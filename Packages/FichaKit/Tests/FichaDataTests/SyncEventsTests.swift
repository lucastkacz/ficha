import FichaCore
import Foundation
import Testing

// For the interface to iCloud's engine, which the fake implements.
@testable import FichaData

/// Tests on what sync does as the iCloud account changes, as the user deletes
/// Ficha's data in iCloud's settings, as iCloud fills up, and as the user
/// turns sync off and on (ADR 0017, #317): two devices, a Mac and an iPhone,
/// in Buenos Aires on one clock, signed into one account of a fake iCloud.
/// The Mac keeps its files in a data folder, as the app does.
final class SyncEventsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    /// The Mac's data folder.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaSyncEventsTests-\(UUID().uuidString)",
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

    /// A device that starts syncing now and fetches what `account` holds, as
    /// a new iPhone would: what it keeps is what iCloud holds. It sends
    /// nothing.
    func aFreshDevice(in account: FakeICloud) async throws -> Device {
        let device = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: account)
        try await device.iCloud.fetchChanges()
        try await device.iCloud.fetchChanges()
        return device
    }

    // MARK: - Accounts

    @Test("signing out of iCloud keeps the cards and stops sync, and what changed meanwhile goes once signed in again")
    func signingOutKeepsTheCards() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()

        try mac.signOut()
        time.advance(by: minutes(1))
        try mac.engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let saves = iCloud.saves
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try mac.engine.cards().map(\.front) == ["ubuntu"])
        #expect(try mac.engine.syncStatus().hasICloudAccount == false)
        #expect(iCloud.saves == saves)
        #expect(try iPhone.cardsAsSeen().map(\.flag) == [nil])

        try mac.signIn(to: iCloud)
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try mac.engine.syncStatus().hasICloudAccount == true)
        #expect(try iPhone.cardsAsSeen().map(\.flag?.note) == ["Falta un ejemplo"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    // iCloud's engine forgets what it was handed at the change, so what goes
    // is what the device recorded to send.
    @Test("changes made offline before an account change reach iCloud after it, a deletion included")
    func changesSurviveAnAccountChange() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        mac.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.edit(ubuntu.id, with: card(.concept, front: "ubuntu", back: "Yo soy porque somos."))
        try mac.engine.delete([mac.engine.card(fronted: "petricor").id])
        await #expect(throws: FakeICloudError.self) { try await self.mac.syncNow() }

        try mac.signOut()
        try mac.signIn(to: iCloud)
        mac.iCloud.isOffline = false
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().map(\.back) == ["Yo soy porque somos."])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    // The Mac signs into another account while the app doesn't run: its
    // engine tells of the change once it runs, after the app handed it what
    // waited, which the change makes it forget.
    @Test("a device that meets another account at launch keeps its cards, and they join that account's")
    func anAccountSwitchedWhileQuitJoinsTheCards() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        let otherAccount = FakeICloud()
        let iPhoneThere = try Device(
            Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: otherAccount)
        try iPhoneThere.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try await iPhoneThere.syncNow()

        let macThere = try Device(mac.engine, syncingThrough: otherAccount)
        try await macThere.syncNow()
        try await iPhoneThere.syncNow()

        for device in [macThere, iPhoneThere] {
            #expect(try device.engine.cards().map(\.front).sorted() == ["saudade", "ubuntu"])
        }
        #expect(try await aFreshDevice(in: iCloud).engine.cards().map(\.front) == ["ubuntu"])
    }

    // MARK: - Purges

    @Test("a purge of Ficha's data in iCloud keeps every device's cards and turns sync off, and nothing goes up")
    func aPurgeKeepsTheCardsAndTurnsSyncOff() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        try await iPhone.syncNow()

        iCloud.purge()
        // The Mac sends before it fetches, so iCloud tells it of the purge
        // as it refuses its change; the iPhone hears of it as it fetches.
        try mac.engine.flag(hornero.id, note: note("Falta el nombre científico"))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.bury(hornero.id)
        try await mac.syncNow()

        for device in [mac, iPhone] {
            #expect(try device.engine.syncStatus().offBecause == .purge)
            #expect(try device.engine.cards().map(\.front) == ["¿Qué pájaro es?"])
            #expect(try device.engine.keptImages() == [bird])
        }
        #expect(iCloud.records.isEmpty)
    }

    // The Mac hears of the purge as iCloud refuses its deletion, before it
    // fetches.
    @Test("a purge heard as iCloud refuses a deletion turns sync off, as one heard on a save does")
    func aPurgeHeardOnADeletionTurnsSyncOff() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()

        iCloud.purge()
        try mac.engine.delete([mac.engine.card(fronted: "petricor").id])
        try await mac.send()

        #expect(try mac.engine.syncStatus().offBecause == .purge)
        #expect(try mac.engine.cards().map(\.front) == ["ubuntu"])
    }

    @Test("turning sync on after a purge sends every card and file again, and each device's cards join, none deleted")
    func turningSyncOnAfterAPurgeSendsEverything() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        iCloud.purge()
        try await mac.syncNow()
        try await iPhone.syncNow()
        try iPhone.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try iPhone.engine.delete([iPhone.engine.card(fronted: "ubuntu").id])

        try mac.turnSyncOn()
        try await mac.syncNow()
        let afterTheMac = try await aFreshDevice(in: iCloud)
        try iPhone.turnSyncOn()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try afterTheMac.engine.cards().map(\.front).sorted() == ["ubuntu", "¿Qué pájaro es?"])
        #expect(try afterTheMac.engine.keptImages() == [bird])
        #expect(try mac.engine.syncStatus().isOn)
        // The iPhone deleted ubuntu while sync was off, which goes when it's
        // on: a deletion wins.
        #expect(try mac.engine.cards().map(\.front).sorted() == ["saudade", "¿Qué pájaro es?"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.engine.keptImages() == [bird])
    }

    // MARK: - The switch

    @Test("turning sync off keeps the deletions that waited, and turning it on sends them, with those made while off")
    func deletionsWaitWhileSyncIsOff() async throws {
        for front in ["ubuntu", "petricor", "saudade"] {
            try approveCard(front, in: mac.engine)
        }
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.delete([mac.engine.card(fronted: "ubuntu").id])

        try mac.turnSyncOff()
        try mac.engine.delete([mac.engine.card(fronted: "petricor").id])
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try mac.engine.syncStatus().offBecause == .user)
        #expect(try iPhone.engine.cards().count == 3)

        try mac.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().map(\.front) == ["saudade"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try mac.engine.syncStatus().offBecause == nil)
    }

    // The Mac's card lets go of the image before it sends that change, so
    // the Mac kept the image only because iCloud holds it. The iPhone later
    // puts it on a card of its own.
    @Test("turning sync off lets go of an image no card uses, which comes back once a card uses it again")
    func turningSyncOffLetsGoOfFilesNoCardUses() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.edit(hornero.id, with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero."))
        #expect(try mac.engine.keptImages() == [bird])

        try mac.turnSyncOff()
        #expect(try mac.engine.keptImages().isEmpty)
        time.advance(by: minutes(1))
        try iPhone.engine.create(card(nil, front: "Furnarius rufus", back: "El hornero.", backImage: bird))
        try await iPhone.syncNow()
        try mac.turnSyncOn()
        for device in [mac, mac, iPhone] {
            try await device.syncNow()
        }

        #expect(try mac.engine.card(fronted: "Furnarius rufus").backImage == bird)
        #expect(try mac.engine.card(fronted: "¿Qué pájaro es?").frontImage == nil)
        #expect(try mac.engine.keptImages() == [bird])
        #expect(try mac.engine.image(bird) == iPhone.engine.image(bird))
    }

    @Test("the status says when the device last synced, which stays while it can't reach iCloud")
    func theStatusSaysWhenTheDeviceLastSynced() async throws {
        #expect(try mac.engine.syncStatus().lastSynced == nil)
        let synced = time.now
        try await mac.syncNow()
        time.advance(by: minutes(5))
        mac.iCloud.isOffline = true
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        await #expect(throws: FakeICloudError.self) { try await self.mac.syncNow() }

        #expect(try mac.engine.syncStatus().lastSynced == synced)
    }

    // MARK: - A full iCloud

    // The card fits and its sound doesn't, which waits.
    @Test("in a full iCloud changes wait and the status says so, and once there's room they go, their files along")
    func aFullICloudKeepsChangesWaiting() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let song = try await addTone(440, to: mac.engine)
        let size = try mac.engine.sound(song).count
        iCloud.leaveRoom(forBytes: size - 1)

        try mac.engine.create(card(.word, front: "¿Cómo suena un la?", back: "Así.", backSound: song))
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try mac.engine.syncStatus().iCloudIsFull)
        #expect(try iPhone.engine.card(fronted: "¿Cómo suena un la?").backSound == song)
        #expect(try iPhone.engine.keptSounds().isEmpty)

        // Room comes without a change on the Mac: its next fetch sends what
        // waited.
        iCloud.makeRoom()
        try await mac.iCloud.fetchChanges()
        try await mac.iCloud.sendChanges()
        try await iPhone.syncNow()

        #expect(try !mac.engine.syncStatus().iCloudIsFull)
        #expect(try iPhone.engine.sound(song) == mac.engine.sound(song))
    }

    // A zone doesn't fit either, so nothing does.
    @Test("a device whose first sync meets a full iCloud sends everything once there's room")
    func aFirstSyncIntoAFullICloudWaits() async throws {
        let full = FakeICloud()
        full.fillUp()
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        let macThere = try Device(mac.engine, syncingThrough: full)

        try await macThere.syncNow()
        #expect(try mac.engine.syncStatus().iCloudIsFull)
        #expect(full.records.isEmpty)

        full.makeRoom()
        try await macThere.syncNow()

        #expect(try !mac.engine.syncStatus().iCloudIsFull)
        #expect(try await aFreshDevice(in: full).engine.cards().map(\.front) == ["ubuntu"])
    }
}
