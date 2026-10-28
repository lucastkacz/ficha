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
        #expect(iCloud.timesSent(SyncedFile(bird).recordID) == 1)
        let cardsZones = Set(iCloud.records.filter { $0.type == "card" }.map(\.id.zone))
        #expect(cardsZones.count == 1)
        #expect(try mac.engine.syncStatus().isOn)
    }
}
