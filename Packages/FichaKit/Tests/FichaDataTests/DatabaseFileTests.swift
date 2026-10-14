import FichaCore
import FichaData
import Foundation
import GRDB
import Testing

/// Tests on a database file in a data folder, the way the app opens it.
final class DatabaseFileTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    /// A data folder of the test's own, which the engine creates when it first opens it.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaDataTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("captures are still in the inbox after the database is opened again")
    func capturesSurviveReopening() throws {
        try Engine(location: .folder(folder), time: time).capture(text: "serendipia", note: nil, source: nil)

        let reopened = try Engine(location: .folder(folder), time: time)

        #expect(try reopened.inbox().map(\.text) == ["serendipia"])
    }

    @Test("a database that a newer version of Ficha migrated is refused")
    func newerDatabaseIsRefused() throws {
        _ = try Engine(location: .folder(folder), time: time)
        // A newer Ficha migrates the database further than this version knows,
        // in the file the engine keeps in the data folder.
        var newerFicha = DatabaseMigrator()
        newerFicha.registerMigration("a migration from a newer Ficha") { _ in }
        try newerFicha.migrate(DatabaseQueue(path: folder.appending(path: "Ficha.sqlite").path(percentEncoded: false)))

        #expect(throws: EngineError.migratedByNewerVersion) {
            try Engine(location: .folder(folder), time: time)
        }
    }
}
