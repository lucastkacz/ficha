import FichaCore
import Foundation
import Synchronization
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// what waits to be sent.
@testable import FichaData

/// The user's private database in iCloud, in memory, which a test's devices
/// share, each through a `FakeSyncEngine` of its own (ADR 0017). It keeps
/// records as iCloud does: by zone and name, each version with a change tag
/// of its own, in its system fields. It saves a record only for a device
/// that heard of its latest version, and otherwise answers with the record
/// as it is (`serverRecordChanged`), refuses a record in a zone it doesn't
/// have (`zoneNotFound`) and one a device heard of that it no longer has
/// (`unknownItem`). It hands each device what changed since that device last
/// fetched, newest first, since iCloud promises no order. It keeps each
/// record's files apart, as `CKAsset`s, in a folder of its own: a copy of
/// each file a device sends, which a device that fetches the record reads.
final class FakeICloud: Sendable {
    private let database: Mutex<Database>
    /// Where it keeps the records' files.
    private let assets = URL.temporaryDirectory.appending(
        path: "FakeICloud-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() {
        database = Mutex(Database(assets: assets))
    }

    deinit {
        try? FileManager.default.removeItem(at: assets)
    }

    /// What the database holds.
    fileprivate struct Database {
        var zones: [ICloudZone: Zone] = [:]
        /// The last change, which each change's number follows.
        var lastChange = 0
        /// How many times it saved a record.
        var saves = 0
        /// How many times a device sent each record to save, saved or not.
        var sends: [ICloudRecordID: Int] = [:]
        /// Where it keeps the records' files.
        let assets: URL
    }

    /// A zone's records, and those deleted, by name.
    fileprivate struct Zone {
        var records: [String: Stored] = [:]
        var deletions: [String: (type: String, change: Int)] = [:]
    }

    /// A record as iCloud holds it, with the change that saved it.
    fileprivate struct Stored {
        let record: ICloudRecord
        let change: Int
    }

    /// How many times it saved a record, for a test that checks a device sent
    /// nothing.
    var saves: Int {
        database.withLock(\.saves)
    }

    /// How many times the devices sent the record with this ID to save,
    /// whether it saved it or not.
    func timesSent(_ id: ICloudRecordID) -> Int {
        database.withLock { $0.sends[id] ?? 0 }
    }

    /// The records it holds now, in every zone, for a test that checks what
    /// iCloud keeps.
    var records: [ICloudRecord] {
        database.withLock { $0.zones.values.flatMap { $0.records.values.map(\.record) } }
    }

    /// The records `asked` name, as it holds them now, and as deleted, with
    /// the type asked for, those it doesn't hold, as `CKDatabase.records(for:)`
    /// answers `unknownItem` for a record it deleted or never had.
    fileprivate func records(_ asked: [(id: ICloudRecordID, type: String)]) -> ICloudEvent.FetchedRecordZoneChanges {
        database.withLock { database in
            let held = asked.compactMap { database.zones[$0.id.zone]?.records[$0.id.name]?.record }
            return ICloudEvent.FetchedRecordZoneChanges(
                modifications: held,
                deletions: asked.filter { record in !held.contains { $0.id == record.id } }.map {
                    ICloudEvent.RecordDeletion(id: $0.id, type: $0.type)
                })
        }
    }

    /// Saves `record` as a device with a newer Ficha would, in a zone it
    /// has, for a test.
    func saveFromANewerFicha(_ record: ICloudRecord) {
        database.withLock { database in
            _ = database.save(record)
        }
    }

    /// Saves `zones`, those it doesn't have yet.
    fileprivate func save(_ zones: [ICloudZone]) {
        database.withLock { database in
            for zone in zones where database.zones[zone] == nil {
                database.zones[zone] = Zone()
            }
        }
    }

    /// Saves `records` and deletes the records `deletions` name, as
    /// `CKModifyRecordsOperation` does with the policy `CKSyncEngine` saves
    /// with.
    fileprivate func modify(saving records: [ICloudRecord], deleting deletions: [ICloudRecordID])
        -> ICloudEvent.SentRecordZoneChanges
    {
        database.withLock { database in
            var saved: [ICloudRecord] = []
            var failed: [ICloudEvent.FailedRecordSave] = []
            for record in records {
                database.sends[record.id, default: 0] += 1
                switch database.save(record) {
                case .success(let record): saved.append(record)
                case .failure(let error): failed.append(ICloudEvent.FailedRecordSave(record: record, error: error))
                }
            }
            var deleted: [ICloudRecordID] = []
            var failedDeletes: [ICloudRecordID: ICloudError] = [:]
            for id in deletions {
                guard database.zones[id.zone] != nil else {
                    failedDeletes[id] = .zoneNotFound
                    continue
                }
                if let stored = database.zones[id.zone]?.records.removeValue(forKey: id.name) {
                    database.lastChange += 1
                    database.zones[id.zone]?.deletions[id.name] = (stored.record.type, database.lastChange)
                }
                deleted.append(id)
            }
            return ICloudEvent.SentRecordZoneChanges(
                savedRecords: saved, failedRecordSaves: failed, deletedRecordIDs: deleted,
                failedRecordDeletes: failedDeletes)
        }
    }

    /// What changed in each zone, or in each of `zones` when it says which,
    /// since the change `fetchedUpTo` says a device fetched up to there,
    /// newest first, with the change it's up to then.
    fileprivate func changes(since fetchedUpTo: [String: Int], in zones: Set<ICloudZone>?) -> [(
        zone: ICloudZone, changes: ICloudEvent.FetchedRecordZoneChanges, upTo: Int
    )] {
        database.withLock { database in
            database.zones.filter { zones?.contains($0.key) ?? true }.sorted { $0.key.name < $1.key.name }.compactMap {
                zone, records in
                let since = fetchedUpTo[zone.name] ?? 0
                let saved = records.records.values.filter { $0.change > since }.sorted { $0.change > $1.change }
                let deleted = records.deletions.filter { $0.value.change > since }
                    .sorted { $0.value.change > $1.value.change }
                guard !saved.isEmpty || !deleted.isEmpty else {
                    return nil
                }
                let changes = ICloudEvent.FetchedRecordZoneChanges(
                    modifications: saved.map(\.record),
                    deletions: deleted.map { name, deletion in
                        ICloudEvent.RecordDeletion(id: ICloudRecordID(name: name, zone: zone), type: deletion.type)
                    })
                let upTo = max(saved.first?.change ?? 0, deleted.first?.value.change ?? 0)
                return (zone, changes, upTo)
            }
        }
    }
}

extension FakeICloud.Database {
    /// Saves `record`, when the device that sends it heard of its latest
    /// version or of none, and returns it as saved, with the system fields of
    /// a new version, or why it isn't. A record saved with none after it was
    /// deleted is a new one, as in CloudKit: a device that fetches from
    /// before the deletion gets it, and not the deletion.
    fileprivate mutating func save(_ record: ICloudRecord) -> Result<ICloudRecord, ICloudError> {
        guard let zone = zones[record.id.zone] else {
            return .failure(.zoneNotFound)
        }
        switch (zone.records[record.id.name], record.systemFields) {
        case (let stored?, let systemFields) where stored.record.systemFields != systemFields:
            return .failure(.serverRecordChanged(stored.record))
        case (nil, _?):
            return .failure(.unknownItem)
        default:
            let fields: [String: ICloudValue?]
            do {
                fields = try record.fields.mapValues(keepingAssets)
            } catch {
                return .failure(.other("assetFileNotFound"))
            }
            lastChange += 1
            saves += 1
            let saved = ICloudRecord(
                id: record.id, type: record.type, fields: fields, systemFields: Data("change \(lastChange)".utf8))
            zones[record.id.zone]?.records[record.id.name] = FakeICloud.Stored(record: saved, change: lastChange)
            zones[record.id.zone]?.deletions[record.id.name] = nil
            return .success(saved)
        }
    }

    /// `value` as it keeps it: a file a device sent, copied into its folder,
    /// as iCloud uploads it, and any other value as it is.
    private func keepingAssets(_ value: ICloudValue?) throws -> ICloudValue? {
        guard case .asset(let file)? = value else {
            return value
        }
        let copy = assets.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: copy)
        return .asset(copy)
    }
}

/// A device's way to the fake iCloud, as `CKSyncEngine` is the app's: it
/// keeps the changes waiting to be sent and how far the device fetched, which
/// it hands `Sync` as its state, and tells `Sync`, its delegate, of each
/// event. It sends and fetches only when asked, as `CKSyncEngine` does with
/// automatic sync off, and it can go offline.
final class FakeSyncEngine: ICloudSyncEngine {
    private let iCloud: FakeICloud
    private let delegate: Sync
    private let state: Mutex<State>
    private let offline = Mutex(false)
    private let losingFetchedFiles = Mutex(false)
    private let gettingItsOwnSavesBack = Mutex(true)
    /// The system fields of the version of each record it saved last.
    private let ownSaves = Mutex<[ICloudRecordID: Data]>([:])
    private let whileSaving = Mutex<(@Sendable () throws -> Void)?>(nil)
    /// The records the device asked for, which it gets at its next fetch.
    private let asked = Mutex<[(id: ICloudRecordID, type: String)]>([])

    /// What it keeps, which `CKSyncEngine` saves through its state's
    /// serialization.
    private struct State: Codable {
        var pendingRecordZoneChanges: [ICloudPendingRecordZoneChange] = []
        var pendingDatabaseChanges: [ICloudPendingDatabaseChange] = []
        /// The last change it fetched of each zone, by name.
        var fetchedUpTo: [String: Int] = [:]
    }

    /// The engine of a device that reaches `iCloud`, telling `delegate` of
    /// each event, from the state it saved last, or from nothing.
    init(iCloud: FakeICloud, delegate: Sync, stateSerialization: Data?) throws {
        self.iCloud = iCloud
        self.delegate = delegate
        state = Mutex(try stateSerialization.map { try JSONDecoder().decode(State.self, from: $0) } ?? State())
    }

    /// Whether it's offline: then sending and fetching fail, and the changes
    /// keep waiting.
    var isOffline: Bool {
        get { offline.withLock { $0 } }
        set { offline.withLock { $0 = newValue } }
    }

    /// Whether the files of the records it fetches are gone before the
    /// device reads them, as when the device can't copy them out of the
    /// folder the system cleans.
    var losesFetchedFiles: Bool {
        get { losingFetchedFiles.withLock { $0 } }
        set { losingFetchedFiles.withLock { $0 = newValue } }
    }

    /// Whether a fetch hands it back the records it saved itself, as they
    /// are until another device saves them. The fake does, unless a test
    /// says otherwise; CloudKit usually doesn't, but may (Apple's developer
    /// forums, thread 774014).
    var getsItsOwnSavesBack: Bool {
        get { gettingItsOwnSavesBack.withLock { $0 } }
        set { gettingItsOwnSavesBack.withLock { $0 = newValue } }
    }

    /// Runs `work` once, after iCloud saves the next records it sends and
    /// before it tells the device: a change the user makes while an upload
    /// is on its way.
    func onceSaved(_ work: @escaping @Sendable () throws -> Void) {
        whileSaving.withLock { $0 = work }
    }

    func add(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        state.withLock { state in
            for change in changes {
                state.pendingRecordZoneChanges.removeAll { $0.recordID == change.recordID }
                state.pendingRecordZoneChanges.append(change)
            }
        }
    }

    func remove(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        state.withLock { state in
            state.pendingRecordZoneChanges.removeAll(where: changes.contains)
        }
    }

    func add(pendingDatabaseChanges changes: [ICloudPendingDatabaseChange]) {
        state.withLock { state in
            for change in changes {
                state.pendingDatabaseChanges.removeAll { $0.zone == change.zone }
                state.pendingDatabaseChanges.append(change)
            }
        }
    }

    /// The changes waiting to be sent, for a test.
    var pendingRecordZoneChanges: [ICloudPendingRecordZoneChange] {
        state.withLock(\.pendingRecordZoneChanges)
    }

    /// Sends the zones and then the records waiting, a batch at a time, as
    /// long as the delegate's answers leave some to send. A save whose record
    /// the delegate doesn't give keeps waiting, as `CKSyncEngine` keeps it,
    /// until the delegate removes it.
    func sendChanges() async throws {
        try checkOnline()
        for _ in 0..<10 {
            let zones = state.withLock { state in
                defer { state.pendingDatabaseChanges = [] }
                return state.pendingDatabaseChanges
            }
            if !zones.isEmpty {
                iCloud.save(zones.compactMap(\.zoneToSave))
                try delegate.handle(
                    .sentDatabaseChanges(ICloudEvent.SentDatabaseChanges(failedZoneSaves: [])), from: self)
            }
            var toSave: [ICloudRecord] = []
            var toDelete: [ICloudRecordID] = []
            for change in pendingRecordZoneChanges {
                switch change {
                case .saveRecord(let id):
                    guard let record = try delegate.recordToSave(id, from: self) else {
                        continue
                    }
                    toSave.append(record)
                case .deleteRecord(let id):
                    toDelete.append(id)
                }
                state.withLock { $0.pendingRecordZoneChanges.removeAll { $0 == change } }
            }
            guard !zones.isEmpty || !toSave.isEmpty || !toDelete.isEmpty else {
                return try delegate.handle(.stateUpdate(serialization()), from: self)
            }
            if !toSave.isEmpty || !toDelete.isEmpty {
                let sent = iCloud.modify(saving: toSave, deleting: toDelete)
                ownSaves.withLock { saves in
                    for record in sent.savedRecords {
                        saves[record.id] = record.systemFields
                    }
                }
                try whileSaving.withLock { work in
                    defer { work = nil }
                    return work
                }?()
                try delegate.handle(.sentRecordZoneChanges(sent), from: self)
            }
        }
        Issue.record("The device kept sending: each answer left changes waiting.")
    }

    /// Fetches what changed in each zone since it last did, and saves how far
    /// it fetched.
    func fetchChanges() async throws {
        try await fetchChanges(in: nil)
    }

    /// Asks for the records `records` name, which it hands the device at its
    /// next fetch: the app's engine hands them over whenever iCloud answers.
    func fetchRecords(_ records: [(id: ICloudRecordID, type: String)]) {
        asked.withLock { asked in
            asked.append(contentsOf: records.filter { record in !asked.contains { $0.id == record.id } })
        }
    }

    /// Fetches what changed in each of `zones` since it last did, or in every
    /// zone when it's nil, as `CKSyncEngine.fetchChanges(_:)` does with a
    /// scope of zones, then the records the device asked for, says it
    /// fetched it all, and saves how far it fetched.
    func fetchChanges(in zones: Set<ICloudZone>?) async throws {
        try checkOnline()
        let fetchedUpTo = state.withLock(\.fetchedUpTo)
        for (zone, changes, upTo) in iCloud.changes(since: fetchedUpTo, in: zones) {
            try delegate.handle(.fetchedRecordZoneChanges(losingFiles(withoutItsOwnSaves(changes))), from: self)
            state.withLock { $0.fetchedUpTo[zone.name] = upTo }
        }
        let asked = asked.withLock { asked in
            defer { asked = [] }
            return asked
        }
        if !asked.isEmpty {
            try delegate.handle(.fetchedRecordZoneChanges(losingFiles(iCloud.records(asked))), from: self)
        }
        try delegate.handle(.didFetchChanges, from: self)
        try delegate.handle(.stateUpdate(serialization()), from: self)
    }

    /// `changes` without the records it saved itself, as they are until
    /// another device saves them, when it doesn't get those back.
    private func withoutItsOwnSaves(_ changes: ICloudEvent.FetchedRecordZoneChanges)
        -> ICloudEvent.FetchedRecordZoneChanges
    {
        guard !getsItsOwnSavesBack else {
            return changes
        }
        let saves = ownSaves.withLock { $0 }
        return ICloudEvent.FetchedRecordZoneChanges(
            modifications: changes.modifications.filter { saves[$0.id] != $0.systemFields },
            deletions: changes.deletions)
    }

    /// `changes` with their files gone, when it loses them.
    private func losingFiles(_ changes: ICloudEvent.FetchedRecordZoneChanges) -> ICloudEvent.FetchedRecordZoneChanges {
        guard losesFetchedFiles else {
            return changes
        }
        return ICloudEvent.FetchedRecordZoneChanges(
            modifications: changes.modifications.map { record in
                ICloudRecord(
                    id: record.id, type: record.type,
                    fields: record.fields.mapValues { value in
                        guard case .asset(let file)? = value else {
                            return value
                        }
                        return .asset(file.deletingLastPathComponent().appending(path: "gone-\(UUID().uuidString)"))
                    }, systemFields: record.systemFields)
            }, deletions: changes.deletions)
    }

    /// Throws when it's offline, as `CKSyncEngine` does when it can't reach
    /// iCloud.
    private func checkOnline() throws {
        if isOffline {
            throw FakeICloudError.offline
        }
    }

    /// Its state, as it saves it.
    private func serialization() throws -> Data {
        try JSONEncoder().encode(state.withLock { $0 })
    }
}

/// Why a device couldn't reach the fake iCloud.
enum FakeICloudError: Error {
    case offline
}

extension ICloudPendingRecordZoneChange {
    /// The record it changes.
    fileprivate var recordID: ICloudRecordID {
        switch self {
        case .saveRecord(let id), .deleteRecord(let id): id
        }
    }
}

extension ICloudPendingDatabaseChange {
    /// The zone it changes.
    fileprivate var zone: ICloudZone {
        switch self {
        case .saveZone(let zone), .deleteZone(let zone): zone
        }
    }

    /// The zone it saves, or nil when it deletes one.
    fileprivate var zoneToSave: ICloudZone? {
        switch self {
        case .saveZone(let zone): zone
        case .deleteZone: nil
        }
    }
}

/// One of the user's devices in a test: an engine, in memory or on a data
/// folder, whose sync reaches the fake iCloud as the app's does.
struct Device {
    let engine: Engine
    let sync: Sync
    let iCloud: FakeSyncEngine

    /// The device `engine` runs, which starts syncing through `iCloud`, from
    /// the state its engine saved last, as the app does when it launches.
    init(_ engine: Engine, syncingThrough iCloud: FakeICloud) throws {
        self.engine = engine
        sync = Sync(engine: engine)
        self.iCloud = try FakeSyncEngine(
            iCloud: iCloud, delegate: sync, stateSerialization: engine.savedSyncEngineState())
        try sync.start(with: self.iCloud)
    }

    /// Syncs as the app does once it hears the database changed and iCloud
    /// tells it of other devices' changes: hands iCloud's engine the changes
    /// waiting, sends them, and fetches what changed.
    func syncNow() async throws {
        try sync.sendWhatChanged(to: iCloud)
        try await iCloud.sendChanges()
        try await iCloud.fetchChanges()
    }
}
