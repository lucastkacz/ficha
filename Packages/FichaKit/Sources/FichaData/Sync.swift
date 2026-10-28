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
/// the cards kept, and so does a restore (`SyncedRestore.swift`). Turning it
/// on after either sends the device's cards into another cards' zone, newer
/// than the one before, as `ICloudZones.swift` names it, which every device
/// moves to as it hears of it: one that synced since before a restore's zone
/// started takes its cards in place of its own, its changes not yet sent
/// dropped, and any other joins it, as at an account change, so a purge
/// never deletes a card. The device that moves deletes the zone it leaves,
/// and any older one it hears of. What the Sync tab and the menu read of it
/// all is `SyncStatus`.
///
/// The app makes one when sync starts, tells it whether the device is signed
/// into iCloud (`noteAccount(signedIn:)`), calls `start(with:)` while sync is
/// on, then `sendWhatChanged(to:)` whenever the database changes, and passes
/// it each event and request of `CKSyncEngine`'s delegate. While sync is off,
/// it hands iCloud's engine nothing and takes nothing from it: the app lets
/// its engine go, and starts one again once sync is on. An off, however
/// brief, ends the engine that saw it (`SyncStretch`).
public struct Sync: Sendable {
    let engine: Engine
    /// The zones the device syncs in, by their names in iCloud.
    let zones: ICloudZones

    /// The rules of sync for the device `engine` runs on, in `zones`.
    public init(engine: Engine, zones: ICloudZones) {
        self.engine = engine
        self.zones = zones
    }

    /// `iCloud` in the zones the device syncs in now, which every rule
    /// speaks to it through (`ICloudInItsZones`): once again after the device
    /// moved to another cards' zone.
    private func inItsZones(_ iCloud: some ICloudSyncEngine) throws(EngineError) -> ICloudInItsZones {
        let base = (iCloud as? ICloudInItsZones)?.base ?? iCloud
        return ICloudInItsZones(base: base, cards: zones.cards(try engine.read(cardsZone(in:))), files: zones.files)
    }

    /// The state iCloud's engine saved last on this device, which the app
    /// starts it from at launch, or nil before it saved one.
    public func savedState() throws(EngineError) -> Data? {
        try engine.savedSyncEngineState()
    }

    /// The stretch of time sync is on now, as Settings' switch says, or nil
    /// while it's off, which the app's engine follows: it runs only while
    /// sync is on, in the stretch it started in.
    public func stretchNow() throws(EngineError) -> SyncStretch? {
        try engine.syncStretch()
    }

    /// Keeps whether the device is signed into iCloud, which the app asks
    /// iCloud at launch and whenever the account changes, whether sync is on
    /// or not, for the Sync tab.
    public func noteAccount(signedIn: Bool) throws(EngineError) {
        try engine.noteICloudAccount(signedIn: signedIn)
    }

    /// Keeps that the device synced now, as a fetch the app asked iCloud's
    /// engine for ended without an error, while sync is on: iCloud answered,
    /// even with nothing new.
    public func noteFetchEnded() throws(EngineError) {
        guard try engine.syncIsOn() else { return }
        try engine.noteSynced()
    }

    /// Starts syncing through `iCloud`, while sync is on: on a device whose
    /// engine never saved a state, it asks iCloud for the cards' zone and the
    /// files', noting it syncs in that cards' zone from now, unless it knows
    /// since when already, and it hands `iCloud` every change that waits,
    /// those made while the app didn't run, by the CLI or offline, included.
    public func start(with iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard try engine.syncIsOn() else { return }
        let iCloud = try inItsZones(iCloud)
        if try engine.savedSyncEngineState() == nil {
            let now = engine.time.now
            try engine.writeWithoutTelling { db in try noteSyncingInTheCardsZone(since: now, in: db) }
            iCloud.askForBothZones()
        }
        try sendWhatChanged(to: iCloud)
    }

    /// Hands `iCloud` every change that waits to be sent, as the database
    /// changes, whichever process changed it, and then the images and sounds
    /// its cards use that iCloud lacks, while sync is on. One it already
    /// holds stays as one. While iCloud is full, it asks for the zones again
    /// first, in case one didn't fit: what didn't fit goes again at each
    /// change to the database, and as `tryAgainInAFullICloud(with:)` says.
    public func sendWhatChanged(to iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard try engine.syncIsOn() else { return }
        let iCloud = try inItsZones(iCloud)
        if try engine.iCloudIsFull() {
            iCloud.askForBothZones()
        }
        iCloud.add(pendingRecordZoneChanges: try engine.changesToSend().map(\.pendingRecordZoneChange))
        try sendFiles(to: iCloud)
    }

    /// Hands `iCloud` again what waits, its zones first, while iCloud is
    /// full, in case there's room now; while it isn't, nothing. Nothing tells
    /// the device when room comes, and iCloud's engine doesn't try again on
    /// its own a change that didn't fit: `quotaExceeded` isn't among the
    /// errors `CKSyncEngine`'s documentation says it retries. So the app
    /// calls it now and then while iCloud is full, as each fetch's end does,
    /// beside each change to the database (`sendWhatChanged(to:)`) and each
    /// launch (`start(with:)`).
    public func tryAgainInAFullICloud(with iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard try engine.iCloudIsFull() else { return }
        try sendWhatChanged(to: iCloud)
    }

    /// The record `iCloud` saves for `id`, as its row is now, with what
    /// iCloud said of it last, or nil when the device no longer holds it,
    /// whose save then stops waiting in `iCloud`, as Apple's sample does: the
    /// record provider of
    /// `CKSyncEngine.RecordZoneChangeBatch(pendingChanges:recordProvider:)`.
    /// A file's record is as `fileRecordToSave(_:)` says. While sync is off,
    /// it's nil for every record, and so it is for a record of a zone the
    /// device no longer syncs in, whose save waited as the device moved.
    public func recordToSave(_ id: ICloudRecordID, from iCloud: some ICloudSyncEngine) throws(EngineError)
        -> ICloudRecord?
    {
        let iCloud = try inItsZones(iCloud)
        let record: ICloudRecord?
        if try !engine.syncIsOn() {
            record = nil
        } else if let inside = iCloud.insideTheDevice(id) {
            if inside.zone == .files {
                record = try fileRecordToSave(inside)
            } else {
                record = try engine.read { db in
                    try syncedRow(named: inside, in: db).flatMap { try FichaData.record(of: $0, in: db) }
                }
            }
        } else {
            record = nil
        }
        guard let record else {
            iCloud.base.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            return nil
        }
        return record.with(id: id)
    }

    /// Handles an event of iCloud's engine, which started in `stretch`, as
    /// `CKSyncEngine`'s delegate's `handleEvent(_:syncEngine:)` does, while
    /// sync is on in that stretch. Once sync is off, an event, such as one an
    /// engine the app let go of still tells, is left aside, and so is every
    /// event of that engine after, even once sync is on again: the next
    /// engine starts from the state saved before the off, and fetches again
    /// what it brought.
    public func handle(_ event: ICloudEvent, from iCloud: some ICloudSyncEngine, startedIn stretch: SyncStretch)
        throws(EngineError)
    {
        guard try engine.syncStretch() == stretch else {
            return syncLogger.debug("Sync went off since iCloud's engine started: its event is left aside")
        }
        // The rest speaks of the zones inside the device.
        let iCloud = try inItsZones(iCloud)
        let inside = event.insideTheDevice(iCloud)
        // A record or a deletion refused because the user deleted Ficha's
        // data in iCloud's settings is a purge, which the device may hear of
        // before it fetches the zone's deletion.
        guard !inside.saysTheUserDeletedFichasData else {
            return try takePurge()
        }
        if inside.saysTheDeviceSynced {
            try engine.noteSynced()
        }
        // Whether iCloud is full is noted first, so that a record that didn't
        // fit waits rather than going again at once.
        if let isFull = inside.saysICloudIsFull {
            try engine.noteICloudIsFull(isFull)
        }
        // Images and sounds first, in `SyncedFiles.swift`; the rest is the
        // cards' zone's.
        switch try handleFiles(in: inside, from: iCloud) {
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
            try takeZoneChanges(changes, with: iCloud)
        case .accountChange(let change):
            try takeAccountChange(change, with: iCloud)
        case .didFetchChanges:
            try finishFetchingFiles(with: iCloud)
            try tryAgainInAFullICloud(with: iCloud)
        }
    }

    /// Takes a change of the iCloud account, which never deletes a card.
    /// iCloud's engine forgets, as it tells of it, every change it was handed
    /// and how far it fetched, so the device starts over with the account it
    /// meets, as in a first sync: it forgets what iCloud said of each record
    /// and the records that waited for a row, and leaves every row waiting to
    /// be sent, with the deletions that waited (`recordEverythingToSend`). A
    /// record the account holds then merges with the device's row, and one it
    /// lacks is saved. The device goes back to the first cards' zone, from
    /// now, since the zone it synced in is another account's: if the account
    /// it meets holds a newer one, the device joins it, as it hears of it
    /// (`takeZoneChanges(_:with:)`). Signed out, sync stops until the device
    /// is signed in, when iCloud's engine tells of it again.
    private func takeAccountChange(_ change: ICloudEvent.AccountChange, with iCloud: ICloudInItsZones)
        throws(EngineError)
    {
        syncLogger.notice("The iCloud account changed: \(String(describing: change), privacy: .public)")
        try engine.noteICloudAccount(signedIn: change != .signOut)
        try engine.noteICloudIsFull(false)
        let now = engine.time.now
        let forgotten = try engine.write { db in
            let files = try forgetWhatICloudSaid(in: db)
            try moveCards(to: .first, at: now, in: db)
            try recordEverythingToSend(in: db)
            return files
        }
        engine.removeFilesNoCardUses(forgotten)
        guard change != .signOut else { return }
        let iCloud = try inItsZones(iCloud)
        iCloud.askForBothZones()
        try sendWhatChanged(to: iCloud)
    }

    /// Takes the zones that changed in iCloud or left it, of those the
    /// device's zones name. When a cards' zone newer than the device's own
    /// changed, the device moves to the newest, as `move(to:afterAPurge:with:)`
    /// says, even when the same fetch says the user purged Ficha's data: a
    /// device turned sync on since, starting it. Otherwise a purge, of the
    /// device's cards' zone or of the files', turns sync off, as `takePurge()`
    /// says; a purge of an older zone is one the device heard of before it
    /// moved, or that came before its first fetch. Then, as
    /// `takeZoneDeletions(_:with:)` says for the device's own zones, and the
    /// device deletes from iCloud each cards' zone older than its own it
    /// heard changed, left behind by the devices that moved.
    private func takeZoneChanges(_ changes: ICloudEvent.FetchedDatabaseChanges, with iCloud: ICloudInItsZones)
        throws(EngineError)
    {
        let deletions = changes.deletions.filter { zones.contains($0.zone) }
        for deletion in deletions {
            syncLogger.notice(
                "The zone \(deletion.zone.name, privacy: .public) left iCloud: \(String(describing: deletion.reason), privacy: .public)"
            )
        }
        let isPurged = deletions.contains { $0.reason == .purged && iCloud.insideTheDevice($0.zone) != nil }
        let changedCardsZones = changes.modifications.compactMap(zones.cardsZone)
        var current = try engine.read(cardsZone(in:))
        var iCloud = iCloud
        if let newest = changedCardsZones.max(), newest > current {
            try move(to: newest, afterAPurge: isPurged, with: iCloud)
            current = newest
            iCloud = try inItsZones(iCloud)
        } else if isPurged {
            return try takePurge()
        } else {
            try takeZoneDeletions(
                deletions.compactMap { deletion in
                    iCloud.insideTheDevice(deletion.zone).map {
                        ICloudEvent.ZoneDeletion(zone: $0, reason: deletion.reason)
                    }
                }, with: iCloud)
        }
        let leftBehind = Set(changedCardsZones.filter { $0 < current }).sorted()
        iCloud.base.add(pendingDatabaseChanges: leftBehind.map { .deleteZone(zones.cards($0)) })
    }

    /// Moves the device to the cards' zone `newest`, newer than its own,
    /// which another device started as it turned sync on after a restore or
    /// a purge, and deletes from iCloud the zone it leaves. A device that
    /// synced since before a restore's zone started takes the copy: it drops
    /// every row that syncs, with its changes not yet sent, and the images
    /// and sounds only those rows used, and takes the zone's records as they
    /// come. Any other joins the zone, as at an account change: one that
    /// started syncing since, or one whose zone is a purge's, which never
    /// deletes a card. `afterAPurge` says the device also heard of the purge
    /// before it: it forgets what iCloud said of each record, the files'
    /// included, as `takePurge()` does, and stays on.
    private func move(to newest: CardsZone, afterAPurge: Bool, with iCloud: ICloudInItsZones) throws(EngineError) {
        let now = engine.time.now
        let (forgotten, dropped, takesTheCopy) = try engine.writeWithoutRecording { db in
            let takesTheCopy: Bool
            if case .started(.restore, let time) = newest {
                takesTheCopy = try cardsZoneSince(in: db) ?? .distantPast < Date(wholeMilliseconds: time)
            } else {
                takesTheCopy = false
            }
            let forgotten = afterAPurge ? try forgetWhatICloudSaid(in: db) : FilesInICloud()
            try moveCards(to: newest, at: now, in: db)
            guard takesTheCopy else {
                try recordEverythingToSend(in: db)
                return (forgotten, FilesReferred(), false)
            }
            return (forgotten, try dropEverythingThatSyncs(in: db), true)
        }
        syncLogger.notice(
            "The cards move to the zone \(zones.cards(newest).name, privacy: .public): this device \(takesTheCopy ? "takes its cards in place of its own" : "joins it", privacy: .public)"
        )
        engine.removeFilesNoCardUses(forgotten)
        engine.removeFilesNoCardUses(images: dropped.images, sounds: dropped.sounds)
        iCloud.base.add(pendingDatabaseChanges: [.deleteZone(iCloud.cards)])
        let moved = try inItsZones(iCloud)
        moved.askForBothZones()
        try sendWhatChanged(to: moved)
    }

    /// Takes the device's own zones that left iCloud, but for a purge. The
    /// files' zone deleted or reset, which no version of Ficha deletes, goes
    /// up again whole: the device forgets the files iCloud held, and sends
    /// each one a card uses. The cards' zone reset with the user's encrypted
    /// data goes up again whole too, as `CKSyncEngine`'s documentation asks.
    /// The cards' zone deleted by another device is only logged: it's an
    /// older Ficha's, or one a device moving left as this one moves too.
    private func takeZoneDeletions(_ deletions: [ICloudEvent.ZoneDeletion], with iCloud: ICloudInItsZones)
        throws(EngineError)
    {
        let toSendAgain = Set(deletions.filter { $0.zone == .files || $0.reason == .encryptedDataReset }.map(\.zone))
        guard !toSendAgain.isEmpty else { return }
        let forgotten = try engine.write { db in
            if toSendAgain.contains(.cards) {
                try db.execute(sql: "DELETE FROM syncRecord WHERE zone = ?", arguments: [ICloudZone.cards.name])
                try db.execute(sql: "DELETE FROM syncIncoming")
                try recordEverythingToSend(in: db)
            }
            guard toSendAgain.contains(.files) else {
                return FilesInICloud()
            }
            return try forgetFilesInICloud(in: db)
        }
        engine.removeFilesNoCardUses(forgotten)
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
            try noteICloudIsFull(false, in: db)
            try saveSyncEngineState(nil, in: db)
            return try forgetWhatICloudSaid(in: db)
        }
        engine.removeFilesNoCardUses(forgotten)
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
        // Only a record iCloud holds as it changed since, which the device
        // takes, is news to the other engines: what sync keeps of the others
        // would only wake the app to send them again, and again for as long
        // as iCloud is full.
        let takesICloudsRecords = toRetry.contains {
            if case .serverRecordChanged = $0.error { true } else { false }
        }
        let retries = try engine.writeWithoutRecording(tellingTheOtherEngines: takesICloudsRecords) { db in
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
            // A purge, which `handle(_:from:startedIn:)` takes before it
            // gets here.
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
private func forgetWhatICloudSaid(in db: Database) throws -> FilesInICloud {
    let files = try forgetFilesInICloud(in: db)
    try db.execute(sql: "DELETE FROM syncRecord")
    try db.execute(sql: "DELETE FROM syncIncoming")
    return files
}

/// Forgets which images and sounds iCloud holds, and returns them.
private func forgetFilesInICloud(in db: Database) throws -> FilesInICloud {
    let files = try FilesInICloud(in: db)
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

    /// Whether it shows iCloud answered the device as it happened: it
    /// brought zones that changed or left, or records, or iCloud took records
    /// or deletions the device sent. The end of a fetch doesn't, since
    /// `CKSyncEngine`'s documentation doesn't say it comes only after a fetch
    /// that didn't fail: a fetch the app sees end without an error says so
    /// (`noteFetchEnded()`).
    fileprivate var saysTheDeviceSynced: Bool {
        switch self {
        case .fetchedDatabaseChanges(let changes):
            !changes.modifications.isEmpty || !changes.deletions.isEmpty
        case .fetchedRecordZoneChanges(let changes):
            !changes.modifications.isEmpty || !changes.deletions.isEmpty
        case .sentRecordZoneChanges(let sent):
            !sent.savedRecords.isEmpty || !sent.deletedRecordIDs.isEmpty
        case .stateUpdate, .accountChange, .sentDatabaseChanges, .didFetchChanges:
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

extension ICloudSyncEngine {
    /// Asks iCloud for the cards' zone and the files', which it saves unless
    /// it holds them already.
    fileprivate func askForBothZones() {
        add(pendingDatabaseChanges: [.saveZone(.cards), .saveZone(.files)])
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
