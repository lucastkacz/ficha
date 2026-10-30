import FichaCore
import Foundation
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// what waits to be sent.
@testable import FichaData

/// Tests on a restore on a device that syncs, and on the zones the cards sync
/// in (ADR 0017, #317): two devices, a Mac and an iPhone, in Buenos Aires on
/// one clock, signed into one account of a fake iCloud. The Mac keeps its
/// cards in a data folder, with its backups, as the app does.
final class SyncedRestoreTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    /// The Mac's data folder.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaSyncedRestoreTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    let mac: Device
    let iPhone: Device

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // The Mac restores from Settings while its engine runs, which then
    // fetches what the iPhone changed: the restore ended the stretch that
    // engine started in, so what it tells is left aside.
    @Test("a restore turns sync off, which stays off across launches, and nothing comes or goes until it's turned on")
    func aRestoreTurnsSyncOff() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        // The backup holds a change that waits to be sent.
        mac.iCloud.isOffline = true
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        let backup = try mac.engine.backUpNow(.defaults)
        mac.iCloud.isOffline = false
        try await mac.syncNow()
        try await iPhone.syncNow()
        time.advance(by: minutes(1))
        try iPhone.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try await iPhone.syncNow()

        try mac.engine.restore(backup.name)
        try await mac.iCloud.fetchChanges()
        let saves = iCloud.saves
        try mac.relaunch()
        try await mac.syncNow()

        #expect(try mac.engine.syncStatus().offBecause == .restore)
        #expect(try mac.engine.cards().map(\.front).sorted() == ["petricor", "ubuntu"])
        #expect(try mac.engine.changesToSend().isEmpty)
        #expect(try mac.engine.savedSyncEngineState() == nil)
        #expect(iCloud.saves == saves)
    }

    // Only filosofía syncs (#355): petricor never went up, nor did the
    // iPhone's saudade, which stays; efímero, made after the backup, goes.
    @Test(
        "after a restore, turning sync on sends only the cards that sync, and the other device replaces only its own that sync, keeping the rest"
    )
    func aRestoreReplacesOnlyTheCardsThatSync() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["lenguaje"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try await mac.syncNow()
        try await iPhone.syncNow()
        try iPhone.engine.create(
            card(.word, front: "saudade", back: "Nostalgia de lo que se fue.", tags: ["lenguaje"]))
        try await iPhone.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        time.advance(by: minutes(1))
        try mac.engine.create(card(.word, front: "efímero", back: "Que dura poco.", tags: ["filosofía"]))
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().map(\.front).sorted() == ["efímero", "saudade", "ubuntu"])

        try mac.engine.restore(backup.name)
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front).sorted() == ["petricor", "ubuntu"])
        #expect(try iPhone.engine.cards().map(\.front).sorted() == ["saudade", "ubuntu"])
        #expect(try iPhone.engine.card(fronted: "ubuntu").asSeen == mac.engine.card(fronted: "ubuntu").asSeen)
        #expect(iCloud.records.filter { $0.type == SyncedRow.RecordType.card.rawValue }.count == 1)
        #expect(cardsZonesInICloud().count == 1)
    }

    // The iPhone was offline while the Mac restored and turned sync on: it
    // sends what it changed meanwhile before it fetches, as iCloud's engine
    // may.
    @Test(
        "turning sync on after a restore replaces the other devices' cards with the restored ones, their unsynced changes dropped, and leaves the files"
    )
    func turningSyncOnAfterARestoreReplacesTheOtherDevicesCards() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let birdInICloud = try #require(iCloud.records.first { $0.id == SyncedFile(bird).recordID })
        let backup = try mac.engine.backUpNow(.defaults)
        time.advance(by: minutes(1))
        try mac.engine.delete([mac.engine.card(fronted: "petricor").id])
        try mac.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        let hornero = try iPhone.engine.card(fronted: "¿Qué pájaro es?")
        try iPhone.engine.edit(
            hornero.id,
            with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero, Furnarius rufus.", frontImage: bird))
        try iPhone.engine.create(card(.word, front: "efímero", back: "Que dura poco."))

        try mac.engine.restore(backup.name)
        try mac.turnSyncOn()
        try await mac.syncNow()
        iPhone.iCloud.isOffline = false
        try await iPhone.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front).sorted() == ["petricor", "¿Qué pájaro es?"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.engine.card(fronted: "¿Qué pájaro es?").back == "Un hornero.")
        #expect(try iPhone.engine.keptImages() == [bird])
        #expect(iCloud.records.first { $0.id == SyncedFile(bird).recordID } == birdInICloud)
        #expect(cardsZonesInICloud().count == 1)
        #expect(try mac.engine.syncStatus().isOn)
    }

    // The Mac goes offline after the first card of the restore's copy went
    // up, as iCloud's engine sends in batches, and the iPhone fetches then,
    // as it does on the push for the new zone.
    @Test("a device that takes a restore's copy while it's still going up deletes none of its files from iCloud")
    func aDeviceTakingAPartialCopyDeletesNoFile() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let birdInICloud = try #require(iCloud.records.first { $0.id == SyncedFile(bird).recordID })
        let backup = try mac.engine.backUpNow(.defaults)

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        let macsICloud = mac.iCloud
        macsICloud.recordsPerBatch = 1
        macsICloud.onceSaved { macsICloud.isOffline = true }
        await #expect(throws: FakeICloudError.offline) { try await self.mac.syncNow() }
        try await iPhone.syncNow()
        #expect(try iPhone.engine.cards().map(\.front) == ["petricor"])
        macsICloud.isOffline = false
        for device in [mac, iPhone, mac, iPhone] {
            try await device.syncNow()
        }

        #expect(iCloud.records.first { $0.id == SyncedFile(bird).recordID } == birdInICloud)
        #expect(try iPhone.engine.keptImages() == [bird])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    // The backup is from before the bird went up, so only the Mac knows
    // iCloud holds it, which no fetch would tell it again: the bird's record
    // doesn't change.
    @Test(
        "a restore keeps what the device knows iCloud holds of its images, so turning sync on sends none of them again")
    func aRestoreKeepsWhatTheDeviceKnowsOfItsFilesInICloud() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let backup = try mac.engine.backUpNow(.defaults)
        try await mac.syncNow()
        #expect(iCloud.timesSent(SyncedFile(bird).recordID) == 1)

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await mac.syncNow()

        #expect(iCloud.timesSent(SyncedFile(bird).recordID) == 1)
        #expect(try mac.engine.keptImages() == [bird])
    }

    // The Mac is the only device, so no other fetches the zone it leaves.
    @Test("turning sync on after a restore deletes the zone of the cards before it, with no other device to hear of it")
    func turningSyncOnAfterARestoreDeletesTheZoneItLeaves() async throws {
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()

        #expect(cardsZonesInICloud().count == 1)
        let iPad = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        try await iPad.syncNow()
        #expect(try iPad.engine.cards().map(\.front) == ["petricor"])
    }

    // `ficha restore` runs on an engine of its own on the Mac's data folder,
    // only while the app doesn't, which then launches.
    @Test("ficha restore turns sync off too, and turning it on replaces the other devices' cards")
    func theCLIsRestoreDoesTheSame() async throws {
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        time.advance(by: minutes(1))
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try iPhone.engine.create(card(.word, front: "efímero", back: "Que dura poco."))
        try await iPhone.syncNow()

        let cli = try Engine(location: .folder(folder), time: time, calendar: calendar)
        try cli.restore(backup.name)
        try mac.relaunch()
        try await mac.syncNow()
        #expect(try mac.engine.syncStatus().offBecause == .restore)
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front) == ["petricor"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(cardsZonesInICloud().count == 1)
    }

    // An iPad whose cards were made before it ever synced starts syncing
    // after the Mac restored and turned sync on.
    @Test(
        "a device that starts syncing after a restore keeps its own cards, which join the restored ones")
    func aDeviceThatStartsSyncingAfterARestoreJoins() async throws {
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        try mac.engine.restore(backup.name)
        try mac.turnSyncOn()
        try await mac.syncNow()

        time.advance(by: minutes(1))
        let iPadsEngine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try iPadsEngine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        let iPad = try Device(iPadsEngine, syncingThrough: iCloud)
        try await iPad.syncNow()
        try await iPad.syncNow()
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try mac.engine.cards().map(\.front).sorted() == ["petricor", "ubuntu"])
        #expect(try iPad.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(cardsZonesInICloud().count == 1)
    }

    // MARK: - Who takes a restore's copy

    // The iPhone is signed out of iCloud while the Mac restores and turns
    // sync on, and signs back in after.
    @Test("a device signed out across a restore takes the restore's copy once it signs back in")
    func aDeviceSignedOutAcrossARestoreTakesTheCopy() async throws {
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try iPhone.signOut()

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try iPhone.signIn(to: iCloud)
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front) == ["petricor"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    // The iPad synced in another account, and its user signs it into the
    // Mac's after the Mac restored and turned sync on.
    @Test("a device that switches from another account after a restore joins the restored cards with its own")
    func aDeviceSwitchingAccountsAfterARestoreJoins() async throws {
        let iPad = try Device(
            Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: FakeICloud())
        try iPad.engine.create(card(.word, front: "efímero", back: "Que dura poco."))
        try await iPad.syncNow()
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try iPad.signIn(to: iCloud)
        try await iPad.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front).sorted() == ["efímero", "petricor"])
        #expect(try iPad.cardsAsSeen() == mac.cardsAsSeen())
    }

    // The iPad synced in another account first. Its user signs it out of
    // that account and into the Mac's while the app runs, after the Mac
    // restored and turned sync on: its engine tells a sign-out, then a
    // sign-in, rather than a switch.
    @Test("a device signed out and then into another account that holds a restore's zone keeps its cards, which join")
    func aDeviceSignedOutAndIntoAnotherAccountJoins() async throws {
        let iPad = try Device(
            Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: FakeICloud())
        try iPad.engine.create(card(.word, front: "efímero", back: "Que dura poco."))
        try await iPad.syncNow()
        time.advance(by: minutes(1))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try iPad.signOut()
        try iPad.signIn(to: iCloud)
        try await iPad.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front).sorted() == ["efímero", "petricor"])
        #expect(try iPad.cardsAsSeen() == mac.cardsAsSeen())
    }

    // The user purged Ficha's data. The Mac restores and turns sync on; the
    // iPhone, off since the purge, with a card made since, is turned on after.
    @Test("a device off since a purge takes the copy of a restore made since, once its sync is turned on")
    func aDeviceOffSinceAPurgeTakesARestoresCopy() async throws {
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        try iPhone.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await iPhone.syncNow()
        try await mac.syncNow()
        iCloud.purge()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try iPhone.engine.create(card(.word, front: "efímero", back: "Que dura poco."))

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try iPhone.turnSyncOn()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front) == ["petricor"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(cardsZonesInICloud().count == 1)
    }

    // A second Mac, which keeps its cards in a data folder too, with a card
    // it hasn't sent, takes the copy.
    @Test("a device saves a copy of its cards before it takes a restore's in their place, which brings them back")
    func aDeviceSavesACopyBeforeTakingARestores() async throws {
        let otherFolder = URL.temporaryDirectory.appending(
            path: "FichaSyncedRestoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: otherFolder) }
        let otherMac = try Device(
            Engine(location: .folder(otherFolder), time: time, calendar: calendar), syncingThrough: iCloud)
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await otherMac.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        try otherMac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        let before = try otherMac.engine.cards()

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await otherMac.syncNow()

        #expect(try otherMac.engine.cards().map(\.front) == ["petricor"])
        let copy = try #require(otherMac.engine.copies().first { $0.kind == .beforeICloudsCopy })
        try otherMac.engine.restore(copy.name)
        #expect(try otherMac.engine.cards() == before)
    }

    // The Mac renames economía after its backup, and restores it. The
    // iPhone, which heard of the rename, takes the restore's cards, and then
    // turns sync off and on, which sends again everything it holds.
    @Test("a rename a restore undid stays undone on every device, also once one sends everything again")
    func aRenameARestoreUndidStaysUndone() async throws {
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await mac.syncNow()
        try await iPhone.syncNow()
        #expect(try iPhone.engine.card(fronted: "inflación").tags == ["economics"])

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try iPhone.engine.turnSyncOff()
        try iPhone.turnSyncOn()
        for _ in 0..<3 {
            try await iPhone.syncNow()
            try await mac.syncNow()
        }

        #expect(try mac.engine.card(fronted: "inflación").tags == ["economía"])
        #expect(try iPhone.engine.card(fronted: "inflación").tags == ["economía"])
    }

    // Only filosofía syncs, so cepo stays on the iPhone. The Mac renames
    // economía, cepo with it, and the iPhone then gives cepo economía again;
    // the Mac's backup holds the rename, which the restore's zone brings.
    @Test(
        "a device that takes a restore's cards applies no change to a tag it heard of before, to the cards it keeps that don't sync"
    )
    func aRestoreAppliesNoChangeTwice() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try iPhone.engine.create(card(.concept, front: "cepo", back: "Un límite.", tags: ["economía"]))
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await mac.syncNow()
        try await iPhone.syncNow()
        time.advance(by: minutes(1))
        let cepo = try iPhone.engine.card(fronted: "cepo")
        try iPhone.engine.edit(
            cepo.id, with: card(.concept, front: "cepo", back: "Un límite.", tags: ["economics", "economía"]))
        let backup = try mac.engine.backUpNow(.defaults)

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try iPhone.engine.cards().map(\.front).sorted() == ["cepo", "ubuntu"])
        #expect(try iPhone.engine.card(fronted: "cepo").tags == ["economics", "economía"])
    }

    // The iPad's clock is an hour ahead of the Mac's, and the iPad made the
    // zone the devices sync in, named after its own clock.
    @Test("a restore's zone is newer than the zone it leaves, even when the Mac's clock is behind that zone's time")
    func aRestoresZoneIsNewerThanTheOneItLeaves() async throws {
        let iPad = try Device(
            Engine(location: .inMemory, time: ManualTimeSource(now: time.now + hours(1)), calendar: calendar),
            syncingThrough: iCloud)
        try iPad.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await iPad.syncNow()
        try await mac.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        try iPad.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try await iPad.syncNow()
        try await mac.syncNow()

        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await iPad.syncNow()
        try await mac.syncNow()

        #expect(try iPad.engine.cards().map(\.front) == ["ubuntu"])
        #expect(try iPad.cardsAsSeen() == mac.cardsAsSeen())
        #expect(cardsZonesInICloud().count == 1)
    }

    // `CKSyncEngine`'s documentation doesn't say whether an engine with no
    // saved state tells of a sign-in as it first meets the account: the one
    // the Mac starts as it turns sync on after the restore does here.
    @Test("an engine that tells of a sign-in as sync turns on after a restore leaves the device in the restore's zone")
    func aSignInAsSyncTurnsOnAfterARestoreKeepsTheZone() async throws {
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        try iPhone.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await iPhone.syncNow()
        try await mac.syncNow()

        iCloud.freshEnginesTellASignIn = true
        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front) == ["petricor"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(cardsZonesInICloud().count == 1)
    }

    // MARK: - The Sync tab

    // The Mac last synced before the restore, which iCloud's copy no longer
    // holds once sync is on again: the line says it hasn't synced until it
    // does, as after a purge.
    @Test(
        "after a restore, the Sync tab says turning sync on replaces iCloud's copy, and then that the Mac hasn't synced yet"
    )
    func theSyncTabSaysWhatTurningSyncOnDoes() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        let backup = try mac.engine.backUpNow(.defaults)
        time.advance(by: minutes(5))

        try mac.engine.restore(backup.name)
        var tab = mac.engine.openSyncTab()

        #expect(tab.status == .off(turningOn: .replacesICloudsCopy, sending: nil))
        #expect(!tab.switchIsOn)
        #expect(tab.canTurnSwitch)

        tab.turnSync(on: true)

        #expect(tab.status == .on(lastSynced: nil))
        #expect(tab.switchIsOn)
    }

    // MARK: - Purges

    // The iPhone was offline while the user purged Ficha's data and the Mac
    // turned sync on again; it fetches first, so it hears of the purge and
    // of the Mac's zone at once.
    @Test(
        "turning sync on after a purge joins every device's cards, and a device that missed the purge deletes none and stays on"
    )
    func aDeviceThatMissedThePurgeJoins() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        iPhone.iCloud.isOffline = true
        try iPhone.engine.create(card(.word, front: "efímero", back: "Que dura poco."))

        iCloud.purge()
        try await mac.syncNow()
        time.advance(by: minutes(1))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try mac.turnSyncOn()
        try await mac.syncNow()
        iPhone.iCloud.isOffline = false
        try await iPhone.iCloud.fetchChanges()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front).sorted() == ["efímero", "petricor", "ubuntu"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.engine.syncStatus().isOn)
        #expect(cardsZonesInICloud().count == 1)
    }

    // The devices sync in "Cards", the zone of a Ficha before #317. The
    // iPhone is offline, with a card edited, while the user purges Ficha's
    // data and a fresh iPad starts syncing, before any device turned sync on
    // again; the Mac hears of it all last.
    @Test(
        "a fresh device that starts after a purge syncs in a zone never used before, and a device that missed the purge loses no card"
    )
    func aFreshDeviceAfterAPurgeMakesANewZone() async throws {
        iCloud.saveZoneOfAnOlderFicha("Cards")
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        #expect(cardsZonesInICloud() == [ICloudZone(name: "Cards")])
        iPhone.iCloud.isOffline = true
        try iPhone.engine.edit(
            iPhone.engine.card(fronted: "ubuntu").id,
            with: card(.concept, front: "ubuntu", back: "Soy porque somos, dice el proverbio."))

        iCloud.purge()
        time.advance(by: minutes(1))
        let iPadsEngine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try iPadsEngine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        let iPad = try Device(iPadsEngine, syncingThrough: iCloud)
        try await iPad.syncNow()
        #expect(!cardsZonesInICloud().contains(ICloudZone(name: "Cards")))
        iPhone.iCloud.isOffline = false
        try await iPhone.syncNow()
        #expect(try iPhone.engine.syncStatus().offBecause == .purge)
        try iPhone.turnSyncOn()
        for device in [iPhone, iPad, mac, iPad, iPhone] {
            try await device.syncNow()
        }

        #expect(try iPad.engine.cards().map(\.front).sorted() == ["petricor", "ubuntu"])
        #expect(try iPad.engine.card(fronted: "ubuntu").back == "Soy porque somos, dice el proverbio.")
        #expect(try iPhone.cardsAsSeen() == iPad.cardsAsSeen())
        #expect(try mac.cardsAsSeen() == iPad.cardsAsSeen())
        #expect(cardsZonesInICloud().count == 1)
    }

    // Both devices heard of the purge, and the user turns sync on again on
    // each, a while apart.
    @Test("devices that turn sync on one by one after a purge sync in one zone, and a deletion made while off wins")
    func devicesTurningSyncOnAfterAPurgeLandInOneZone() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        iCloud.purge()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try iPhone.engine.delete([iPhone.engine.card(fronted: "ubuntu").id])

        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        time.advance(by: minutes(5))
        try iPhone.turnSyncOn()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.cards().map(\.front) == ["petricor"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(cardsZonesInICloud().count == 1)
    }

    // MARK: - Scratch runs

    // An agent's scratch run of Ficha Dev, with its second device, syncs in
    // the same account as the user's devices, and the Mac restores meanwhile.
    @Test("a scratch run syncs in zones of its own, which the user's devices leave alone, and no card crosses over")
    func aScratchRunSyncsInZonesOfItsOwn() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let name = try #require(ScratchName("agent-317"))
        let scratch = try Device(
            Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud, in: .scratch(name))
        let scratchSecond = try Device(
            Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud, in: .scratch(name))
        let bird = try scratch.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try scratch.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await scratch.syncNow()
        try await scratchSecond.syncNow()

        let backup = try mac.engine.backUpNow(.defaults)
        try mac.engine.restore(backup.name)
        time.advance(by: minutes(1))
        try mac.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()
        try await scratch.syncNow()
        try await scratchSecond.syncNow()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().map(\.front) == ["ubuntu"])
            #expect(try device.engine.keptImages().isEmpty)
        }
        #expect(try scratchSecond.engine.cards().map(\.front) == ["¿Qué pájaro es?"])
        #expect(try scratchSecond.engine.keptImages() == [bird])
        let zones = iCloud.zones.map(\.name)
        #expect(zones.filter { $0.hasPrefix("Cards-agent-317.") }.count == 1)
        #expect(zones.contains("Files-agent-317"))
        #expect(cardsZonesInICloud().count == 1)
    }

    @Test(
        "a scratch run's name holds letters, digits, - and _ alone, so that no run's zones are another's or Ficha's own",
        arguments: ["", "agent.317", "agent/317", "agent 317", "agenté"])
    func aScratchNameHoldsOnlyLettersDigitsAndDashes(_ name: String) {
        #expect(ScratchName(name) == nil)
    }

    /// Ficha's own cards' zones that iCloud holds, empty or not.
    private func cardsZonesInICloud() -> Set<ICloudZone> {
        iCloud.zones.filter { $0.name == "Cards" || $0.name.hasPrefix("Cards.") }
    }
}
