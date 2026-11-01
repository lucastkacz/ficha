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
            ladder: longLadder, scheduler: .standard, newCardsPerDay: 9,
            forgottenOftenAfter: ReviewSettings.defaults.forgottenOftenAfter)
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
            ladder: iPhonesLadder, scheduler: .standard, newCardsPerDay: 2,
            forgottenOftenAfter: ReviewSettings.defaults.forgottenOftenAfter)
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

    // The Mac sends first: of the learning steps, its earlier change, which
    // the iPhone's later one replaces; of the relearning steps, its later
    // change, which the iPhone's earlier one, sent after it, doesn't replace.
    @Test(
        "each scheduling setting changed on two devices keeps its latest change on both, whichever device sends last")
    func eachSchedulingSettingKeepsItsLatestChange() async throws {
        time.advance(by: minutes(1))
        let onMac = try mac.engine.progressSettings()
        let macsFirst = try onMac.scheduler.with(learningSteps: [.seconds(minutes(10)), .seconds(minutes(30))])
            .with(desiredRetention: 0.8)
        try mac.engine.saveProgressSettings(onMac.with(scheduler: macsFirst), changedFrom: onMac)
        let onIPhone = try iPhone.engine.progressSettings()
        let iPhonesFirst = try onIPhone.scheduler.with(relearningSteps: []).with(longestIntervalInDays: 365)
        try iPhone.engine.saveProgressSettings(onIPhone.with(scheduler: iPhonesFirst), changedFrom: onIPhone)
        time.advance(by: minutes(1))
        try iPhone.engine.saveProgressSettings(
            onIPhone.with(
                scheduler: try iPhonesFirst.with(learningSteps: [.seconds(hours(2))]).with(parameters: customParameters)
            ),
            changedFrom: onIPhone.with(scheduler: iPhonesFirst))
        try mac.engine.saveProgressSettings(
            onMac.with(scheduler: try macsFirst.with(relearningSteps: [.seconds(minutes(30))])),
            changedFrom: onMac.with(scheduler: macsFirst))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let latest = try #require(
            Scheduler(
                learningSteps: [.seconds(hours(2))], relearningSteps: [.seconds(minutes(30))], desiredRetention: 0.8,
                longestIntervalInDays: 365, parameters: customParameters))
        #expect(try mac.engine.progressSettings().scheduler == latest)
        #expect(try iPhone.engine.progressSettings().scheduler == latest)
    }

    // A Ficha from before the scheduler's settings sends its record without
    // them, nor when they changed: the ladder it changed still comes.
    @Test(
        "a record from a Ficha before the scheduling settings leaves them as the device holds them, and brings the rest"
    )
    func aRecordFromBeforeTheSchedulingSettingsLeavesThem() throws {
        let kept = try customProgressSettings()
        try mac.engine.moveInProgressSettings { kept }
        time.advance(by: minutes(1))
        let ladder = try #require(Ladder(waits: [.seconds(hours(1)), .seconds(days(1))]))

        let received = try mac.engine.writeWithoutRecording { db in
            try receive(try recordOfFichasSettings(changing: .ladder, to: ladderValue(ladder), at: time.now), in: db)
        }

        #expect(received == .applied)
        #expect(try mac.engine.progressSettings() == kept.with(ladder: ladder))
    }

    @Test(
        "a record whose scheduling setting breaks its rule waits, and the device keeps the settings it holds",
        arguments: [
            (SyncedField.learningSteps, ICloudValue.string("[300]")),
            (.learningSteps, .string("[86400]")),
            (.learningSteps, .string("[3600,1800]")),
            (.relearningSteps, .string("[600,600]")),
            (.relearningSteps, .string("[\"an hour\"]")),
            (.desiredRetention, .double(0.69)),
            (.desiredRetention, .double(1)),
            (.longestIntervalInDays, .int(0)),
            (.longestIntervalInDays, .int(36_501)),
            (.fsrsParameters, .string("[0.212,1.2931,2.3065]")),
            (.fsrsParameters, .string("{}")),
        ])
    func aRecordWhoseSchedulingSettingBreaksItsRuleWaits(field: SyncedField, value: ICloudValue) throws {
        let kept = try customProgressSettings()
        try mac.engine.moveInProgressSettings { kept }
        time.advance(by: minutes(1))

        let received = try mac.engine.writeWithoutRecording { db in
            try receive(try recordOfFichasSettings(changing: field, to: value, at: time.now), in: db)
        }

        #expect(received == .waits)
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
/// of them, as a device that never changed them sends it from a version of
/// Ficha before the scheduler's settings, which it lacks.
private func recordOfFichasSettingsWithNoTimes() throws -> ICloudRecord {
    let fichas = ReviewSettings.defaults.progress
    return ICloudRecord(
        id: SyncedRow.progressSettings.recordID, type: SyncedRow.RecordType.progressSettings.rawValue,
        fields: [
            SyncedField.ladder.rawValue: try ladderValue(fichas.ladder),
            SyncedField.newCardsPerDay.rawValue: .int(Int64(fichas.newCardsPerDay)),
            SyncedField.forgottenOftenAfter.rawValue: fichas.forgottenOftenAfter.map { .int(Int64($0)) },
        ],
        systemFields: nil)
}

/// That record, but holding `value` for `field`, which changed at `time`.
private func recordOfFichasSettings(changing field: SyncedField, to value: ICloudValue, at time: Date) throws
    -> ICloudRecord
{
    let record = try recordOfFichasSettingsWithNoTimes()
    var fields = record.fields
    fields[field.rawValue] = value
    fields[field.timeKey] = .int(time.wholeMilliseconds)
    return ICloudRecord(id: record.id, type: record.type, fields: fields, systemFields: nil)
}

/// The value of `ladder` in the settings' record: each step's wait in whole
/// seconds, from the first step up, as a JSON array.
private func ladderValue(_ ladder: Ladder) throws -> ICloudValue {
    .string(String(decoding: try JSONEncoder().encode(ladder.waits.map { $0.components.seconds }), as: UTF8.self))
}

extension ProgressSettings {
    /// These settings with `scheduler` in place of theirs.
    fileprivate func with(scheduler: Scheduler) -> ProgressSettings {
        var settings = self
        settings.scheduler = scheduler
        return settings
    }

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

extension Scheduler {
    /// These settings with those given in place of theirs, which must keep
    /// them valid.
    fileprivate func with(
        learningSteps: [Duration]? = nil, relearningSteps: [Duration]? = nil, desiredRetention: Double? = nil,
        longestIntervalInDays: Int? = nil, parameters: [Float]? = nil
    ) throws -> Scheduler {
        try #require(
            Scheduler(
                learningSteps: learningSteps ?? self.learningSteps,
                relearningSteps: relearningSteps ?? self.relearningSteps,
                desiredRetention: desiredRetention ?? self.desiredRetention,
                longestIntervalInDays: longestIntervalInDays ?? self.longestIntervalInDays,
                parameters: parameters ?? self.parameters))
    }
}
