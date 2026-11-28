import FichaCore
import Foundation
import GRDB
import Testing

@testable import FichaData

/// Tests on the settings that decide a card's progress in the database: the
/// new cards a day and the forgotten-often count, which the app kept in its
/// preferences before they synced (#315), and the scheduler's settings
/// beside them (#404).
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

    // As spec #404 sets them: Ficha's steps, and Anki's longest interval and
    // FSRS-6's parameters, which none stands for, as Anki keeps them until
    // Optimize; and the desired retention of 85% ADR 0034 sets, in place of
    // Anki's 90%.
    @Test(
        "the scheduling settings start with learning steps of 1 hour and 4 hours, a relearning step of 1 hour, 85%, 36,500 days and FSRS-6's default parameters",
        .bug(id: 490))
    func theSchedulingSettingsStartAsTheSpecSays() throws {
        let engine = try Engine(location: .folder(folder), time: time)

        let scheduler = try engine.progressSettings().scheduler

        #expect(scheduler.learningSteps == [.seconds(hours(1)), .seconds(hours(4))])
        #expect(scheduler.relearningSteps == [.seconds(hours(1))])
        #expect(scheduler.desiredRetention == 0.85)
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
            try newCard("serendipia", in: cli)
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

    // A user changed the new cards a day to 3 before Ficha's day, and sync,
    // on, sent it, so the database holds a row of the settings that decide
    // progress, which the hour joins as Ficha's, with nothing to send.
    @Test(
        "a database from before Ficha's day migrates with its settings and the day starting at 4:00, as no change to send, and keeps an hour saved after, which syncs",
        .bug(id: 562))
    func aDatabaseFromBeforeFichasDayStartsItAtFour() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeFichasDay(at: folder.appending(path: "Ficha.sqlite"))

        let app = try Engine(location: .folder(folder), time: time)
        let waitingOnceMigrated = try app.changesToSend()
        let migrated = try app.progressSettings()
        var atSix = migrated
        atSix.dayStartsAtHour = 6
        try app.saveProgressSettings(atSix, changedFrom: migrated)

        var expected = ReviewSettings.defaults.progress
        expected.newCardsPerDay = 3
        #expect(migrated == expected)
        #expect(migrated.dayStartsAtHour == 4)
        #expect(waitingOnceMigrated.isEmpty)
        #expect(try app.changesToSend().map(\.row) == [.progressSettings])
        #expect(try Engine(location: .folder(folder), time: time).progressSettings() == atSix)
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

/// Settings that decide progress, made up, none of them Ficha's: the
/// scheduler's `customScheduler()`; 12 new cards a day; Ficha's day starting
/// at 6:00; and the offer to flag a card forgotten often after 4 lapses.
func customProgressSettings() throws -> ProgressSettings {
    ProgressSettings(scheduler: try customScheduler(), newCardsPerDay: 12, dayStartsAtHour: 6, forgottenOftenAfter: 4)
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

/// Saves a database at `file` as Ficha left it before Ficha's day
/// (ADR 0045), through the schema's migrations up to the one before it, with
/// sync on, as a database with no cards starts, and nothing waiting to be
/// sent, and with the settings that decide progress a user changed to 3 new
/// cards a day: Ficha's otherwise, as Ficha writes the row, the desired
/// retention of a new install among them, 85%, where the column holds the
/// scheduler's 90%.
func saveDatabaseBeforeFichasDay(at file: URL) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v35 a deck's description")
    try database.write { db in
        try db.execute(sql: "UPDATE syncWrite SET recordsChanges = 0")
        try db.execute(
            sql: """
                INSERT INTO progressSettings (id, newCardsPerDay, forgottenOftenAfter, desiredRetention)
                VALUES (1, 3, 8, 0.85)
                """)
        try db.execute(sql: "UPDATE syncWrite SET recordsChanges = 1")
        try db.execute(sql: "DELETE FROM syncPending")
    }
    try database.close()
}
