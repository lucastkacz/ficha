import FichaCore
import Foundation
internal import GRDB
import os

/// Sync's log, apart from the engine's, for its files.
let syncLogger = Logger(subsystem: "com.lucastkacz.ficha", category: "sync")

/// Sync's rules (ADR 0017): what `CKSyncEngine`'s delegate does for Ficha,
/// on one device's engine. It hands iCloud's engine the changes recorded to
/// send, the CLI's too, builds each record as its row is when the engine
/// sends it, and applies what other devices changed without recording it to
/// send back: of each field of a card, a capture, a tag or the settings that
/// decide progress, the latest change wins and the rest merges, and the
/// review log's entries join, each card's ways worked out again from them
/// all. A deletion wins over what other devices changed of its row, and what
/// it changes on a device goes back as that device's own change
/// (`SyncedDeletions.swift`). The images and sounds on cards travel apart, in
/// a zone of their own, as `SyncedFiles.swift` says. Each device keeps
/// working without a connection: what waits is sent once iCloud's engine
/// reaches iCloud, and so is what didn't fit in a full iCloud, once there's
/// room. An account change never deletes a card: signed out, sync stops;
/// signed into an account, the device's rows join its records, as in a first
/// sync. A purge of Ficha's data in iCloud's settings turns sync off, with
/// the cards kept. What the Sync tab and the menu read of it all is
/// `SyncStatus`.
///
/// The app makes one when sync starts, tells it whether the device is signed
/// into iCloud (`noteAccount(signedIn:)`), calls `start(with:)` while sync is
/// on, then `sendWhatChanged(to:)` whenever the database changes, and passes
/// it each event and request of `CKSyncEngine`'s delegate. While sync is off,
/// it hands iCloud's engine nothing and takes nothing from it: the app lets
/// its engine go, and starts one again once sync is on.
public struct Sync: Sendable {
    let engine: Engine

    /// The rules of sync for the device `engine` runs on.
    public init(engine: Engine) {
        self.engine = engine
    }

    /// The state iCloud's engine saved last on this device, which the app
    /// starts it from at launch, or nil before it saved one.
    public func savedState() throws(EngineError) -> Data? {
        try engine.savedSyncEngineState()
    }

    /// Whether sync is on, as Settings' switch says, which the app's engine
    /// follows: it runs only while it is.
    public func isOn() throws(EngineError) -> Bool {
        try engine.syncIsOn()
    }

    /// Keeps whether the device is signed into iCloud, which the app asks
    /// iCloud at launch and whenever the account changes, whether sync is on
    /// or not, for the Sync tab.
    public func noteAccount(signedIn: Bool) throws(EngineError) {
        try engine.noteICloudAccount(signedIn: signedIn)
    }

    /// Starts syncing through `iCloud`, while sync is on: on a device whose
    /// engine never saved a state, it asks iCloud for the cards' zone and the
    /// files', and it hands `iCloud` every change that waits, those made
    /// while the app didn't run, by the CLI or offline, included.
    public func start(with iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard try engine.syncIsOn() else { return }
        if try engine.savedSyncEngineState() == nil {
            iCloud.add(pendingDatabaseChanges: [.saveZone(.cards), .saveZone(.files)])
        }
        try sendWhatChanged(to: iCloud)
    }

    /// Hands `iCloud` every change that waits to be sent, as the database
    /// changes, whichever process changed it, and then the images and sounds
    /// its cards use that iCloud lacks, while sync is on. One it already
    /// holds stays as one. While iCloud is full, it asks for the zones again
    /// first, in case one didn't fit, since this is how what waits goes once
    /// there's room.
    public func sendWhatChanged(to iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard try engine.syncIsOn() else { return }
        if try engine.iCloudIsFull() {
            iCloud.add(pendingDatabaseChanges: [.saveZone(.cards), .saveZone(.files)])
        }
        iCloud.add(pendingRecordZoneChanges: try engine.changesToSend().map(\.pendingRecordZoneChange))
        try sendFiles(to: iCloud)
    }

    /// The record `iCloud` saves for `id`, as its row is now, with what
    /// iCloud said of it last, or nil when the device no longer holds it,
    /// whose save then stops waiting in `iCloud`, as Apple's sample does: the
    /// record provider of
    /// `CKSyncEngine.RecordZoneChangeBatch(pendingChanges:recordProvider:)`.
    /// A file's record is as `fileRecordToSave(_:)` says. While sync is off,
    /// it's nil for every record.
    public func recordToSave(_ id: ICloudRecordID, from iCloud: some ICloudSyncEngine) throws(EngineError)
        -> ICloudRecord?
    {
        let record: ICloudRecord?
        if try !engine.syncIsOn() {
            record = nil
        } else if id.zone == .files {
            record = try fileRecordToSave(id)
        } else {
            record = try engine.read { db in
                try syncedRow(named: id, in: db).flatMap { try FichaData.record(of: $0, in: db) }
            }
        }
        if record == nil {
            iCloud.remove(pendingRecordZoneChanges: [.saveRecord(id)])
        }
        return record
    }

    /// Handles an event of iCloud's engine, as `CKSyncEngine`'s delegate's
    /// `handleEvent(_:syncEngine:)` does, while sync is on. While it's off,
    /// an event, such as one an engine the app let go of still tells, is
    /// left aside: the next engine starts from the state saved before, and
    /// fetches again what it brought.
    public func handle(_ event: ICloudEvent, from iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard try engine.syncIsOn() else {
            return syncLogger.debug("Sync is off: an event of iCloud's engine is left aside")
        }
        // A record or a deletion refused because the user deleted Ficha's
        // data in iCloud's settings is a purge, which the device may hear of
        // before it fetches the zone's deletion.
        guard !event.saysTheUserDeletedFichasData else {
            return try takePurge()
        }
        if event.saysTheDeviceSynced {
            try engine.noteSynced()
        }
        // Whether iCloud is full is noted first, so that a record that didn't
        // fit waits rather than going again at once.
        if let isFull = event.saysICloudIsFull {
            try engine.noteICloudIsFull(isFull)
        }
        // Images and sounds first, in `SyncedFiles.swift`; the rest is the
        // cards' zone's.
        let event = try handleFiles(in: event, from: iCloud)
        switch event {
        case .stateUpdate(let state):
            try engine.saveSyncEngineState(state)
        case .fetchedRecordZoneChanges(let changes):
            try receiveFetched(changes.modifications)
            try takeDeletions(changes.deletions)
        case .sentRecordZoneChanges(let sent):
            try settle(sent, with: iCloud)
        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                syncLogger.error(
                    "iCloud didn't save the zone \(failure.zone.name, privacy: .public): \(String(describing: failure.error))"
                )
            }
        case .fetchedDatabaseChanges(let changes):
            try takeZoneDeletions(changes.deletions, with: iCloud)
        case .accountChange(let change):
            try takeAccountChange(change, with: iCloud)
        case .didFetchChanges:
            try finishFetchingFiles(with: iCloud)
            // While iCloud is full, each fetch tries again what waits, in
            // case the user made room meanwhile.
            if try engine.iCloudIsFull() {
                try sendWhatChanged(to: iCloud)
            }
        }
    }

    /// Takes a change of the iCloud account, which never deletes a card.
    /// iCloud's engine forgets, as it tells of it, every change it was handed
    /// and how far it fetched, so the device starts over with the account it
    /// meets, as in a first sync: it forgets what iCloud said of each record
    /// and the records that waited for a row, and leaves every row waiting to
    /// be sent, with the deletions that waited (`recordEverythingToSend`). A
    /// record the account holds then merges with the device's row, and one it
    /// lacks is saved. Signed out, sync stops until the device is signed in,
    /// when iCloud's engine tells of it again.
    private func takeAccountChange(_ change: ICloudEvent.AccountChange, with iCloud: some ICloudSyncEngine)
        throws(EngineError)
    {
        syncLogger.notice("The iCloud account changed: \(String(describing: change), privacy: .public)")
        try engine.noteICloudAccount(signedIn: change != .signOut)
        try engine.noteICloudIsFull(false)
        let forgotten = try engine.write { db in
            let files = try forgetWhatICloudSaid(in: db)
            try recordEverythingToSend(in: db)
            return files
        }
        engine.removeFilesNoCardUses(images: forgotten.images, sounds: forgotten.sounds)
        guard change != .signOut else { return }
        iCloud.add(pendingDatabaseChanges: [.saveZone(.cards), .saveZone(.files)])
        try sendWhatChanged(to: iCloud)
    }

    /// Takes the zones that left iCloud. A purge, of either zone, turns sync
    /// off, as `takePurge()` says. The files' zone deleted or reset, which no
    /// version of Ficha deletes, goes up again whole: the device forgets the
    /// files iCloud held, and sends each one a card uses. The cards' zone
    /// reset with the user's encrypted data goes up again whole too, as
    /// `CKSyncEngine`'s documentation asks. The cards' zone deleted by
    /// another device is only logged: it's a restore's (#317).
    private func takeZoneDeletions(_ deletions: [ICloudEvent.ZoneDeletion], with iCloud: some ICloudSyncEngine)
        throws(EngineError)
    {
        for deletion in deletions {
            syncLogger.notice(
                "The zone \(deletion.zone.name, privacy: .public) left iCloud: \(String(describing: deletion.reason), privacy: .public)"
            )
        }
        guard !deletions.contains(where: { $0.reason == .purged }) else {
            return try takePurge()
        }
        let toSendAgain = Set(deletions.filter { $0.zone == .files || $0.reason == .encryptedDataReset }.map(\.zone))
        guard !toSendAgain.isEmpty else { return }
        let forgotten = try engine.write { db in
            if toSendAgain.contains(.cards) {
                try db.execute(sql: "DELETE FROM syncRecord WHERE zone = ?", arguments: [ICloudZone.cards.name])
                try db.execute(sql: "DELETE FROM syncIncoming")
                try recordEverythingToSend(in: db)
            }
            guard toSendAgain.contains(.files) else {
                return (images: Set<ImageName>(), sounds: Set<SoundName>())
            }
            return try forgetFilesInICloud(in: db)
        }
        engine.removeFilesNoCardUses(images: forgotten.images, sounds: forgotten.sounds)
        iCloud.add(pendingDatabaseChanges: toSendAgain.sorted { $0.name < $1.name }.map { .saveZone($0) })
        try sendWhatChanged(to: iCloud)
    }

    /// Takes a purge: the user deleted Ficha's data in iCloud's settings.
    /// The cards stay, against what `CKSyncEngine`'s documentation suggests
    /// (ADR 0017), and sync turns off, so that nothing goes back up until the
    /// user turns it on, which sends everything, as a first sync does: the
    /// device forgets what waited, what iCloud said of each record and held
    /// of the files, and the state of iCloud's engine. The images and sounds
    /// no card uses, kept only because iCloud held them, go.
    private func takePurge() throws(EngineError) {
        syncLogger.notice("Ficha's data was deleted in iCloud's settings: sync turns off, and the cards stay")
        let forgotten = try engine.write { db in
            try switchSyncOff(because: .purge, in: db)
            try db.execute(sql: "DELETE FROM syncPending")
            try db.execute(sql: "UPDATE syncDevice SET iCloudIsFull = 0")
            try saveSyncEngineState(nil, in: db)
            return try forgetWhatICloudSaid(in: db)
        }
        engine.removeFilesNoCardUses(images: forgotten.images, sounds: forgotten.sounds)
    }

    /// Applies `records`, which other devices saved, or this one, as iCloud
    /// holds them now, in one write that records nothing to send back: tags
    /// and captures first, then cards and the review log, so that what a
    /// record refers to is there first; and then those that waited for one
    /// of them.
    private func receiveFetched(_ records: [ICloudRecord]) throws(EngineError) {
        guard !records.isEmpty else {
            return
        }
        try engine.writeWithoutRecording { db in
            for record in records.sorted(by: { $0.applyingRank < $1.applyingRank }) {
                _ = try receive(record, in: db)
            }
            try applyWaitingRecords(in: db)
        }
    }

    /// Settles what became of the records iCloud's engine sent. A record
    /// iCloud saved keeps what iCloud says of it, and its change stops
    /// waiting, unless its row changed since. A record that changed in
    /// iCloud since this device heard of it takes iCloud's latest changes,
    /// field by field, and goes again with its own, if it still has some. The
    /// deletions sent stop waiting, as `settleSentDeletions` says, and a
    /// record iCloud no longer has because another device deleted it takes
    /// that deletion (`takeDeletionsBehind`). Any other record whose zone or
    /// whose version iCloud no longer has goes again from scratch, its zone
    /// first. One that didn't fit in a full iCloud keeps waiting here, for
    /// when there's room.
    private func settle(_ sent: ICloudEvent.SentRecordZoneChanges, with iCloud: some ICloudSyncEngine)
        throws(EngineError)
    {
        try engine.writeWithoutTelling { db in
            for record in sent.savedRecords {
                try keep(record.systemFields, of: record.id, in: db)
                try forgetPendingSave(of: try SyncedRow(of: record), whenICloudHolds: record, in: db)
            }
        }
        try settleSentDeletions(sent)
        let toRetry = try takeDeletionsBehind(sent.failedRecordSaves)
        guard !toRetry.isEmpty else {
            return
        }
        let retries = try engine.writeWithoutRecording { db in
            try toRetry.map { failure in try retry(failure, in: db) }
        }
        iCloud.add(pendingDatabaseChanges: retries.compactMap(\.zone))
        iCloud.add(pendingRecordZoneChanges: retries.compactMap(\.record))
    }

    /// What to send again of a record iCloud didn't save, as `failure` says
    /// why: the record again, its zone first, or nothing.
    func retry(_ failure: ICloudEvent.FailedRecordSave, in db: Database) throws -> (
        zone: ICloudPendingDatabaseChange?, record: ICloudPendingRecordZoneChange?
    ) {
        let id = failure.record.id
        switch failure.error {
        case .serverRecordChanged(let iCloudsRecord):
            guard try receive(iCloudsRecord, in: db) == .applied,
                try hasPendingSave(SyncedRow(of: iCloudsRecord), in: db)
            else {
                return (nil, nil)
            }
            return (nil, .saveRecord(id))
        case .zoneNotFound:
            try keep(nil, of: id, in: db)
            // In a full iCloud, the zone may be what didn't fit: the record
            // waits, and goes with its zone once there's room
            // (`sendWhatChanged(to:)`), rather than again and again now.
            guard try !iCloudIsFull(in: db) else {
                return (nil, nil)
            }
            return (.saveZone(id.zone), .saveRecord(id))
        case .unknownItem:
            // A record of a row that's deleted for good never comes here:
            // its row went with it, as `takeDeletionsBehind` says. Any other,
            // such as a tag's, goes again from scratch.
            try keep(nil, of: id, in: db)
            return (nil, .saveRecord(id))
        case .quotaExceeded:
            syncLogger.notice("iCloud is full: a change waits until there's room")
            return (nil, nil)
        case .userDeletedZone:
            // A purge, which `handle(_:from:)` takes before it gets here.
            return (nil, nil)
        case .retriedByTheEngine:
            return (nil, nil)
        case .other(let code):
            syncLogger.error(
                "iCloud didn't save a record of type \(failure.record.type, privacy: .public): \(code, privacy: .public)"
            )
            return (nil, nil)
        }
    }
}

/// Forgets what iCloud said of every record, and the records that waited
/// for a row, as the account changes or the user purges Ficha's data: what
/// one account said means nothing to another, and a record sent with it to an
/// account that lacks it would be refused as one another device deleted,
/// whose row goes (`takeDeletionsBehind`). Sent without it, a record the
/// account holds merges with it, and one it lacks is saved: an account change
/// never deletes a card. The images and sounds iCloud held are forgotten too,
/// so the device sends each one its cards use, which the account turns down
/// when it holds it. Returns them, for the device to remove those no card
/// uses.
private func forgetWhatICloudSaid(in db: Database) throws -> (images: Set<ImageName>, sounds: Set<SoundName>) {
    let files = try forgetFilesInICloud(in: db)
    try db.execute(sql: "DELETE FROM syncRecord")
    try db.execute(sql: "DELETE FROM syncIncoming")
    return files
}

/// Forgets which images and sounds iCloud holds, and returns them.
private func forgetFilesInICloud(in db: Database) throws -> (images: Set<ImageName>, sounds: Set<SoundName>) {
    let files = (images: try namesInICloud(ImageName.self, in: db), sounds: try namesInICloud(SoundName.self, in: db))
    try db.execute(sql: "DELETE FROM syncRecord WHERE zone = ?", arguments: [ICloudZone.files.name])
    return files
}

extension ICloudEvent {
    /// Whether it says iCloud is full, or that there's room again, or nil
    /// when it says neither: a record or a zone that didn't fit says it's
    /// full; records iCloud saved, with none that didn't fit, say there's
    /// room. A deletion says neither, since iCloud takes one when it's full.
    fileprivate var saysICloudIsFull: Bool? {
        switch self {
        case .sentRecordZoneChanges(let sent):
            if sent.failedRecordSaves.contains(where: { $0.error == .quotaExceeded }) {
                return true
            }
            return sent.savedRecords.isEmpty ? nil : false
        case .sentDatabaseChanges(let sent):
            return sent.failedZoneSaves.contains { $0.error == .quotaExceeded } ? true : nil
        case .stateUpdate, .accountChange, .fetchedDatabaseChanges, .fetchedRecordZoneChanges, .didFetchChanges:
            return nil
        }
    }

    /// Whether the device synced as it happened: a fetch of what the other
    /// devices changed ended, or iCloud took records or deletions it sent.
    fileprivate var saysTheDeviceSynced: Bool {
        switch self {
        case .didFetchChanges:
            true
        case .sentRecordZoneChanges(let sent):
            !sent.savedRecords.isEmpty || !sent.deletedRecordIDs.isEmpty
        case .stateUpdate, .accountChange, .fetchedDatabaseChanges, .fetchedRecordZoneChanges, .sentDatabaseChanges:
            false
        }
    }

    /// Whether iCloud refused a record, or a deletion, because the user
    /// deleted Ficha's data in iCloud's settings.
    fileprivate var saysTheUserDeletedFichasData: Bool {
        guard case .sentRecordZoneChanges(let sent) = self else { return false }
        return sent.failedRecordSaves.contains { $0.error == .userDeletedZone }
            || sent.failedRecordDeletes.values.contains(.userDeletedZone)
    }
}

extension ChangeToSend {
    /// The change iCloud's engine sends for it: a row saved is sent as it is
    /// when the engine sends it, and a row deleted is deleted from iCloud.
    fileprivate var pendingRecordZoneChange: ICloudPendingRecordZoneChange {
        switch kind {
        case .saved: .saveRecord(row.recordID)
        case .deleted: .deleteRecord(row.recordID)
        }
    }
}

extension ICloudRecord {
    /// Its place among the records of a fetch as they're applied: tags, the
    /// settings that decide progress and captures first, then cards, then
    /// the review log, so that what a record refers to comes before it. A
    /// type this version doesn't know comes last, to wait.
    fileprivate var applyingRank: Int {
        switch SyncedRow.RecordType(rawValue: type) {
        case .tag, .progressSettings: 0
        case .capture: 1
        case .card: 2
        case .reviewLogEntry: 3
        case nil: 4
        }
    }
}
