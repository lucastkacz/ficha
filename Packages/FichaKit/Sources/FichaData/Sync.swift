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
/// the cards kept, and so does a restore (`SyncedRestore.swift`).
///
/// The cards sync in the newest of the cards' zones iCloud holds, as
/// `ICloudZones.swift` names them, never the same name twice. On its first
/// sync, after an account change and after a purge, a device fetches before
/// it sends anything, and starts in the newest zone the fetch lists, or
/// makes one when it lists none. Turning sync on after a restore makes one
/// too, into which the device sends its cards, deleting the zone it leaves.
/// Every device moves to a newer zone as it hears of it: one made by a
/// restore, the device takes as the copy, in place of its cards, its changes
/// not yet sent dropped, when it last synced in an older zone, after a copy
/// of its cards first; any other it joins, as at an account change, and so
/// does a device that never synced in this account. The device that moves
/// deletes the zone it leaves, and any older one it hears of. What the Sync
/// tab and the menu read of it all is `SyncStatus`.
///
/// The app makes one when sync starts, tells it whether the device is signed
/// into iCloud (`noteAccount(signedIn:)`), calls `start(with:)` while sync is
/// on, then `sendWhatChanged(to:)` whenever the database changes, and passes
/// it each event and request of `CKSyncEngine`'s delegate. While the device
/// chooses its cards' zone, and now and then while iCloud is full
/// (`iCloudIsFull()`), the app fetches first, and says when a fetch ended
/// without an error (`finishAFetchWithoutAnError(with:)`). While sync is off, it
/// hands iCloud's engine nothing and takes nothing from it: the app lets its
/// engine go, and starts one again once sync is on. An off, however brief,
/// ends the engine that saw it (`SyncStretch`).
public struct Sync: Sendable {
    let engine: Engine
    /// The zones the device syncs in, by their names in iCloud.
    let zones: ICloudZones

    /// The rules of sync for the device `engine` runs on, in `zones`.
    public init(engine: Engine, zones: ICloudZones) {
        self.engine = engine
        self.zones = zones
    }

    /// `base`, iCloud's engine, in the zones the device syncs in now, which
    /// every rule speaks to it through (`ICloudInItsZones`): read once for
    /// each call of the app's and each event, since the device may move to
    /// another cards' zone in between.
    private func inItsZones(_ base: some ICloudSyncEngine) throws(EngineError) -> ICloudInItsZones {
        let standing = try engine.read(CardsZoneStanding.init(in:))
        return ICloudInItsZones(base, in: zones, cardsZone: standing.chooses ? nil : standing.zone)
    }

    /// Whether the device waits for a fetch to choose its cards' zone before
    /// it sends anything: on its first sync, after an account change and
    /// after a purge. The app then fetches first, and says when the fetch
    /// ended without an error (`finishAFetchWithoutAnError(with:)`).
    public func choosesItsCardsZone() throws(EngineError) -> Bool {
        try engine.read(CardsZoneStanding.init(in:)).chooses
    }

    /// Whether the device knows iCloud is full. Nothing tells it when room
    /// comes, and iCloud's engine doesn't try again on its own a change that
    /// didn't fit: `quotaExceeded` isn't among the errors `CKSyncEngine`'s
    /// documentation says it retries. So the app fetches now and then while
    /// it's full, and the fetch's end hands iCloud's engine again what waits,
    /// its zones too (`finishAFetchWithoutAnError(with:)`).
    public func iCloudIsFull() throws(EngineError) -> Bool {
        try engine.iCloudIsFull()
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

    /// Finishes a fetch the app asked iCloud for that ended without an error,
    /// while sync is on, handing what it asks for to `iCloud`, the engine
    /// that runs: iCloud answered, so the device keeps that it synced now,
    /// even with nothing new, and notes what syncs, now that it heard every
    /// change to the choice and to the cards' tags (`noteWhatSyncs(in:)`),
    /// handing over the rows that start or stop syncing. A device that
    /// chooses its cards' zone still,
    /// which a fetch that listed one would have moved there, learns that
    /// iCloud holds none: it makes one, and sends every card into it, the
    /// zones first. In a full iCloud, the device hands `iCloud` again what
    /// waits, the zones first too, in case there's room now. Only the end of
    /// such a fetch asks for the zones, so that a device that missed a purge
    /// hears of it first, rather than save a zone again under the name iCloud
    /// purged, which would reach the other devices as changed (P16) and
    /// refuse each record it sends with what iCloud said of it as deleted.
    /// And only a fetch that ended without an error says all this, since
    /// `CKSyncEngine`'s documentation doesn't say that the end of a fetch it
    /// tells of comes only after one that didn't fail.
    public func finishAFetchWithoutAnError(with base: some ICloudSyncEngine) throws(EngineError) {
        guard try engine.syncIsOn() else { return }
        try engine.noteSynced()
        var iCloud = try inItsZones(base)
        if iCloud.cardsZone == nil {
            let now = engine.time.now
            let zone = try engine.writeWithoutTelling { db in
                let zone = try CardsZoneStanding.makeAZoneWhereICloudHoldsNone(at: now, in: db)
                try recordEverythingToSend(in: db)
                return zone
            }
            syncLogger.notice(
                "iCloud holds no cards' zone: the cards go into a new one, \(zones.cards(zone).name, privacy: .public)")
            iCloud = iCloud.movedTo(zone)
        } else if try !engine.iCloudIsFull() {
            return try handOverWhatWaits(to: iCloud, notingWhatSyncs: true)
        }
        iCloud.askForBothZones()
        try handOverWhatWaits(to: iCloud, notingWhatSyncs: true)
    }

    /// Starts syncing through `iCloud`, while sync is on, as
    /// `startSyncing(through:)` says.
    public func start(with iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard try engine.syncIsOn() else { return }
        try startSyncing(through: try inItsZones(iCloud))
    }

    /// Starts syncing through `iCloud`, unless the device chooses its cards'
    /// zone, when it hands it nothing until a fetch tells it which: on an
    /// engine that never saved a state, it asks iCloud for the cards' zone
    /// and the files'; it deletes the zone a restore's turn-on left, if
    /// any; and it hands `iCloud` every change that waits, those made while
    /// the app didn't run, by the CLI or offline, included, once it noted
    /// what syncs.
    private func startSyncing(through iCloud: ICloudInItsZones) throws(EngineError) {
        guard iCloud.cardsZone != nil else { return }
        if try engine.savedSyncEngineState() == nil {
            iCloud.askForBothZones()
        }
        if let left = try engine.writeWithoutTelling(CardsZoneStanding.takeTheZoneLeft(in:)) {
            iCloud.delete([left])
        }
        try handOverWhatWaits(to: iCloud, notingWhatSyncs: true)
    }

    /// Hands `iCloud` every change that waits to be sent, as the database
    /// changes, whichever process changed it, as `handOverWhatWaits(to:)`
    /// says.
    public func sendWhatChanged(to iCloud: some ICloudSyncEngine) throws(EngineError) {
        try handOverWhatWaits(to: try inItsZones(iCloud))
    }

    /// Hands `iCloud` every change that waits to be sent, and then the images
    /// and sounds its cards that sync use that iCloud lacks, while sync is on
    /// and the device doesn't choose its cards' zone. One it already holds
    /// stays as one. First it notes what syncs, as
    /// `Engine.noteWhatSyncs(everything:)` says, of every row when
    /// `everything` says so, as a fetch ends; and while a change to the
    /// choice waits, the rows that leave iCloud wait for it
    /// (`Engine.leavingWhileTheChoiceChanges()`). In a full iCloud, what
    /// didn't fit goes again with them, but never a zone that didn't: only
    /// the end of a fetch without an error asks for the zones again
    /// (`finishAFetchWithoutAnError(with:)`).
    private func handOverWhatWaits(to iCloud: ICloudInItsZones, notingWhatSyncs everything: Bool = false)
        throws(EngineError)
    {
        guard iCloud.cardsZone != nil, try engine.syncIsOn() else { return }
        try engine.noteWhatSyncs(everything: everything)
        let waiting = try engine.leavingWhileTheChoiceChanges()
        iCloud.add(
            pendingRecordZoneChanges: try engine.changesToSend().filter { !waiting.contains($0.sequence) }
                .map(\.pendingRecordZoneChange))
        try sendFiles(to: iCloud)
    }

    /// The record `iCloud` saves for `id`, as its row is now, with what
    /// iCloud said of it last, or nil when the device no longer holds it,
    /// whose save then stops waiting in `iCloud`, as Apple's sample does: the
    /// record provider of
    /// `CKSyncEngine.RecordZoneChangeBatch(pendingChanges:recordProvider:)`.
    /// A file's record is as `fileRecordToSave(_:)` says, and that of a row
    /// that doesn't sync, as one that left, only while iCloud holds it in
    /// full, as far as the device knows (`SelectiveSync.swift`). While sync
    /// is off, it's nil for every record, and so it is for a record of a
    /// zone the device no longer syncs in, whose save waited as the device
    /// moved.
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
                    guard let row = try syncedRow(named: inside, in: db),
                        let record = try FichaData.record(of: row, in: db),
                        try !record.hasLeft || iCloudHoldsInFull(inside, in: db)
                    else {
                        return nil
                    }
                    return record
                }
            }
        } else {
            record = nil
        }
        guard let record else {
            iCloud.stopSaving(id)
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
            try takeZoneChanges(changes, in: iCloud)
        case .accountChange(let change):
            try takeAccountChange(change, in: iCloud)
        case .didFetchChanges:
            // What syncs is noted again, now that the device heard what the
            // other devices changed of the choice and the cards' tags, before
            // the files it lets go of in sync, and the rows that start or
            // stop syncing go. The records that didn't fit go again, while
            // iCloud is full, but not the zones: this fetch may have ended
            // with an error, and the end of one that didn't asks for them
            // (`finishAFetchWithoutAnError(with:)`).
            try engine.noteWhatSyncs(everything: true)
            try finishFetchingFiles(with: iCloud)
            try handOverWhatWaits(to: iCloud)
        }
    }

    /// Takes a change of the iCloud account, which never deletes a card.
    /// iCloud's engine forgets, as it tells of it, every change it was handed
    /// and how far it fetched, so the device starts over with the account it
    /// meets, as in a first sync: it forgets what iCloud said of each record
    /// and the records that waited for a row, and leaves every row waiting to
    /// be sent, with the deletions that waited (`recordEverythingToSend`). A
    /// record the account holds then merges with the device's row, and one it
    /// lacks is saved. The device chooses its cards' zone again, at its next
    /// fetch, which starts from nothing (`takeZoneChanges(_:in:)`). Signed
    /// into another account than the one it last synced in, as a switch says,
    /// or a sign-in as another user than the one it last synced as, it
    /// forgets the zone it synced in, another account's, and joins as on a
    /// first sync; signed out and in again as the same user, it keeps it, so
    /// that it takes a restore's copy made meanwhile. A device that doesn't
    /// know who it last synced as, as one that synced before Ficha kept it,
    /// learns it from a sign-out or a sign-in, and keeps its zone. Signed
    /// out, sync stops until the device is signed in, when iCloud's engine
    /// tells of it again. An engine that never saved a state may tell of a
    /// sign-in as it first meets the account, which `CKSyncEngine`'s
    /// documentation leaves open: as the same user, the device then only
    /// gets again what it handed it as it started (`startSyncing(through:)`),
    /// since it forgot it.
    private func takeAccountChange(_ change: ICloudEvent.AccountChange, in iCloud: ICloudInItsZones)
        throws(EngineError)
    {
        // Never the users' IDs.
        syncLogger.notice("The iCloud account changed: \(change.kind, privacy: .public)")
        try engine.noteICloudAccount(signedIn: change.signsIn)
        let anotherUser = try engine.read(CardsZoneStanding.init(in:)).anotherUser(after: change)
        if case .signIn(let user) = change, anotherUser == nil, try engine.savedSyncEngineState() == nil {
            try engine.writeWithoutTelling { db in try CardsZoneStanding.learn(user, in: db) }
            return try startSyncing(through: iCloud)
        }
        try engine.noteICloudIsFull(false)
        let forgotten = try engine.write { db in
            let files = try forgetWhatICloudSaid(in: db)
            if let anotherUser {
                try CardsZoneStanding.chooseAgain(inTheAccountOf: anotherUser, in: db)
            } else {
                try CardsZoneStanding.chooseAgain(in: db)
                try CardsZoneStanding.learn(change.userSyncedAs, in: db)
            }
            try recordEverythingToSend(in: db)
            return files
        }
        engine.removeFilesNoCardUses(forgotten)
    }

    /// Takes the zones that came, changed or left iCloud, of those the
    /// device's zones name. A device that chooses its cards' zone fetches
    /// from nothing, which lists every zone iCloud holds: it moves to the
    /// newest, as `move(to:from:afterAPurge:in:)` says, and takes no zone
    /// that left, which it was told of before it chose. Any other device
    /// moves to the newest when it's newer than its own, even when the same
    /// fetch says the user purged Ficha's data: a device turned sync on
    /// since, making it. Otherwise a purge, of the device's cards' zone or of
    /// the files', turns sync off, as `takePurge()` says; a purge of an older
    /// zone is one the device heard of before it moved. Otherwise the
    /// device's own zones that left go as `takeZoneDeletions(_:in:)` says.
    /// Last, the device deletes from iCloud each cards' zone older than its
    /// own that it heard of, which the devices that moved left behind.
    private func takeZoneChanges(_ changes: ICloudEvent.FetchedDatabaseChanges, in iCloud: ICloudInItsZones)
        throws(EngineError)
    {
        let deletions = changes.deletions.filter { zones.contains($0.zone) }
        for deletion in deletions {
            syncLogger.notice(
                "The zone \(deletion.zone.name, privacy: .public) left iCloud: \(String(describing: deletion.reason), privacy: .public)"
            )
        }
        let standing = try engine.read(CardsZoneStanding.init(in:))
        let heard = changes.modifications.compactMap(zones.cardsZone)
        let isPurged = deletions.contains { $0.reason == .purged && iCloud.insideTheDevice($0.zone) != nil }
        let current: CardsZone
        if let newest = heard.max(), standing.chooses || standing.zone.map({ newest > $0 }) ?? true {
            try move(to: newest, from: standing, afterAPurge: isPurged, in: iCloud)
            current = newest
        } else if let zone = standing.zone, !standing.chooses {
            guard !isPurged else {
                return try takePurge()
            }
            try takeZoneDeletions(
                deletions.compactMap { deletion in
                    iCloud.insideTheDevice(deletion.zone).map {
                        ICloudEvent.ZoneDeletion(zone: $0, reason: deletion.reason)
                    }
                }, in: iCloud)
            current = zone
        } else {
            return
        }
        iCloud.delete(Set(heard.filter { $0 < current }).sorted())
    }

    /// Moves the device into the cards' zone `newest`, from where it stood,
    /// `standing`, and deletes from iCloud the zone it leaves. A device that
    /// last synced in a zone older than a restore's takes the copy: it saves
    /// a copy before taking iCloud's copy first, so that the cards the
    /// restore removed can still be found, which is our own guard, and none
    /// for an engine in memory; then it drops every row that syncs, with its
    /// changes not yet sent, and takes the zone's records as they come. Any
    /// other joins the zone, as at an account change: one that never synced
    /// in this account, or one whose zone a restore didn't make, which never
    /// deletes a card. One that chose the zone it last synced in goes on in
    /// it. A device that moves forgets which images and sounds iCloud holds,
    /// and keeps them, so that it never deletes one from iCloud because the
    /// cards it has of the zone are only some of them still: it sends again
    /// each one its cards that sync use, which iCloud turns down when it
    /// holds it (#316), and the files no card uses leave as another device
    /// deletes them. `afterAPurge` says the device also heard of the purge
    /// before it: it forgets what iCloud said of each record, as `takePurge()`
    /// does, removes the files no card uses, which iCloud no longer holds,
    /// and stays on.
    private func move(
        to newest: CardsZone, from standing: CardsZoneStanding, afterAPurge: Bool, in iCloud: ICloudInItsZones
    ) throws(EngineError) {
        let moved = iCloud.movedTo(newest)
        guard newest != standing.zone else {
            try engine.writeWithoutTelling { db in try CardsZoneStanding.move(to: newest, in: db) }
            syncLogger.notice("The cards go on in the zone \(zones.cards(newest).name, privacy: .public)")
            return try handOverWhatWaits(to: moved)
        }
        let takesTheCopy = newest.isMadeByARestore && standing.zone.map { $0 < newest } == true
        if takesTheCopy {
            try engine.saveCopy(.beforeICloudsCopy)
        }
        let toRemove = try engine.writeWithoutRecording { db in
            // After a purge, iCloud holds none of the files the device knew
            // it held: they're among those to remove, and none is kept for
            // iCloud. Otherwise the device keeps them, for the zone's cards.
            var toRemove = FileNames()
            var keptForICloud = FileNames()
            if afterAPurge {
                toRemove = try forgetWhatICloudSaid(in: db)
            } else {
                keptForICloud = try forgetFilesInICloud(in: db)
            }
            try CardsZoneStanding.move(to: newest, in: db)
            guard takesTheCopy else {
                try recordEverythingToSend(in: db)
                return toRemove
            }
            toRemove.formUnion(try dropEverythingThatSyncs(in: db).subtracting(keptForICloud))
            return toRemove
        }
        syncLogger.notice(
            "The cards move to the zone \(zones.cards(newest).name, privacy: .public): this device \(takesTheCopy ? "takes its cards in place of its own" : "joins it", privacy: .public)"
        )
        engine.removeFilesNoCardUses(toRemove)
        iCloud.delete(standing.zone.map { [$0] } ?? [])
        moved.add(pendingDatabaseChanges: [.saveZone(.files)])
        try handOverWhatWaits(to: moved)
    }

    /// Takes the device's own zones that left iCloud, but for a purge. The
    /// files' zone deleted or reset, which no version of Ficha deletes, goes
    /// up again whole: the device forgets the files iCloud held, and sends
    /// each one a card uses. The cards' zone reset with the user's encrypted
    /// data goes up again whole too, as `CKSyncEngine`'s documentation asks.
    /// The cards' zone deleted by another device is only logged: it's an
    /// older Ficha's, or one a device moving left as this one moves too.
    private func takeZoneDeletions(_ deletions: [ICloudEvent.ZoneDeletion], in iCloud: ICloudInItsZones)
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
                return FileNames()
            }
            return try forgetFilesInICloud(in: db)
        }
        engine.removeFilesNoCardUses(forgotten)
        iCloud.add(pendingDatabaseChanges: toSendAgain.sorted { $0.name < $1.name }.map { .saveZone($0) })
        try handOverWhatWaits(to: iCloud)
    }

    /// Takes a purge: the user deleted Ficha's data in iCloud's settings.
    /// The cards stay, against what `CKSyncEngine`'s documentation suggests
    /// (ADR 0017), and sync turns off, so that nothing goes back up until the
    /// user turns it on, which sends everything, as a first sync does: the
    /// device forgets what waited, what iCloud said of each record and held
    /// of the files, and the state of iCloud's engine, and chooses its cards'
    /// zone again, knowing the one it last synced in. The images and sounds
    /// no card uses, kept only because iCloud held them, go.
    private func takePurge() throws(EngineError) {
        syncLogger.notice("Ficha's data was deleted in iCloud's settings: sync turns off, and the cards stay")
        let forgotten = try engine.write { db in
            try switchSyncOff(because: .purge, in: db)
            try db.execute(sql: "DELETE FROM syncPending")
            try noteICloudIsFull(false, in: db)
            try saveSyncEngineState(nil, in: db)
            try CardsZoneStanding.chooseAgain(in: db)
            return try forgetWhatICloudSaid(in: db)
        }
        engine.removeFilesNoCardUses(forgotten)
    }

    /// Applies `records`, which other devices saved, or this one, as iCloud
    /// holds them now, in one write that records nothing to send back: tags
    /// first, then the changes to tags, then captures, cards and the review
    /// log, so that what a record refers to is there first, as
    /// `applyingRank()` says; and then those that waited for one of them.
    private func receiveFetched(_ records: [ICloudRecord]) throws(EngineError) {
        guard !records.isEmpty else {
            return
        }
        try engine.writeWithoutRecording { db in
            let ranked = try records.map { record in (rank: try record.applyingRank(), record: record) }
            for (_, record) in ranked.sorted(by: { $0.rank < $1.rank }) {
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
                try keep(record.systemFields, of: record.id, hasLeft: record.hasLeft, in: db)
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
            // waits, and goes again after its zone, at the end of a fetch
            // without an error (`finishAFetchWithoutAnError(with:)`), rather
            // than again and again now.
            guard try !FichaData.iCloudIsFull(in: db) else {
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
private func forgetWhatICloudSaid(in db: Database) throws -> FileNames {
    let files = try forgetFilesInICloud(in: db)
    try db.execute(sql: "DELETE FROM syncRecord")
    try db.execute(sql: "DELETE FROM syncIncoming")
    return files
}

/// Forgets which images and sounds iCloud holds, and returns them.
private func forgetFilesInICloud(in db: Database) throws -> FileNames {
    let files = try FileNames(heldByICloudIn: db)
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
    /// (`finishAFetchWithoutAnError(with:)`).
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

extension ICloudEvent.AccountChange {
    /// Which change it is, for the log, without the users' IDs.
    fileprivate var kind: String {
        switch self {
        case .signIn: "signIn"
        case .signOut: "signOut"
        case .switchAccounts: "switchAccounts"
        }
    }

    /// Whether the device is signed into iCloud after it.
    fileprivate var signsIn: Bool {
        if case .signOut = self { false } else { true }
    }

    /// The user the device last synced as, as it says: the one signed in
    /// after it, or, after a sign-out, the one signed in before.
    fileprivate var userSyncedAs: ICloudUser {
        switch self {
        case .signIn(let current), .switchAccounts(_, let current): current
        case .signOut(let previous): previous
        }
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
    /// Its place among the records of a fetch as they're applied: tags,
    /// decks, the settings that decide progress, the choice of what syncs and
    /// the user's card types; then the changes to tags, in the order they were made, so
    /// that each applies to the tags as the fetch left them and to the cards
    /// as the device held them when it heard of it (`TagChanges.swift`); then
    /// captures, then cards, then the review log, so that what a record
    /// refers to comes before it. A type this version doesn't know comes
    /// last, to wait. Throws for a change to a tag that doesn't say when it
    /// was made.
    fileprivate func applyingRank() throws -> (Int, Int64) {
        switch SyncedRow.RecordType(rawValue: type) {
        case .tag, .deck, .progressSettings, .syncChoice, .userType: return (0, 0)
        case .tagChange:
            guard let madeAt = try time("madeAt") else {
                throw unreadable("A change to a tag from iCloud doesn't say when it was made")
            }
            return (1, madeAt.wholeMilliseconds)
        case .capture: return (2, 0)
        case .card: return (3, 0)
        case .reviewLogEntry: return (4, 0)
        case nil: return (5, 0)
        }
    }
}
