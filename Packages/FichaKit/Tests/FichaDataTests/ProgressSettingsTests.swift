import FichaCore
import Foundation
import GRDB
import Testing

@testable import FichaData

/// Tests on the settings that decide a card's progress in the database: the
/// ladder, the new cards a day and the forgotten-often count, which the app
/// kept in its preferences before they synced (#315).
final class ProgressSettingsTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    /// A data folder of the test's own, for an app and the CLI to share.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaProgressSettingsTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("the settings that decide progress start as Ficha's, and read back as saved, by any engine on the database")
    func theSettingsReadBackFromTheDatabase() throws {
        let app = try Engine(location: .folder(folder), time: time)
        #expect(try app.progressSettings() == ReviewSettings.defaults.progress)

        try app.saveProgressSettings(try customProgressSettings(), changedFrom: ReviewSettings.defaults.progress)

        let cli = try Engine(location: .folder(folder), time: time)
        #expect(try cli.progressSettings() == customProgressSettings())
        #expect(try Engine(location: .folder(folder), time: time).progressSettings() == customProgressSettings())
    }

    // As spec #404 sets them: Ficha's steps, and Anki's desired retention,
    // longest interval and FSRS-6's parameters, which none stands for, as
    // Anki keeps them until Optimize.
    @Test(
        "the scheduling settings start with learning steps of 1 hour and 4 hours, a relearning step of 1 hour, 90%, 36,500 days and FSRS-6's default parameters"
    )
    func theSchedulingSettingsStartAsTheSpecSays() throws {
        let engine = try Engine(location: .folder(folder), time: time)

        let scheduler = try engine.progressSettings().scheduler

        #expect(scheduler.learningSteps == [.seconds(hours(1)), .seconds(hours(4))])
        #expect(scheduler.relearningSteps == [.seconds(hours(1))])
        #expect(scheduler.desiredRetention == 0.9)
        #expect(scheduler.longestIntervalInDays == 36_500)
        #expect(scheduler.parameters.isEmpty)
    }

    // Only the app can read its preferences: the CLI, which may run the
    // migration first, leaves them for the app to move in. The app moves them
    // in each time it opens the database, which they're in after the first.
    @Test(
        "the update moves in the settings the app's preferences kept, and keeps them, whichever of the app or the CLI opens the database first",
        arguments: [Opener.app, .cli])
    func theUpdateMovesTheSettingsIn(first: Opener) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeProgressSettings(at: folder.appending(path: "Ficha.sqlite"))
        if first == .cli {
            let cli = try Engine(location: .folder(folder), time: time)
            try cli.newCapture("serendipia")
        }

        let kept = try customProgressSettings()
        let app = try Engine(location: .folder(folder), time: time)
        try app.moveInProgressSettings { kept }

        let cli = try Engine(location: .folder(folder), time: time)
        #expect(try cli.progressSettings() == kept)
        var changed = kept
        changed.newCardsPerDay = 3
        try app.saveProgressSettings(changed, changedFrom: kept)
        try Engine(location: .folder(folder), time: time).moveInProgressSettings { kept }
        #expect(try cli.progressSettings() == changed)
    }

    // #309 brings the app's preferences into the sandboxed app's, which may
    // first open the database before they're in, holding Ficha's.
    @Test(
        "preferences that kept Ficha's settings move in nothing, so those kept by preferences that come later still move in"
    )
    func fichasSettingsMoveInNothing() throws {
        let app = try Engine(location: .folder(folder), time: time)
        try app.moveInProgressSettings { ReviewSettings.defaults.progress }

        let kept = try customProgressSettings()
        try app.moveInProgressSettings { kept }

        #expect(try app.progressSettings() == kept)
    }

    // A copy from before the update holds no settings that decide progress:
    // the app moves in again those its preferences kept, as it does whenever
    // it hears the database changed, rather than leave Ficha's.
    @Test("a restored copy from before the update takes the settings the app's preferences kept")
    func aCopyFromBeforeTheUpdateTakesTheKeptSettings() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeProgressSettings(at: folder.appending(path: "Ficha.sqlite"))
        let kept = try customProgressSettings()
        let app = try Engine(location: .folder(folder), time: time)
        let beforeUpdate = try #require(try app.copies().first { $0.kind == .beforeUpdate })
        try app.moveInProgressSettings { kept }
        var changed = kept
        changed.forgottenOftenAfter = nil
        try app.saveProgressSettings(changed, changedFrom: kept)

        try app.restore(beforeUpdate.name)
        try app.moveInProgressSettings { kept }

        #expect(try app.progressSettings() == kept)
    }

    /// The process that opens the database first after the update.
    enum Opener {
        case app
        case cli
    }
}

/// Saves a database as Ficha left it before the settings that decide progress
/// moved into it, through the schema's migrations up to the one before it.
func saveDatabaseBeforeProgressSettings(at file: URL) throws {
    try Schema.migrator.migrate(
        DatabaseQueue(path: file.path(percentEncoded: false)), upTo: "v22 what this device knows of iCloud")
}

/// Settings that decide progress, made up, none of them Ficha's: a ladder of
/// three steps, 10 minutes, 6 hours and 3 days; the scheduler's
/// `customScheduler()`; 12 new cards a day; and the offer to flag a card
/// forgotten often after 4 reviews rated again.
func customProgressSettings() throws -> ProgressSettings {
    ProgressSettings(
        ladder: try #require(Ladder(waits: [.seconds(minutes(10)), .seconds(hours(6)), .seconds(days(3))])),
        scheduler: try customScheduler(), newCardsPerDay: 12, forgottenOftenAfter: 4)
}

/// Scheduling settings made up, none of them Ficha's: learning steps of 10
/// minutes, 30 minutes and 3 hours, no relearning step, a desired retention
/// of 85%, a longest interval of a year, and FSRS parameters of the user's
/// own, as Optimize would fit them, none of which a float holds exactly in
/// decimal.
func customScheduler() throws -> Scheduler {
    try #require(
        Scheduler(
            learningSteps: [.seconds(minutes(10)), .seconds(minutes(30)), .seconds(hours(3))], relearningSteps: [],
            desiredRetention: 0.85, longestIntervalInDays: 365, parameters: customParameters))
}

/// FSRS parameters of the user's own, 21 as FSRS-6 has.
let customParameters: [Float] = [
    0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234, 1.616, 0.1544, 1.0824, 1.9813, 0.0953, 0.2975,
    2.2042, 0.2407, 2.9466, 0.5034, 0.6567, 0.1, 0.1542,
]
