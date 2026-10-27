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
/// fetched, newest first, since iCloud promises no order.
final class FakeICloud: Sendable {
    private let database = Mutex(Database())

    /// What the database holds.
    fileprivate struct Database {
        var zones: [ICloudZone: Zone] = [:]
        /// The last change, which each change's number follows.
        var lastChange = 0
        /// How many times it saved a record.
        var saves = 0
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

    /// The records it holds now, in every zone, for a test that checks what
    /// iCloud keeps.
    var records: [ICloudRecord] {
        database.withLock { $0.zones.values.flatMap { $0.records.values.map(\.record) } }
    }

    /// Saves `zones`, those it doesn't have yet, and returns them all.
    fileprivate func save(_ zones: [ICloudZone]) -> [ICloudZone] {
        database.withLock { database in
            for zone in zones where database.zones[zone] == nil {
                database.zones[zone] = Zone()
            }
            return zones
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

    /// What changed in each zone since the change `fetchedUpTo` says a
    /// device fetched up to there, newest first, with the change it's up to
    /// then.
    fileprivate func changes(since fetchedUpTo: [String: Int]) -> [(
        zone: ICloudZone, changes: ICloudEvent.FetchedRecordZoneChanges, upTo: Int
    )] {
        database.withLock { database in
            database.zones.sorted { $0.key.name < $1.key.name }.compactMap { zone, records in
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
    /// a new version, or why it isn't.
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
            lastChange += 1
            saves += 1
            let saved = record.with(systemFields: Data("change \(lastChange)".utf8))
            zones[record.id.zone]?.records[record.id.name] = FakeICloud.Stored(record: saved, change: lastChange)
            return .success(saved)
        }
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

    func add(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        state.withLock { state in
            for change in changes {
                state.pendingRecordZoneChanges.removeAll { $0.recordID == change.recordID }
                state.pendingRecordZoneChanges.append(change)
            }
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
    /// long as the delegate's answers leave some waiting.
    func sendChanges() async throws {
        try checkOnline()
        for _ in 0..<10 {
            let (zones, records) = state.withLock { state in
                defer {
                    state.pendingDatabaseChanges = []
                    state.pendingRecordZoneChanges = []
                }
                return (state.pendingDatabaseChanges, state.pendingRecordZoneChanges)
            }
            guard !zones.isEmpty || !records.isEmpty else {
                return try delegate.handle(.stateUpdate(serialization()), from: self)
            }
            if !zones.isEmpty {
                let saved = iCloud.save(zones.compactMap(\.zoneToSave))
                try delegate.handle(
                    .sentDatabaseChanges(
                        ICloudEvent.SentDatabaseChanges(
                            savedZones: saved, failedZoneSaves: [], deletedZones: [], failedZoneDeletes: [:])),
                    from: self)
            }
            var toSave: [ICloudRecord] = []
            var toDelete: [ICloudRecordID] = []
            for change in records {
                switch change {
                case .saveRecord(let id):
                    // A record the delegate no longer has stops waiting, as
                    // Apple's sample does.
                    if let record = try delegate.recordToSave(id) {
                        toSave.append(record)
                    }
                case .deleteRecord(let id):
                    toDelete.append(id)
                }
            }
            if !toSave.isEmpty || !toDelete.isEmpty {
                try delegate.handle(
                    .sentRecordZoneChanges(iCloud.modify(saving: toSave, deleting: toDelete)), from: self)
            }
        }
        Issue.record("The device kept sending: each answer left changes waiting.")
    }

    /// Fetches what changed in each zone since it last did, and saves how far
    /// it fetched.
    func fetchChanges() async throws {
        try checkOnline()
        let fetchedUpTo = state.withLock(\.fetchedUpTo)
        for (zone, changes, upTo) in iCloud.changes(since: fetchedUpTo) {
            try delegate.handle(.fetchedRecordZoneChanges(changes), from: self)
            state.withLock { $0.fetchedUpTo[zone.name] = upTo }
        }
        try delegate.handle(.stateUpdate(serialization()), from: self)
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
