import FichaCore
import Foundation
import GRDB
import Testing

// For the schema's migrations, which save databases as older versions of
// Ficha left them.
@testable import FichaData

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
        try engine.newCapture("serendipia")
        try engine.newCapture("¿Por qué el cielo es azul?", source: "Una charla")

        let reopened = try Engine(location: .folder(folder), time: time)

        #expect(try reopened.progress(.defaults).inInbox == 2)
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

        #expect(try engine.inbox().captures.map(\.text) == ["serendipia"])
        let copyPath = path(of: "Ficha before v2 cards.sqlite")
        try #require(FileManager.default.fileExists(atPath: copyPath))
        let (captures, hasCards) = try DatabaseQueue(path: copyPath).read { db in
            (try String.fetchAll(db, sql: "SELECT text FROM capture"), try db.tableExists("card"))
        }
        #expect(captures == ["serendipia"])
        #expect(!hasCards)
    }

    // The review log's table is made again for answers from card
    // notifications, which have no response time.
    @Test("a database from before card notifications migrates, and its review log keeps every entry as it was")
    func reviewLogKeepsItsEntriesThroughTheMigration() throws {
        try saveDatabaseBeforeCardNotifications()

        let engine = try Engine(location: .folder(folder), time: time)

        #expect(
            try engine.reviewLog() == [
                ReviewLogEntry(
                    cardID: 1, kind: .firstView, answeredAt: time.now, responseTime: .milliseconds(8_250),
                    trigger: .reviewNow),
                ReviewLogEntry(
                    cardID: 1, kind: .review(.hard), answeredAt: time.now + hours(1),
                    responseTime: .milliseconds(2_500), trigger: .appearance),
                ReviewLogEntry(
                    cardID: 1, kind: .review(.good), answeredAt: time.now + hours(2), responseTime: .seconds(4),
                    trigger: .reviewNow, isAhead: true),
            ])
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

        let capture = try app.newCapture("serendipia")
        #expect(try cli.inbox().captures.map(\.text) == ["serendipia"])

        try cli.approve(
            capture.id, into: [card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad.")])
        #expect(try app.progress(.defaults).inInbox == 0)
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

        try cli.newCapture("serendipia")

        #expect(await changes.next() != nil)
        #expect(try app.progress(.defaults).inInbox == 1)
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

    /// Saves a database as Ficha left it before card notifications, through
    /// the schema's migrations up to the one before them, with a card that
    /// has a first view, a review from an appearance and a review ahead.
    private func saveDatabaseBeforeCardNotifications() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let database = try DatabasePool(path: path(of: "Ficha.sqlite"))
        try Schema.migrator.migrate(database, upTo: "v8 held-back appearances")
        let now = time.now
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO capture (id, text, createdAt, refinedAt) VALUES (1, 'serendipia', ?, ?)",
                arguments: [now, now])
            try db.execute(
                sql: """
                    INSERT INTO card (id, type, front, back, tags, createdAt, captureId)
                    VALUES (1, 'word', 'serendipia', 'Un hallazgo valioso por casualidad.', '[]', ?, 1)
                    """,
                arguments: [now])
            try db.execute(
                sql: """
                    INSERT INTO reviewLog (cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
                    VALUES (1, 'firstView', NULL, ?, 8.25, 'reviewNow', 0),
                        (1, 'review', 'hard', ?, 2.5, 'appearance', 0),
                        (1, 'review', 'good', ?, 4, 'reviewNow', 1)
                    """,
                arguments: [now, now + hours(1), now + hours(2)])
        }
        try database.close()
    }
}
