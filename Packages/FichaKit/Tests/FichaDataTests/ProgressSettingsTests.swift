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
/// three steps, 10 minutes, 6 hours and 3 days, 12 new cards a day, and the
/// offer to flag a card forgotten often after 4 reviews rated again.
func customProgressSettings() throws -> ProgressSettings {
    ProgressSettings(
        ladder: try #require(Ladder(waits: [.seconds(minutes(10)), .seconds(hours(6)), .seconds(days(3))])),
        newCardsPerDay: 12, forgottenOftenAfter: 4)
}
