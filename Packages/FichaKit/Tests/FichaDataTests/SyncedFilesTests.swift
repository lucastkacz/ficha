import FichaCore
import Foundation
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// the files each device keeps.
@testable import FichaData

/// Tests on the images and sounds on cards as they sync (ADR 0017): two
/// devices, a Mac and an iPhone, in Buenos Aires on one clock, syncing
/// through a fake iCloud. The Mac keeps its files in a data folder, as the
/// app does, and the iPhone in memory, so that both of the engine's ways of
/// keeping files send them and take them.
final class SyncedFilesTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    /// The Mac's data folder.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaSyncedFilesTests-\(UUID().uuidString)",
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

    /// A device that starts syncing now and fetches what iCloud holds, as a
    /// new iPhone would: what it keeps is what the user gets on one. It
    /// sends nothing, so iCloud stays as the test left it.
    func aFreshDevice() async throws -> Device {
        let device = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        try await device.iCloud.fetchChanges()
        return device
    }

    @Test("a card's image and sound reach the other device, as they are on the first")
    func aCardsImageAndSoundReachTheOtherDevice() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let song = try await addTone(440, to: mac.engine)
        try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backSound: song))

        try await mac.syncNow()
        try await iPhone.syncNow()

        let hornero = try iPhone.engine.card(fronted: "¿Qué pájaro es?")
        #expect(hornero.frontImage == bird)
        #expect(hornero.backSound == song)
        #expect(try iPhone.engine.image(bird) == mac.engine.image(bird))
        #expect(try iPhone.engine.sound(song) == mac.engine.sound(song))
    }

    // The iPhone puts the image on a card of its own before it first syncs,
    // as it would by importing the same deck: it sends it too, which iCloud
    // turns down, holding it already.
    @Test(
        "the same file on two cards goes up once from each device that has it, and a device that has it already keeps it once"
    )
    func theSameFileOnTwoCardsGoesUpOnceFromEachDevice() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let song = try await addTone(440, to: mac.engine)
        try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, frontSound: song))
        try mac.engine.create(card(nil, front: "¿Cómo canta el hornero?", back: "Así.", backSound: song))
        try mac.engine.create(card(nil, front: "hornero", back: "Hace su nido de barro.", backImage: bird))
        try await mac.syncNow()
        #expect(try iPhone.engine.addImage(picture(width: 800, height: 600, red: 0.8)) == bird)
        try iPhone.engine.create(card(nil, front: "Furnarius rufus", back: "El hornero.", backImage: bird))

        for device in [iPhone, mac, iPhone, mac] {
            try await device.syncNow()
        }

        #expect(iCloud.timesSent(SyncedFile(bird).recordID) == 2)
        #expect(iCloud.timesSent(SyncedFile(song).recordID) == 1)
        #expect(try iPhone.engine.keptImages() == [bird])
        #expect(try iPhone.engine.keptSounds() == [song])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    // The iPhone fetches the cards' zone before the files', as iCloud's
    // engine may.
    @Test(
        "a card whose image and sound haven't arrived shows its sides without them, with no error, and with them once they arrive"
    )
    func aCardShowsItsSidesBeforeItsFilesArrive() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let song = try await addTone(440, to: mac.engine)
        try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backSound: song))
        try await mac.syncNow()
        try iPhone.sync.sendWhatChanged(to: iPhone.iCloud)
        try await iPhone.iCloud.sendChanges()
        try await iPhone.iCloud.fetchChanges(in: [.cards])
        let hornero = try iPhone.engine.card(fronted: "¿Qué pájaro es?")
        let ladder = ReviewSettings.defaults.ladder
        var window = iPhone.engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        window.select([hornero.id])

        let panel = try iPhone.engine.openPanel(
            .reviewNow, with: iPhone.engine.reviewNow(.defaults), settings: .defaults)

        #expect(panel.content == .firstView(hornero))
        #expect(panel.images[bird] == nil)
        #expect(panel.sounds[song] == nil)
        #expect(window.images[bird] == nil)
        #expect(window.sounds[song] == nil)

        try await iPhone.syncNow()
        window.read(on: ladder)
        let panelOnceThere = try iPhone.engine.openPanel(
            .reviewNow, with: iPhone.engine.reviewNow(.defaults), settings: .defaults)

        #expect(try window.images[bird]?.get() == mac.engine.image(bird))
        #expect(try window.sounds[song]?.get().data == mac.engine.sound(song))
        #expect(try panelOnceThere.images[bird]?.get() == mac.engine.image(bird))
        #expect(try panelOnceThere.sounds[song]?.get().data == mac.engine.sound(song))
    }

    // A capture comes in on the Mac while it fetches, so a change waits to
    // go up when the fetch ends. Once that one goes too, the next fetch ends
    // in sync, and the next send deletes the image.
    @Test(
        "an image no card uses leaves iCloud only once its device is in sync, and then leaves the other device too"
    )
    func aFileNoCardUsesLeavesICloudOnlyInSync() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.edit(hornero.id, with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero."))

        try mac.sync.sendWhatChanged(to: mac.iCloud)
        try await mac.iCloud.sendChanges()
        try mac.engine.newCapture("petricor")
        try await mac.iCloud.fetchChanges()
        try await mac.iCloud.sendChanges()

        #expect(try await aFreshDevice().engine.keptImages() == [bird])

        try await mac.syncNow()
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try await aFreshDevice().engine.keptImages().isEmpty)
        #expect(try mac.engine.keptImages().isEmpty)
        #expect(try iPhone.engine.keptImages().isEmpty)
        #expect(try iPhone.engine.card(fronted: "¿Qué pájaro es?").frontImage == nil)
    }

    // The Mac is in sync when it deletes the image: it can't know of the
    // iPhone's card, made offline, which hears the image left and sends it
    // again.
    @Test("an image another device's card uses, in a change still waiting there, isn't lost when it leaves iCloud")
    func aFileAnotherDeviceStillNeedsIsntLost() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        try await iPhone.syncNow()
        iPhone.iCloud.isOffline = true
        try iPhone.engine.create(card(nil, front: "Furnarius rufus", back: "El hornero.", backImage: bird))
        try mac.engine.edit(hornero.id, with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero."))
        try await mac.syncNow()
        try await mac.syncNow()
        #expect(try await aFreshDevice().engine.keptImages().isEmpty)

        iPhone.iCloud.isOffline = false
        for device in [iPhone, iPhone, mac] {
            try await device.syncNow()
        }

        #expect(try await aFreshDevice().engine.keptImages() == [bird])
        #expect(try mac.engine.card(fronted: "Furnarius rufus").backImage == bird)
        #expect(try mac.engine.image(bird) == iPhone.engine.image(bird))
        #expect(try mac.cardsAsSeen() == iPhone.cardsAsSeen())
    }

    // The Mac's card lets go of the image before the Mac hears of the
    // iPhone's card, and iCloud's record of the image doesn't change, so no
    // fetch would bring it to the Mac again.
    @Test("an image one device's card lets go of, while another device's card takes it, stays on both devices")
    func aFileOneCardLetsGoOfWhileAnotherTakesItStays() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.edit(hornero.id, with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero."))
        try iPhone.engine.create(card(nil, front: "Furnarius rufus", back: "El hornero.", backImage: bird))

        for device in [iPhone, mac, iPhone, mac] {
            try await device.syncNow()
        }

        #expect(try mac.engine.image(bird) == iPhone.engine.image(bird))
        #expect(try await aFreshDevice().engine.keptImages() == [bird])
        #expect(try mac.cardsAsSeen() == iPhone.cardsAsSeen())
    }

    // Where #313 meets this ticket: the iPhone takes the Mac's deletion of
    // the card, which lets go of its image, and keeps the image while iCloud
    // holds it. Both devices end in sync, and both delete it from iCloud.
    @Test("an image whose card another device deleted stays while iCloud holds it, and then leaves both devices")
    func aDeletedCardsImageLeavesWithICloud() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        try await iPhone.syncNow()

        try mac.engine.delete([hornero.id])
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().isEmpty)
        #expect(try iPhone.engine.keptImages() == [bird])
        #expect(try await aFreshDevice().engine.keptImages() == [bird])

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try await aFreshDevice().engine.keptImages().isEmpty)
        #expect(try mac.engine.keptImages().isEmpty)
        #expect(try iPhone.engine.keptImages().isEmpty)
    }

    // Where #315 meets this ticket: a change of the settings waits to go up
    // like a card's, so the Mac's fetch doesn't end in sync until it went.
    @Test("an image no card uses stays in iCloud while a change of the settings that decide progress waits to go up")
    func aFileWaitsForASettingsChangeToGoUp() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.edit(hornero.id, with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero."))

        try mac.sync.sendWhatChanged(to: mac.iCloud)
        try await mac.iCloud.sendChanges()
        let before = try mac.engine.progressSettings()
        var changed = before
        changed.ladder = try #require(Ladder(waits: [.seconds(hours(1)), .seconds(days(1))]))
        try mac.engine.saveProgressSettings(changed, changedFrom: before)
        try await mac.iCloud.fetchChanges()
        try await mac.iCloud.sendChanges()

        #expect(try await aFreshDevice().engine.keptImages() == [bird])

        try await mac.syncNow()
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try await aFreshDevice().engine.keptImages().isEmpty)
        #expect(try iPhone.engine.progressSettings() == changed)
        #expect(try iPhone.engine.keptImages().isEmpty)
    }

    // The Mac's card lets go of the image while its upload is on its way, so
    // the Mac removes it before it hears iCloud holds it, and, as CloudKit
    // usually does, iCloud doesn't hand the Mac its own save back. The
    // iPhone then puts the same image on a card of its own, as an import of
    // the same deck would, which iCloud turns down, holding the Mac's.
    @Test(
        "an image a card lets go of while it uploads, which another device's card takes later, comes back to the first device"
    )
    func aFileLetGoOfWhileItUploadsComesBack() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        mac.iCloud.getsItsOwnSavesBack = false
        let macEngine = mac.engine
        mac.iCloud.onceSaved {
            try macEngine.edit(hornero.id, with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero."))
        }
        try await mac.syncNow()
        #expect(try iPhone.engine.addImage(picture(width: 800, height: 600, red: 0.8)) == bird)
        try iPhone.engine.create(card(nil, front: "Furnarius rufus", back: "El hornero.", backImage: bird))

        for device in [iPhone, mac, mac] {
            try await device.syncNow()
        }

        #expect(try mac.engine.image(bird) == iPhone.engine.image(bird))
    }

    // The iPhone can't keep the image as it comes, as when its disk is full,
    // so its card uses an image iCloud holds and it lacks, whose record won't
    // change again. Meanwhile a sound no card uses any more waits in iCloud,
    // and the iPhone deletes it only once it has the image.
    @Test("an image that couldn't be kept as it came is fetched again, and until it is, no file leaves iCloud")
    func aFileThatCouldntBeKeptIsFetchedAgain() async throws {
        let song = try await addTone(440, to: mac.engine)
        let hornero = try mac.engine.create(
            card(nil, front: "¿Cómo canta el hornero?", back: "Así.", backSound: song))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.edit(hornero.id, with: card(nil, front: "¿Cómo canta el hornero?", back: "A dúo."))
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try mac.sync.sendWhatChanged(to: mac.iCloud)
        try await mac.iCloud.sendChanges()

        iPhone.iCloud.losesFetchedFiles = true
        try await iPhone.syncNow()
        try await iPhone.iCloud.sendChanges()

        #expect(try await aFreshDevice().engine.keptSounds() == [song])

        iPhone.iCloud.losesFetchedFiles = false
        try await iPhone.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.image(bird) == mac.engine.image(bird))
        #expect(try await aFreshDevice().engine.keptSounds().isEmpty)
    }

    // The Mac's fetch ends in sync, and its deletion of the sound waits to be
    // sent while the iPhone sends a card with it, which the Mac fetches only
    // after its deletion went: iCloud then lacks a sound a card uses.
    @Test("a sound a card uses that iCloud lacks is sent again, and reaches the device whose deletion it outlived")
    func aFileICloudLacksIsSentAgain() async throws {
        let song = try await addTone(440, to: mac.engine)
        let hornero = try mac.engine.create(
            card(nil, front: "¿Cómo canta el hornero?", back: "Así.", backSound: song))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.edit(hornero.id, with: card(nil, front: "¿Cómo canta el hornero?", back: "A dúo."))
        try await mac.syncNow()
        try iPhone.engine.create(card(nil, front: "Furnarius rufus", back: "El hornero.", frontSound: song))
        try await iPhone.syncNow()
        try await mac.syncNow()
        #expect(try await aFreshDevice().engine.keptSounds().isEmpty)

        for device in [iPhone, iPhone, mac] {
            try await device.syncNow()
        }

        #expect(try await aFreshDevice().engine.keptSounds() == [song])
        #expect(try mac.engine.sound(song) == iPhone.engine.sound(song))
        #expect(try mac.cardsAsSeen() == iPhone.cardsAsSeen())
    }
}
