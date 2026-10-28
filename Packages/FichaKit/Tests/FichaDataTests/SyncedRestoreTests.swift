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
}
