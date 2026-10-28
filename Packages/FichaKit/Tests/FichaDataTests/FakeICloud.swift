import FichaCore
import Foundation
import Synchronization
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// what waits to be sent.
@testable import FichaData

/// One iCloud account's private database, in memory, which a test's devices
/// signed into it share, each through a `FakeSyncEngine` of its own (ADR
/// 0017). It keeps records as iCloud does: by zone and name, each version
/// with a change tag of its own, in its system fields. It saves a record only
/// for a device that heard of its latest version, and otherwise answers with
/// the record as it is (`serverRecordChanged`), refuses a record in a zone it
/// doesn't have (`zoneNotFound`) and one a device heard of that it no longer
/// has (`unknownItem`). It hands each device what changed since that device
/// last fetched, newest first, since iCloud promises no order. It keeps each
/// record's files apart, as `CKAsset`s, in a folder of its own: a copy of
/// each file a device sends, which a device that fetches the record reads.
///
/// It can be purged, as when the user deletes Ficha's data in iCloud's
/// settings: every zone goes, each device that fetches hears it was purged,
/// and a zone purged refuses records (`userDeletedZone`) until a device saves
/// it again. A zone deleted and saved again before a device fetched reaches
/// it as changed, with no deletion, as P16 found (#316).
///
/// It can fill up: given room for so many bytes, it refuses a record that
/// doesn't fit (`quotaExceeded`), and a zone once nothing fits, while it
/// takes every deletion. Where it differs from iCloud: a record's size is
/// its fields' bytes alone, its text's in UTF-8, eight for a number and the
/// file's for an asset, where iCloud counts what it likes; and CloudKit's
/// documentation doesn't say whether a zone counts, so the fake, being the
/// less forgiving, refuses one when nothing fits.
final class FakeICloud: Sendable {
    /// Who signed into the account, as the user record's ID tells accounts
    /// apart in `CKSyncEngine.Event.AccountChange`.
    let user = UUID()
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
        /// The zones that left, why, and the change that took them, until
        /// they're saved again.
        var zoneDeletions: [ICloudZone: (reason: ICloudEvent.ZoneDeletion.Reason, change: Int)] = [:]
        /// The last change, which each change's number follows.
        var lastChange = 0
        /// How many times it saved a record.
        var saves = 0
        /// How many times a device sent each record to save, saved or not.
        var sends: [ICloudRecordID: Int] = [:]
        /// How many bytes it has room for, or nil for as many as it's sent.
        var room: Int?
        /// Where it keeps the records' files.
        let assets: URL

        /// How many bytes its records take.
        var used: Int {
            zones.values.reduce(0) { used, zone in zone.records.values.reduce(used) { $0 + $1.size } }
        }
    }

    /// A zone's records, and those deleted, by name.
    fileprivate struct Zone {
        var records: [String: Stored] = [:]
        var deletions: [String: (type: String, change: Int)] = [:]
    }

    /// A record as iCloud holds it, with the change that saved it and how
    /// many bytes it takes.
    fileprivate struct Stored {
        let record: ICloudRecord
        let change: Int
        let size: Int
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

    /// Fills it up: from now on, only what frees room fits.
    func fillUp() {
        database.withLock { $0.room = $0.used }
    }

    /// Leaves room for `bytes` more than it holds now.
    func leaveRoom(forBytes bytes: Int) {
        database.withLock { $0.room = $0.used + bytes }
    }

    /// Makes room for whatever comes, as when the user frees up space or buys
    /// more.
    func makeRoom() {
        database.withLock { $0.room = nil }
    }

    /// Deletes every zone, as the user does when they delete Ficha's data in
    /// iCloud's settings.
    func purge() {
        database.withLock { database in
            for zone in database.zones.keys {
                database.lastChange += 1
                database.zoneDeletions[zone] = (.purged, database.lastChange)
            }
            database.zones = [:]
        }
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

    /// Saves the zones `changes` save, those it doesn't have yet, and deletes
    /// those they delete, as `CKModifyRecordZonesOperation` does, and returns
    /// those it couldn't save, and why: once nothing fits, no zone does.
    fileprivate func modify(_ changes: [ICloudPendingDatabaseChange]) -> [ICloudEvent.FailedZoneSave] {
        database.withLock { database in
            var failed: [ICloudEvent.FailedZoneSave] = []
            for change in changes {
                switch change {
                case .saveZone(let zone) where database.zones[zone] == nil:
                    if let room = database.room, database.used >= room {
                        failed.append(ICloudEvent.FailedZoneSave(zone: zone, error: .quotaExceeded))
                    } else {
                        database.zones[zone] = Zone()
                        database.zoneDeletions[zone] = nil
                    }
                case .saveZone:
                    break
                case .deleteZone(let zone):
                    guard database.zones.removeValue(forKey: zone) != nil else { continue }
                    database.lastChange += 1
                    database.zoneDeletions[zone] = (.deleted, database.lastChange)
                }
            }
            return failed
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
                    failedDeletes[id] =
                        database.zoneDeletions[id.zone]?.reason == .purged ? .userDeletedZone : .zoneNotFound
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

    /// The zones that left since the change `fetchedUpTo` says a device
    /// fetched the database's changes up to, with the change it's up to then.
    fileprivate func zoneDeletions(since fetchedUpTo: Int) -> (deletions: [ICloudEvent.ZoneDeletion], upTo: Int) {
        database.withLock { database in
            (
                database.zoneDeletions.filter { $0.value.change > fetchedUpTo }.sorted { $0.key.name < $1.key.name }
                    .map { ICloudEvent.ZoneDeletion(zone: $0.key, reason: $0.value.reason) },
                database.lastChange
            )
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
    /// version or of none, and it fits, and returns it as saved, with the
    /// system fields of a new version, or why it isn't. A record saved with
    /// none after it was deleted is a new one, as in CloudKit: a device that
    /// fetches from before the deletion gets it, and not the deletion.
    fileprivate mutating func save(_ record: ICloudRecord) -> Result<ICloudRecord, ICloudError> {
        guard let zone = zones[record.id.zone] else {
            return .failure(zoneDeletions[record.id.zone]?.reason == .purged ? .userDeletedZone : .zoneNotFound)
        }
        let stored = zone.records[record.id.name]
        switch (stored, record.systemFields) {
        case (let stored?, let systemFields) where stored.record.systemFields != systemFields:
            return .failure(.serverRecordChanged(stored.record))
        case (nil, _?):
            return .failure(.unknownItem)
        default:
            let size = record.fields.values.reduce(0) { $0 + bytes(of: $1) }
            if let room, used - (stored?.size ?? 0) + size > room {
                return .failure(.quotaExceeded)
            }
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
            zones[record.id.zone]?.records[record.id.name] = FakeICloud.Stored(
                record: saved, change: lastChange, size: size)
            zones[record.id.zone]?.deletions[record.id.name] = nil
            return .success(saved)
        }
    }

    /// How many bytes `value` takes, as the fake counts it.
    private func bytes(of value: ICloudValue?) -> Int {
        switch value {
        case nil: 0
        case .string(let text)?: text.utf8.count
        case .int?, .double?: 8
        case .asset(let file)?: (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
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
/// keeps the changes waiting to be sent, how far the device fetched and the
/// account it last knew of, which it hands `Sync` as its state, and tells
/// `Sync`, its delegate, of each event. It sends and fetches only when asked,
/// as `CKSyncEngine` does with automatic sync off, and it can go offline.
///
/// It reaches the account the device is signed into. As `CKSyncEngine`'s
/// documentation says, it tells of an account change as soon as the device
/// signs in or out, or, for a change made while the app didn't run, once it
/// runs, as one change from the account it last knew of to the one it meets;
/// and as it tells of it, it forgets the changes it was handed and how far it
/// fetched. Signed out, it neither sends nor fetches, as the documentation
/// says it may, keeping what waits. Where it differs from CloudKit: an
/// engine with no saved state tells of no account change, where CloudKit's
/// may tell of a sign-in, since its documentation doesn't say, so Ficha's
/// first sync can't depend on one.
final class FakeSyncEngine: ICloudSyncEngine {
    private let delegate: Sync
    private let state: Mutex<State>
    /// The account the device is signed into now, or nil while it's signed
    /// out.
    private let account: Mutex<FakeICloud?>
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
        /// The last change it fetched of the database's zones.
        var fetchedZonesUpTo = 0
        /// The account it last knew of, or nil before it looked.
        var account: KnownAccount?
    }

    /// An account as the engine knows it: who's signed in, or no one.
    private enum KnownAccount: Codable, Equatable {
        case signedOut
        case signedIn(UUID)

        init(_ account: FakeICloud?) {
            self = account.map { .signedIn($0.user) } ?? .signedOut
        }
    }

    /// The engine of a device signed into `account`, or signed out when it's
    /// nil, telling `delegate` of each event, from the state it saved last,
    /// or from nothing.
    init(account: FakeICloud?, delegate: Sync, stateSerialization: Data?) throws {
        self.delegate = delegate
        self.account = Mutex(account)
        var state = try stateSerialization.map { try JSONDecoder().decode(State.self, from: $0) } ?? State()
        if state.account == nil {
            state.account = KnownAccount(account)
        }
        self.state = Mutex(state)
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

    /// Hears that the device signed into `account`, or out when it's nil,
    /// and tells of it, as `CKSyncEngine` listens for account changes.
    func signedInto(_ account: FakeICloud?) throws {
        self.account.withLock { $0 = account }
        try tellAccountChange()
    }

    /// Tells the delegate of a change from the account it last knew of to
    /// the one the device is signed into, if they differ, forgetting first
    /// every change it was handed and how far it fetched, as `CKSyncEngine`
    /// resets its state.
    private func tellAccountChange() throws {
        let now = KnownAccount(account.withLock { $0 })
        let change: ICloudEvent.AccountChange? = state.withLock { state in
            let change: ICloudEvent.AccountChange? =
                switch (state.account, now) {
                case (.signedOut?, .signedIn): .signIn
                case (.signedIn?, .signedOut): .signOut
                case (.signedIn(let before)?, .signedIn(let after)) where before != after: .switchAccounts
                default: nil
                }
            if change != nil {
                state = State(account: now)
            }
            return change
        }
        guard let change else { return }
        ownSaves.withLock { $0 = [:] }
        asked.withLock { $0 = [] }
        try delegate.handle(.accountChange(change), from: self)
        try delegate.handle(.stateUpdate(serialization()), from: self)
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
    /// until the delegate removes it. A change that failed no longer waits.
    func sendChanges() async throws {
        try checkOnline()
        try tellAccountChange()
        guard let account = account.withLock({ $0 }) else { return }
        for _ in 0..<10 {
            let zones = state.withLock { state in
                defer { state.pendingDatabaseChanges = [] }
                return state.pendingDatabaseChanges
            }
            if !zones.isEmpty {
                let failed = account.modify(zones)
                try delegate.handle(
                    .sentDatabaseChanges(ICloudEvent.SentDatabaseChanges(failedZoneSaves: failed)), from: self)
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
                let sent = account.modify(saving: toSave, deleting: toDelete)
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

    /// Fetches what changed since it last did, and saves how far it fetched.
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

    /// Fetches the zones that left since it last did, forgetting how far it
    /// fetched each; then what changed in each of `zones` since it last did,
    /// or in every zone when it's nil, as `CKSyncEngine.fetchChanges(_:)`
    /// does with a scope of zones; then the records the device asked for;
    /// says it fetched it all, and saves how far it fetched.
    func fetchChanges(in zones: Set<ICloudZone>?) async throws {
        try checkOnline()
        try tellAccountChange()
        guard let account = account.withLock({ $0 }) else { return }
        let (deletions, zonesUpTo) = account.zoneDeletions(since: state.withLock(\.fetchedZonesUpTo))
        if !deletions.isEmpty {
            try delegate.handle(
                .fetchedDatabaseChanges(ICloudEvent.FetchedDatabaseChanges(deletions: deletions)), from: self)
        }
        state.withLock { state in
            state.fetchedZonesUpTo = zonesUpTo
            for deletion in deletions {
                state.fetchedUpTo[deletion.zone.name] = nil
            }
        }
        let fetchedUpTo = state.withLock(\.fetchedUpTo)
        for (zone, changes, upTo) in account.changes(since: fetchedUpTo, in: zones) {
            try delegate.handle(.fetchedRecordZoneChanges(losingFiles(withoutItsOwnSaves(changes))), from: self)
            state.withLock { $0.fetchedUpTo[zone.name] = upTo }
        }
        let asked = asked.withLock { asked in
            defer { asked = [] }
            return asked
        }
        if !asked.isEmpty {
            try delegate.handle(.fetchedRecordZoneChanges(losingFiles(account.records(asked))), from: self)
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
}

/// One of the user's devices in a test: an engine, in memory or on a data
/// folder, whose sync reaches the fake iCloud as the app's does, through the
/// account the device is signed into.
final class Device {
    let engine: Engine
    let sync: Sync
    /// Its way to iCloud: a new one each time the app launches, or turns sync
    /// on.
    private(set) var iCloud: FakeSyncEngine
    /// The account it's signed into, or nil while it's signed out.
    private(set) var account: FakeICloud?

    /// The device `engine` runs, signed into `account`, or signed out when
    /// it's nil, which starts syncing, from the state its engine saved last,
    /// as the app does when it launches: it notes whether the device is
    /// signed in, and starts while sync is on.
    init(_ engine: Engine, syncingThrough account: FakeICloud?) throws {
        self.engine = engine
        self.account = account
        sync = Sync(engine: engine)
        iCloud = try FakeSyncEngine(
            account: account, delegate: sync, stateSerialization: engine.savedSyncEngineState())
        try sync.noteAccount(signedIn: account != nil)
        try sync.start(with: iCloud)
    }

    /// Syncs as the app does once it hears the database changed and iCloud
    /// tells it of other devices' changes: hands iCloud's engine the changes
    /// waiting, sends them, and fetches what changed.
    func syncNow() async throws {
        try sync.sendWhatChanged(to: iCloud)
        try await iCloud.sendChanges()
        try await iCloud.fetchChanges()
    }

    /// Sends what waits, without fetching, as the app's engine does on its
    /// own once the app hands it a change.
    func send() async throws {
        try sync.sendWhatChanged(to: iCloud)
        try await iCloud.sendChanges()
    }

    /// Signs the device out of iCloud, which its engine hears, as the app
    /// does too, whether sync is on or not.
    func signOut() throws {
        account = nil
        try sync.noteAccount(signedIn: false)
        try iCloud.signedInto(nil)
    }

    /// Signs the device into `account`, as `signOut()` does.
    func signIn(to account: FakeICloud) throws {
        self.account = account
        try sync.noteAccount(signedIn: true)
        try iCloud.signedInto(account)
    }

    /// Turns sync on, as the user does in Settings: the app starts a new
    /// engine, from the state the device saved last.
    func turnSyncOn() throws {
        try engine.turnSyncOn()
        try relaunch()
    }

    /// Turns sync off, as the user does in Settings: the app lets its engine
    /// go, and its events are left aside.
    func turnSyncOff() throws {
        try engine.turnSyncOff()
    }

    /// Starts a new engine from the state the device saved last, as the app
    /// does when it launches.
    func relaunch() throws {
        iCloud = try FakeSyncEngine(
            account: account, delegate: sync, stateSerialization: engine.savedSyncEngineState())
        try sync.noteAccount(signedIn: account != nil)
        try sync.start(with: iCloud)
    }
}
