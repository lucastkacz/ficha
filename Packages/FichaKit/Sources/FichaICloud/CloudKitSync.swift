import CloudKit
import FichaData
import Foundation
import os

/// The adapter's log: what CloudKit's engine did, event by event, and why it
/// couldn't do what sync asked.
let iCloudLogger = Logger(subsystem: "com.lucastkacz.ficha", category: "icloud")

/// One device's sync through the user's private database in iCloud (ADR
/// 0017): it starts CloudKit's `CKSyncEngine` and is its delegate, handing
/// sync's rules, `Sync`, each event and request, converted, through
/// `CloudKitSyncEngine`. The engine syncs while the app runs: on push, and on
/// its own schedule, as `CKSyncEngine` does with automatic sync on. Being an
/// actor, it hands `Sync` one event at a time, whether from the engine or
/// from records it asked iCloud for.
///
/// An engine that syncs on its own fetches only on push: asked to fetch, it
/// asks iCloud nothing unless a push came, whatever its documentation says,
/// as #316 probed. So, to fetch what changed while the app didn't run, or
/// right now, the device catches up first through an engine that doesn't
/// sync on its own, which asks iCloud each time, and then starts its own
/// engine from the state that one left. Catching up this way is our own.
///
/// The app makes one per device, calls `start()`, and then
/// `sendWhatChanged()` whenever the device's database changes. It never
/// makes one in a process without iCloud's entitlements, such as the CLI,
/// `swift test` or `make render`: CloudKit stops a process that makes a
/// container without them, as #316 probed.
public actor CloudKitSync: CKSyncEngineDelegate {
    /// The iCloud container both apps sync through, in the environment their
    /// entitlements name: Development for Ficha Dev, Production for the real
    /// Ficha.
    public static let containerIdentifier = "iCloud.com.lucastkacz.ficha"

    private let sync: Sync
    /// Which device it is, for the log.
    private let device: String
    /// CloudKit's engine, which syncs on its own, while it runs.
    private var syncEngine: CKSyncEngine?
    /// The engine that catches up on what changed in iCloud, while it does.
    private var catchingUp: CKSyncEngine?
    /// Whether the device is starting its engine, catching up first.
    private var isStarting = false
    /// Whether the engine is sending changes, which a fetch now waits for.
    private var isSending = false
    /// Whether a fetch now waits for the engine to finish sending.
    private var fetchesAfterSending = false
    /// What to do once the engine sent changes that iCloud took, if anything.
    private var afterSending: (@Sendable () async -> Void)?
    /// Whether iCloud took a change since the engine last finished sending.
    private var sentSomething = false

    /// The sync of the device whose database `engine` opens, named `device`
    /// in the log.
    public init(engine: Engine, device: String) {
        sync = Sync(engine: engine)
        self.device = device
    }

    /// Starts syncing. On a device that synced before, it catches up on what
    /// changed in iCloud since, and then starts CloudKit's engine from the
    /// state the device saved last, and hands it every change that waits; on
    /// one that never did, the engine fetches everything as it starts. A
    /// saved state it can't read leaves sync off, and the log says why:
    /// starting from none would fetch everything again as a new device.
    public func start() async {
        guard syncEngine == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            if let saved = try sync.savedState() {
                await catchUp(from: try CKSyncEngine.State.Serialization(saved: saved))
            }
            let state = try sync.savedState().map { try CKSyncEngine.State.Serialization(saved: $0) }
            let engine = Self.engine(from: state, delegate: self, syncingOnItsOwn: true)
            syncEngine = engine
            iCloudLogger.notice(
                "\(self.device, privacy: .public) starts syncing, \(state == nil ? "for the first time" : "from its saved state", privacy: .public)"
            )
            try sync.start(with: CloudKitSyncEngine(engine: engine, device: self))
        } catch {
            iCloudLogger.fault(
                "\(self.device, privacy: .public) can't start syncing: \(String(describing: error), privacy: .public)")
        }
    }

    /// Fetches what changed in iCloud since `state` through an engine that
    /// doesn't sync on its own, whose events `Sync` handles as the device's
    /// engine's: what it fetched, and the state it leaves, which it tells of
    /// a moment after it fetched. Without a connection, it ends with an error,
    /// or once the connection is back.
    private func catchUp(from state: CKSyncEngine.State.Serialization) async {
        let engine = Self.engine(from: state, delegate: self, syncingOnItsOwn: false)
        catchingUp = engine
        do {
            try await engine.fetchChanges()
        } catch {
            iCloudLogger.error(
                "\(self.device, privacy: .public) couldn't catch up on what changed in iCloud: \(String(describing: error), privacy: .public)"
            )
        }
        try? await Task.sleep(for: .milliseconds(500))
        catchingUp = nil
    }

    /// CloudKit's engine on the user's private database in Ficha's container,
    /// from `state`, which hands its events to `delegate`, and syncs on its
    /// own or only when asked.
    private static func engine(
        from state: CKSyncEngine.State.Serialization?, delegate: CloudKitSync, syncingOnItsOwn: Bool
    ) -> CKSyncEngine {
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        var configuration = CKSyncEngine.Configuration(
            database: database, stateSerialization: state, delegate: delegate)
        configuration.automaticallySync = syncingOnItsOwn
        return CKSyncEngine(configuration)
    }

    /// Hands the engine the changes that wait, as the database changed,
    /// whichever process changed it.
    public func sendWhatChanged() {
        guard let syncEngine else { return }
        do {
            try sync.sendWhatChanged(to: CloudKitSyncEngine(engine: syncEngine, device: self))
        } catch {
            iCloudLogger.error(
                "\(self.device, privacy: .public) couldn't hand iCloud what changed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Sends what waits and fetches what changed now, instead of when the
    /// engine would on its own, as Ficha Dev's debug menu does.
    public func syncNow() async {
        if let syncEngine {
            do {
                try await syncEngine.sendChanges()
            } catch {
                iCloudLogger.error(
                    "\(self.device, privacy: .public) couldn't send now: \(String(describing: error), privacy: .public)"
                )
            }
        }
        await fetchNow()
    }

    /// Fetches what changed in iCloud now, instead of on the next push: the
    /// device lets its engine go, catches up and starts a new one. While the
    /// engine sends, it waits until it's done, so that a large file's upload
    /// isn't cut short. What changes meanwhile waits in the database, which
    /// the new engine takes as it starts. The engine let go isn't cancelled,
    /// since `CKSyncEngine.cancelOperations()` stops the app, as #316 found:
    /// it sends no more records, and what it tells is left aside.
    public func fetchNow() async {
        guard syncEngine != nil else { return }
        guard !isSending else {
            fetchesAfterSending = true
            return
        }
        syncEngine = nil
        await start()
    }

    /// Does `work` each time the engine finished sending changes that iCloud
    /// took, as Ficha Dev's second device does to have the other device
    /// fetch them: iCloud doesn't push a change to the device that made it,
    /// and both run on one Mac.
    public func afterSending(_ work: @escaping @Sendable () async -> Void) {
        afterSending = work
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // An engine the device stopped may still tell of what it did, which
        // the new one does again.
        guard syncEngine === self.syncEngine || syncEngine === catchingUp else { return }
        log(event)
        switch event {
        case .willSendChanges:
            isSending = true
        case .sentRecordZoneChanges(let sent) where !sent.savedRecords.isEmpty || !sent.deletedRecordIDs.isEmpty:
            sentSomething = true
        case .didSendChanges:
            // Detached, since CloudKit stops the app when its engine is asked
            // to do something by a task this event started, as #316 found.
            isSending = false
            if sentSomething, let afterSending {
                Task.detached { await afterSending() }
            }
            sentSomething = false
            if fetchesAfterSending {
                fetchesAfterSending = false
                Task.detached { await self.fetchNow() }
            }
        default:
            break
        }
        let converted: ICloudEvent?
        do {
            converted = try ICloudEvent(event)
        } catch {
            return iCloudLogger.fault(
                "\(self.device, privacy: .public) can't read an event of iCloud's engine: \(String(describing: error), privacy: .public)"
            )
        }
        guard let converted else { return }
        do {
            try sync.handle(converted, from: CloudKitSyncEngine(engine: syncEngine, device: self))
        } catch {
            iCloudLogger.error(
                "\(self.device, privacy: .public) couldn't handle an event of iCloud's engine: \(String(describing: error), privacy: .public)"
            )
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine)
        async -> CKSyncEngine.RecordZoneChangeBatch?
    {
        // An engine the device stopped sends nothing more.
        guard syncEngine === self.syncEngine else { return nil }
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let iCloud = CloudKitSyncEngine(engine: syncEngine, device: self)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await self.recordToSave(id, from: iCloud)
        }
    }

    /// The record the engine saves for `id`, as `Sync` builds it, or nil when
    /// the device no longer holds it, or when it can't be built, which the
    /// log says: the engine then skips it, and it keeps waiting.
    private func recordToSave(_ id: CKRecord.ID, from iCloud: CloudKitSyncEngine) -> CKRecord? {
        do {
            return try sync.recordToSave(ICloudRecordID(id), from: iCloud)?.toSave()
        } catch {
            iCloudLogger.error(
                "\(self.device, privacy: .public) couldn't build a record of the zone \(id.zoneID.zoneName, privacy: .public) to send: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    /// Asks iCloud for the records `records` name, and hands `Sync` those it
    /// holds as fetched changes, and those it lacks as deleted, while the
    /// fetched records, and so their files, are still at hand.
    func fetch(_ records: [(id: ICloudRecordID, type: String)], through iCloud: CloudKitSyncEngine) async {
        let results: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            results = try await iCloud.engine.database.records(for: records.map { CKRecord.ID($0.id) })
        } catch {
            return iCloudLogger.error(
                "\(self.device, privacy: .public) couldn't ask iCloud for \(records.count) records: \(String(describing: error), privacy: .public)"
            )
        }
        var modifications: [ICloudRecord] = []
        var deletions: [ICloudEvent.RecordDeletion] = []
        for (id, type) in records {
            switch results[CKRecord.ID(id)] {
            case .success(let record):
                modifications += ICloudRecord.all([record])
            case .failure(let error as CKError) where error.code == .unknownItem:
                deletions.append(ICloudEvent.RecordDeletion(id: id, type: type))
            case .failure(let error):
                iCloudLogger.error(
                    "\(self.device, privacy: .public) couldn't get a record of type \(type, privacy: .public) from iCloud: \(String(describing: error), privacy: .public)"
                )
            case nil:
                iCloudLogger.error(
                    "iCloud didn't answer \(self.device, privacy: .public) for a record of type \(type, privacy: .public)"
                )
            }
        }
        iCloudLogger.info(
            "\(self.device, privacy: .public) asked iCloud again for \(records.count) records: \(modifications.count) came, \(deletions.count) are gone"
        )
        do {
            try sync.handle(
                .fetchedRecordZoneChanges(
                    ICloudEvent.FetchedRecordZoneChanges(modifications: modifications, deletions: deletions)),
                from: iCloud)
        } catch {
            iCloudLogger.error(
                "\(self.device, privacy: .public) couldn't take the records it asked for: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Logs what the engine did, for the probes and for a device that
    /// doesn't sync: counts and zones, never a card's content.
    private func log(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate:
            iCloudLogger.debug("\(self.device, privacy: .public): the engine's state changed")
        case .accountChange:
            // Sync logs which change it was, without the account's record.
            break
        case .fetchedDatabaseChanges(let changes):
            iCloudLogger.info(
                "\(self.device, privacy: .public) fetched zones: \(changes.modifications.map(\.zoneID.zoneName), privacy: .public) changed, \(changes.deletions.map { "\($0.zoneID.zoneName) (\($0.reason))" }, privacy: .public) left"
            )
        case .fetchedRecordZoneChanges(let changes):
            iCloudLogger.info(
                "\(self.device, privacy: .public) fetched \(changes.modifications.count) records and \(changes.deletions.count) deletions: \(Self.countByType(changes.modifications.map(\.record.recordType) + changes.deletions.map { "\($0.recordType) deleted" }), privacy: .public)"
            )
        case .sentDatabaseChanges(let sent):
            iCloudLogger.info(
                "\(self.device, privacy: .public) sent zones: \(sent.savedZones.map(\.zoneID.zoneName), privacy: .public) saved, \(sent.deletedZoneIDs.map(\.zoneName), privacy: .public) deleted, \(sent.failedZoneSaves.map { "\($0.zone.zoneID.zoneName): \($0.error.code.rawValue)" }, privacy: .public) failed"
            )
        case .sentRecordZoneChanges(let sent):
            iCloudLogger.info(
                "\(self.device, privacy: .public) sent records: \(sent.savedRecords.count) saved, \(sent.deletedRecordIDs.count) deleted, failed: \(Self.countByType(sent.failedRecordSaves.map { "\($0.record.recordType) \($0.error.code.rawValue)" } + sent.failedRecordDeletes.values.map { "deletion \($0.code.rawValue)" }), privacy: .public)"
            )
        case .willFetchChanges(let will):
            iCloudLogger.info(
                "\(self.device, privacy: .public) will fetch changes (\(String(describing: will.context.reason), privacy: .public))"
            )
        case .didFetchRecordZoneChanges(let did):
            if let error = did.error {
                iCloudLogger.error(
                    "\(self.device, privacy: .public) couldn't fetch the zone \(did.zoneID.zoneName, privacy: .public): \(error.code.rawValue) \(String(describing: error), privacy: .public)"
                )
            }
        case .didFetchChanges:
            iCloudLogger.info("\(self.device, privacy: .public) fetched every change")
        case .willSendChanges(let will):
            iCloudLogger.info(
                "\(self.device, privacy: .public) will send changes (\(String(describing: will.context.reason), privacy: .public))"
            )
        case .didSendChanges(let did):
            iCloudLogger.info(
                "\(self.device, privacy: .public) sent its changes (\(String(describing: did.context.reason), privacy: .public)), \(self.syncEngine?.state.pendingRecordZoneChanges.count ?? 0) still wait"
            )
        case .willFetchRecordZoneChanges:
            break
        @unknown default:
            iCloudLogger.notice("\(self.device, privacy: .public): an event this version doesn't know: \(event)")
        }
    }

    /// How many of each kind `kinds` holds, as "card ×2, tag ×1", for the log.
    private static func countByType(_ kinds: [String]) -> String {
        Dictionary(kinds.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.key < $1.key }
            .map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
    }
}

/// CloudKit's engine as sync reaches it, `ICloudSyncEngine`: each call goes
/// to `CKSyncEngine`, converted, and the records sync asks for come back
/// through the device's `CloudKitSync`.
struct CloudKitSyncEngine: ICloudSyncEngine {
    let engine: CKSyncEngine
    let device: CloudKitSync

    func add(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        engine.state.add(pendingRecordZoneChanges: changes.map(CKSyncEngine.PendingRecordZoneChange.init))
    }

    func remove(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        engine.state.remove(pendingRecordZoneChanges: changes.map(CKSyncEngine.PendingRecordZoneChange.init))
    }

    func add(pendingDatabaseChanges changes: [ICloudPendingDatabaseChange]) {
        engine.state.add(pendingDatabaseChanges: changes.map(CKSyncEngine.PendingDatabaseChange.init))
    }

    func sendChanges() async throws {
        try await engine.sendChanges()
    }

    func fetchChanges() async throws {
        try await engine.fetchChanges()
    }

    func fetchRecords(_ records: [(id: ICloudRecordID, type: String)]) {
        Task { await device.fetch(records, through: self) }
    }
}
