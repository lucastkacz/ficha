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
        let kept = try customProgressSettings()
        try mac.engine.moveInProgressSettings { kept }
        try iPhone.engine.moveInProgressSettings { ReviewSettings.defaults.progress }
        try await mac.syncNow()
        try await iPhone.syncNow()
        #expect(try iPhone.engine.progressSettings() == kept)
        #expect(try iPhone.engine.changesToSend().isEmpty)

        time.advance(by: minutes(1))
        var changed = kept
        changed.ladder = try #require(Ladder(waits: [.seconds(hours(1)), .seconds(days(1))]))
        changed.forgottenOftenAfter = nil
        try iPhone.engine.saveProgressSettings(changed, changedFrom: kept)
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
        try mac.engine.saveProgressSettings(onMac.with(ladder: shortLadder), changedFrom: onMac)
        onMac.ladder = shortLadder
        var onIPhone = try iPhone.engine.progressSettings()
        try iPhone.engine.saveProgressSettings(onIPhone.with(newCardsPerDay: 2), changedFrom: onIPhone)
        onIPhone.newCardsPerDay = 2
        time.advance(by: minutes(1))
        try iPhone.engine.saveProgressSettings(onIPhone.with(ladder: longLadder), changedFrom: onIPhone)
        try mac.engine.saveProgressSettings(onMac.with(newCardsPerDay: 9), changedFrom: onMac)
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let latest = ProgressSettings(
            ladder: longLadder, newCardsPerDay: 9, forgottenOftenAfter: ReviewSettings.defaults.forgottenOftenAfter)
        #expect(try mac.engine.progressSettings() == latest)
        #expect(try iPhone.engine.progressSettings() == latest)
    }

    // The Mac's Settings read the settings before the iPhone's ladder came,
    // and still show the ladder it had.
    @Test(
        "a change in Settings to one setting keeps another device's later change to another, which Settings hadn't read"
    )
    func aChangeKeepsAnotherDevicesChangeToAnotherSetting() async throws {
        let shownOnMac = try mac.engine.progressSettings()
        time.advance(by: minutes(1))
        let onIPhone = try iPhone.engine.progressSettings()
        let iPhonesLadder = try #require(Ladder(waits: [.seconds(hours(1)), .seconds(days(1))]))
        try iPhone.engine.saveProgressSettings(onIPhone.with(ladder: iPhonesLadder), changedFrom: onIPhone)
        try await iPhone.syncNow()
        try await mac.syncNow()

        time.advance(by: minutes(1))
        try mac.engine.saveProgressSettings(shownOnMac.with(newCardsPerDay: 2), changedFrom: shownOnMac)
        try await mac.syncNow()
        try await iPhone.syncNow()

        let latest = ProgressSettings(
            ladder: iPhonesLadder, newCardsPerDay: 2, forgottenOftenAfter: ReviewSettings.defaults.forgottenOftenAfter)
        #expect(try mac.engine.progressSettings() == latest)
        #expect(try iPhone.engine.progressSettings() == latest)
    }

    // A device that never changed its settings holds Ficha's with no times,
    // as one that applied such a record does.
    @Test("settings moved in or changed on a device stay when a record of Ficha's settings with no times comes")
    func aRecordWithNoTimesLeavesTheSettings() throws {
        let kept = try customProgressSettings()
        try mac.engine.moveInProgressSettings { kept }

        let received = try mac.engine.writeWithoutRecording { db in
            try receive(try recordOfFichasSettingsWithNoTimes(), in: db)
        }

        #expect(received == .applied)
        #expect(try mac.engine.progressSettings() == kept)
    }

    @Test("settings changed while sync was off reach the other device once it's on again")
    func settingsChangedWhileSyncWasOffReachTheOtherDevice() async throws {
        try mac.engine.turnSyncOff()
        try mac.engine.saveProgressSettings(try customProgressSettings(), changedFrom: ReviewSettings.defaults.progress)
        try await mac.syncNow()
        try await iPhone.syncNow()
        #expect(try iPhone.engine.progressSettings() == ReviewSettings.defaults.progress)

        try mac.engine.turnSyncOn()
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.progressSettings() == customProgressSettings())
    }
}

/// The record of Ficha's settings that decide progress, with no time for any
/// of them, as a device that never changed them sends it.
private func recordOfFichasSettingsWithNoTimes() throws -> ICloudRecord {
    let fichas = ReviewSettings.defaults.progress
    let waits = try JSONEncoder().encode(fichas.ladder.waits.map { $0.components.seconds })
    return ICloudRecord(
        id: SyncedRow.progressSettings.recordID, type: SyncedRow.RecordType.progressSettings.rawValue,
        fields: [
            SyncedField.ladder.rawValue: .string(String(decoding: waits, as: UTF8.self)),
            SyncedField.newCardsPerDay.rawValue: .int(Int64(fichas.newCardsPerDay)),
            SyncedField.forgottenOftenAfter.rawValue: fichas.forgottenOftenAfter.map { .int(Int64($0)) },
        ],
        systemFields: nil)
}

extension ProgressSettings {
    /// These settings with `ladder` in place of theirs.
    fileprivate func with(ladder: Ladder) -> ProgressSettings {
        var settings = self
        settings.ladder = ladder
        return settings
    }

    /// These settings with `newCardsPerDay` in place of theirs.
    fileprivate func with(newCardsPerDay: Int) -> ProgressSettings {
        var settings = self
        settings.newCardsPerDay = newCardsPerDay
        return settings
    }
}
