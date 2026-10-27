import FichaCore
import Foundation
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// what waits to be sent.
@testable import FichaData

/// Tests on how the settings that decide a card's progress sync (#315): two
/// devices, a Mac and an iPhone, each an engine in memory on one clock,
/// syncing through a fake iCloud, as `SyncTests`' do.
final class ProgressSettingsSyncTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device

    init() throws {
        mac = try Device(Engine(location: .inMemory, time: time), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time), syncingThrough: iCloud)
    }

    // The iPhone kept nothing before the update, so it moves in Ficha's.
    @Test("the settings that decide progress, moved in on one device at the update or changed there, reach the other")
    func theSettingsReachTheOtherDevice() async throws {
        let lucas = try lucasSettings()
        try mac.engine.moveInProgressSettings { lucas }
        try iPhone.engine.moveInProgressSettings { ReviewSettings.defaults.progress }
        try await mac.syncNow()
        try await iPhone.syncNow()
        #expect(try iPhone.engine.progressSettings() == lucas)
        #expect(try iPhone.engine.changesToSend().isEmpty)

        time.advance(by: minutes(1))
        var changed = lucas
        changed.ladder = try #require(Ladder(waits: [.seconds(hours(1)), .seconds(days(1))]))
        changed.forgottenOftenAfter = nil
        try iPhone.engine.saveProgressSettings(changed)
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.engine.progressSettings() == changed)
    }

    // The Mac sends first: of the ladder, its earlier change, which the
    // iPhone's later one replaces; of the new cards a day, its later change,
    // which the iPhone's earlier one, sent after it, doesn't replace.
    @Test("each setting changed on two devices keeps its latest change on both, whichever device sends last")
    func eachSettingKeepsItsLatestChange() async throws {
        let shortLadder = try #require(Ladder(waits: [.seconds(hours(1)), .seconds(days(1))]))
        let longLadder = try #require(Ladder(waits: [.seconds(hours(4)), .seconds(days(7)), .seconds(days(60))]))

        time.advance(by: minutes(1))
        var onMac = try mac.engine.progressSettings()
        onMac.ladder = shortLadder
        try mac.engine.saveProgressSettings(onMac)
        var onIPhone = try iPhone.engine.progressSettings()
        onIPhone.newCardsPerDay = 2
        try iPhone.engine.saveProgressSettings(onIPhone)
        time.advance(by: minutes(1))
        onIPhone.ladder = longLadder
        try iPhone.engine.saveProgressSettings(onIPhone)
        onMac.newCardsPerDay = 9
        try mac.engine.saveProgressSettings(onMac)
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let latest = ProgressSettings(
            ladder: longLadder, newCardsPerDay: 9, forgottenOftenAfter: ReviewSettings.defaults.forgottenOftenAfter)
        #expect(try mac.engine.progressSettings() == latest)
        #expect(try iPhone.engine.progressSettings() == latest)
    }

    @Test("settings changed while sync was off reach the other device once it's on again")
    func settingsChangedWhileSyncWasOffReachTheOtherDevice() async throws {
        try mac.engine.turnSyncOff()
        try mac.engine.saveProgressSettings(try lucasSettings())
        try await mac.syncNow()
        try await iPhone.syncNow()
        #expect(try iPhone.engine.progressSettings() == ReviewSettings.defaults.progress)

        try mac.engine.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.progressSettings() == lucasSettings())
    }

    @Test("a device's active hours, and the rest of its settings, stay its own while the ladder syncs")
    func activeHoursStayOnTheirDevice() async throws {
        var macSettings = ReviewSettings.defaults
        macSettings.activeHours = 7..<20
        macSettings.cardsPerAppearance = 3
        var iPhoneSettings = ReviewSettings.defaults
        iPhoneSettings.activeHours = 10..<23
        macSettings.progress = try lucasSettings()
        try mac.engine.saveProgressSettings(macSettings.progress)
        try await mac.syncNow()
        try await iPhone.syncNow()

        iPhoneSettings.progress = try iPhone.engine.progressSettings()

        #expect(iPhoneSettings.ladder == macSettings.ladder)
        #expect(iPhoneSettings.activeHours == 10..<23)
        #expect(iPhoneSettings.cardsPerAppearance == ReviewSettings.defaults.cardsPerAppearance)
    }
}
