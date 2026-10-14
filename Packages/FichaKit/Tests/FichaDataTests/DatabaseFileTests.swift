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

    @Test("the inbox still counts its captures after the database is opened again")
    func inboxCountSurvivesReopening() throws {
        let engine = try Engine(location: .folder(folder), time: time)
        try engine.capture(text: "serendipia", note: nil, source: nil)
        try engine.capture(text: "¿Por qué el cielo es azul?", note: nil, source: "Una charla")

        let reopened = try Engine(location: .folder(folder), time: time)

        #expect(try reopened.inboxCount() == 2)
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

    @Test("before migrating a database from an older version, the engine saves a copy of it as it was, next to it")
    func olderDatabaseIsCopiedBeforeMigrating() throws {
        try saveFirstVersionDatabase(capturing: "serendipia")

        let engine = try Engine(location: .folder(folder), time: time)

        #expect(try engine.inbox().map(\.text) == ["serendipia"])
        let copyPath = path(of: "Ficha before v2 cards.sqlite")
        try #require(FileManager.default.fileExists(atPath: copyPath))
        let (captures, hasCards) = try DatabaseQueue(path: copyPath).read { db in
            (try String.fetchAll(db, sql: "SELECT text FROM capture"), try db.tableExists("card"))
        }
        #expect(captures == ["serendipia"])
        #expect(!hasCards)
    }

    // Ficha opens its database every time it starts, and the CLI on every
    // command: copying it each time would fill the data folder.
    @Test("a new database, or one already up to date, isn't copied")
    func newOrUpToDateDatabaseIsNotCopied() throws {
        _ = try Engine(location: .folder(folder), time: time)
        _ = try Engine(location: .folder(folder), time: time)

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(files.filter { $0.hasSuffix(".sqlite") } == ["Ficha.sqlite"])
    }

    @Test("two engines on the same database, as the app and the CLI are, each see what the other writes")
    func twoEnginesSeeEachOthersWrites() throws {
        let app = try Engine(location: .folder(folder), time: time)
        let cli = try Engine(location: .folder(folder), time: time)

        let capture = try app.capture(text: "serendipia", note: nil, source: nil)
        #expect(try cli.inbox().map(\.text) == ["serendipia"])

        try cli.approve(
            capture.id, into: [card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad.")])
        #expect(try app.inboxCount() == 0)
        #expect(try app.cards().map(\.front) == ["serendipia"])
    }

    // The menu counts the inbox again whenever the CLI changes it.
    @Test(
        "an engine hears when another engine on the same database changes it",
        .timeLimit(.minutes(1))
    )
    func anEngineHearsTheOthersChanges() async throws {
        let app = try Engine(location: .folder(folder), time: time)
        let cli = try Engine(location: .folder(folder), time: time)
        var changes = app.changes().makeAsyncIterator()

        try cli.capture(text: "serendipia", note: nil, source: nil)

        #expect(await changes.next() != nil)
        #expect(try app.inboxCount() == 1)
    }

    /// The path of a file in the data folder.
    private func path(of file: String) -> String {
        folder.appending(path: file).path(percentEncoded: false)
    }

    /// Saves a database as the first version of Ficha left it, written by hand
    /// with that version's only migration and one capture.
    private func saveFirstVersionDatabase(capturing text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var firstVersion = DatabaseMigrator()
        firstVersion.registerMigration("v1 captures") { db in
            try db.create(table: "capture") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("text", .text).notNull()
                table.column("note", .text)
                table.column("source", .text)
                table.column("createdAt", .datetime).notNull()
            }
        }
        let database = try DatabasePool(path: path(of: "Ficha.sqlite"))
        try firstVersion.migrate(database)
        try database.write { db in
            try db.execute(sql: "INSERT INTO capture (text, createdAt) VALUES (?, ?)", arguments: [text, time.now])
        }
        try database.close()
    }
}
