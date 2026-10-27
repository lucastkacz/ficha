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

    @Test("before migrating a database from an older version, the engine saves a copy before an update in Backups")
    func olderDatabaseIsCopiedBeforeMigrating() throws {
        try saveFirstVersionDatabase(capturing: "serendipia")

        let engine = try Engine(location: .folder(folder), time: time)

        #expect(try engine.inbox().captures.map(\.text) == ["serendipia"])
        let copy = try #require(try engine.copies().first)
        #expect(try engine.copies().map(\.kind) == [.beforeUpdate])
        #expect(copy.savedAt == time.now)
        let backups = try #require(engine.backupsFolder)
        let (captures, hasCards) = try DatabaseQueue(
            path: backups.appending(path: copy.name).path(percentEncoded: false)
        ).read { db in
            (try String.fetchAll(db, sql: "SELECT text FROM capture"), try db.tableExists("card"))
        }
        #expect(captures == ["serendipia"])
        #expect(!hasCards)
    }

    // Before backups, the copy before a migration was saved next to the
    // database, named after the migration.
    @Test("the copies before an update that older versions left next to the database move into Backups")
    func oldCopiesBeforeAnUpdateMoveIntoBackups() throws {
        try saveFirstVersionDatabase(capturing: "serendipia")
        let oldCopy = folder.appending(path: "Ficha before v2 cards.sqlite")
        try FileManager.default.copyItem(at: folder.appending(path: "Ficha.sqlite"), to: oldCopy)
        let savedAt = time.now - days(30)
        try FileManager.default.setAttributes(
            [.modificationDate: savedAt], ofItemAtPath: oldCopy.path(percentEncoded: false))

        let engine = try Engine(location: .folder(folder), time: time)

        #expect(!FileManager.default.fileExists(atPath: oldCopy.path(percentEncoded: false)))
        let moved = try #require(try engine.copies().last)
        #expect(moved.kind == .beforeUpdate)
        #expect(moved.savedAt == savedAt)
        #expect(try engine.copies().count == 2)
    }

    // The review log's table is made again for answers from card
    // notifications, which have no response time.
    @Test("a database from before card notifications migrates, and its review log keeps every entry as it was")
    func reviewLogKeepsItsEntriesThroughTheMigration() throws {
        try saveDatabaseBeforeCardNotifications()

        let engine = try Engine(location: .folder(folder), time: time)

        #expect(
            try engine.reviewLog().map(\.withoutIDs) == [
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

    @Test("a database from before tags of their own migrates with every card where it stood, and no tag set aside")
    func cardsKeepTheirStandingThroughTheTagMigration() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeTags(at: folder.appending(path: "Ficha.sqlite"), at: time.now)

        let engine = try Engine(location: .folder(folder), time: time)

        #expect(
            try engine.cards().map(\.standing) == [
                .inReviews, .inInbox(Flag(note: "Falta un ejemplo", flaggedAt: time.now)),
                .buried(at: time.now, flag: nil),
            ])
        #expect(
            try engine.standing(of: 1, on: ReviewSettings.defaults.ladder)
                == .onLadder(step: 0, due: time.now + hours(1)))
        #expect(try engine.sidebarTags() == [CardTag(name: "filosofía"), CardTag(name: "lenguaje")])
    }

    // The card table is made again for cards without a type or a capture.
    @Test(
        "a database from before cards without a type or a capture migrates with every card's type, capture, step and review log as they were"
    )
    func cardsKeepEverythingThroughTheMigrationToOptionalTypes() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeOptionalTypes(at: folder.appending(path: "Ficha.sqlite"), at: time.now)

        let engine = try Engine(location: .folder(folder), time: time)

        try expectEveryCardAsItWasBeforeOptionalTypes(in: engine, at: time.now)
        // The id of the card deleted before isn't given again.
        #expect(try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia.")).id == 5)
    }

    // The review log's table is made again for placements, which have no
    // trigger.
    @Test("a database from before placements migrates with every card's step, due time and review log as they were")
    func cardsKeepTheirStepsThroughTheMigrationToPlacements() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforePlacements(at: folder.appending(path: "Ficha.sqlite"), at: time.now)
        let ladder = ReviewSettings.defaults.ladder

        let engine = try Engine(location: .folder(folder), time: time)

        // serendipia: its first view, good an hour later, then a review ahead
        // that doesn't count: the second step, four hours from the good.
        #expect(try engine.standing(of: 1, on: ladder) == .onLadder(step: 1, due: time.now + hours(5)))
        // ubuntu: its first view, from a card notification, then again.
        #expect(try engine.standing(of: 2, on: ladder) == .onLadder(step: 0, due: time.now + hours(3)))
        #expect(try engine.standing(of: 3, on: ladder) == .new)
        #expect(
            try engine.reviewLog().map(\.withoutIDs) == [
                ReviewLogEntry(
                    cardID: 1, kind: .firstView, answeredAt: time.now, responseTime: .milliseconds(8_250),
                    trigger: .reviewNow),
                ReviewLogEntry(
                    cardID: 2, kind: .firstView, answeredAt: time.now, responseTime: nil, trigger: .appearance),
                ReviewLogEntry(
                    cardID: 1, kind: .review(.good), answeredAt: time.now + hours(1), responseTime: .seconds(3),
                    trigger: .appearance),
                ReviewLogEntry(
                    cardID: 2, kind: .review(.again), answeredAt: time.now + hours(2), responseTime: .seconds(5),
                    trigger: .reviewNow),
                ReviewLogEntry(
                    cardID: 1, kind: .review(.good), answeredAt: time.now + hours(3), responseTime: .seconds(2),
                    trigger: .reviewNow, isAhead: true),
            ])
    }

    @Test(
        "a database from before Both ways migrates with every card going one way, and its step, due time and review log as they were"
    )
    func aDatabaseFromBeforeBothWaysMigratesWithEveryCardGoingOneWay() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeBothWays(at: folder.appending(path: "Ficha.sqlite"), at: time.now)
        let ladder = ReviewSettings.defaults.ladder

        let engine = try Engine(location: .folder(folder), time: time)

        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["serendipia", "ubuntu"])
        #expect(cards.map(\.bothWays) == [false, false])
        // serendipia: its first view, then good an hour later: the second
        // step, four hours from the good.
        #expect(try engine.standing(of: 1, on: ladder) == .onLadder(step: 1, due: time.now + hours(5)))
        #expect(try engine.standing(of: 2, on: ladder) == .new)
        #expect(
            try engine.reviewLog().map(\.withoutIDs) == [
                ReviewLogEntry(
                    cardID: 1, kind: .firstView, answeredAt: time.now, responseTime: .milliseconds(8_250),
                    trigger: .reviewNow),
                ReviewLogEntry(
                    cardID: 1, kind: .review(.good), answeredAt: time.now + hours(1), responseTime: .seconds(3),
                    trigger: .appearance),
            ])
    }

    @Test(
        "a database from before each answer's way migrates with every entry front first, and a card that goes both ways ready to start back first"
    )
    func aDatabaseFromBeforeWaysMigratesWithEveryEntryFrontFirst() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeWays(at: folder.appending(path: "Ficha.sqlite"), at: time.now)
        let ladder = ReviewSettings.defaults.ladder

        let engine = try Engine(location: .folder(folder), time: time)

        #expect(try engine.reviewLog().map(\.way) == [.frontFirst, .frontFirst])
        #expect(try engine.standing(of: 1, on: ladder) == .onLadder(step: 1, due: time.now + hours(5)))
        #expect(try engine.standing(of: 1, way: .backFirst, on: ladder) == .new)
        #expect(try engine.reviewNow(.defaults).map(\.way) == [.backFirst])
    }

    // The card, capture and review log tables are made again for the IDs'
    // defaults.
    @Test(
        "a database from before IDs unique across devices migrates with every row as it was, each with an ID of its own waiting to be sent"
    )
    func aDatabaseFromBeforeIDsMigratesWithAnIDForEveryRow() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeIDs(at: folder.appending(path: "Ficha.sqlite"), at: time.now)

        let engine = try Engine(location: .folder(folder), time: time)

        let waiting = try engine.changesToSend()
        try expectEveryRowWithAnIDAsBeforeIDs(in: engine, at: time.now)
        #expect(
            waiting.map(\.row.recordType) == [
                .card, .card, .capture, .capture, .capture, .reviewLogEntry, .reviewLogEntry, .reviewLogEntry,
                .reviewLogEntry, .tag,
            ])
        #expect(waiting.allSatisfy { $0.kind == .saved && $0.fieldTimes.isEmpty })
        #expect(Set(waiting.map(\.row)).count == waiting.count)
        #expect(
            waiting.filter { $0.row.recordType == .reviewLogEntry }.map(\.row)
                == (try engine.reviewLog().compactMap(\.uuid).map(SyncedRow.reviewLogEntry)))
        #expect(waiting.last?.row == .tag("lenguaje"))
        #expect(try engine.recorded { try engine.unbury(2) }.map(\.row) == [waiting[1].row])
    }

    // Ficha opens its database every time it starts, and the CLI on every
    // command: copying it each time would fill the data folder.
    @Test("a new database, or one already up to date, isn't copied")
    func newOrUpToDateDatabaseIsNotCopied() throws {
        _ = try Engine(location: .folder(folder), time: time)
        let engine = try Engine(location: .folder(folder), time: time)

        #expect(try engine.copies().isEmpty)
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

    /// Saves a database as the first version of Ficha left it, with one
    /// capture, in the data folder.
    private func saveFirstVersionDatabase(capturing text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FichaDataTests.saveFirstVersionDatabase(
            at: folder.appending(path: "Ficha.sqlite"), capturing: text, at: time.now)
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

/// Saves a database at `file` as Ficha left it before tags had anything of
/// their own, through the schema's migrations up to the one before them,
/// with three cards tagged "filosofía" and "lenguaje", approved at `time`:
/// one in Lucas's reviews, met then, one flagged then, and one buried then.
func saveDatabaseBeforeTags(at file: URL, at time: Date) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v10 planned appearances")
    try database.write { db in
        try db.execute(
            sql: "INSERT INTO capture (id, text, createdAt, refinedAt) VALUES (1, 'ubuntu', ?, ?)",
            arguments: [time, time])
        try db.execute(
            sql: """
                INSERT INTO card (id, type, front, back, tags, createdAt, captureId, flagNote, flaggedAt, buriedAt)
                VALUES (1, 'word', 'ubuntu', 'Humanidad.', '["filosofía"]', ?, 1, NULL, NULL, NULL),
                    (2, 'word', 'eudaimonía', 'Vida plena.', '["filosofía", "lenguaje"]', ?, 1,
                        'Falta un ejemplo', ?, NULL),
                    (3, 'word', 'ataraxia', 'Serenidad.', '["filosofía"]', ?, 1, NULL, NULL, ?)
                """,
            arguments: [time, time, time, time, time])
        try db.execute(
            sql: """
                INSERT INTO reviewLog (cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
                VALUES (1, 'firstView', NULL, ?, 8.25, 'reviewNow', 0)
                """,
            arguments: [time])
    }
    try database.close()
}

/// Saves a database at `file` as Ficha left it before cards without a type
/// or a capture, through the schema's migrations up to the one before them,
/// with everything made at `time`: two cards approved from "serendipia", one
/// on the second step and one flagged, an expansion of the first, a buried
/// card approved from "ubuntu", and a fourth card, deleted.
func saveDatabaseBeforeOptionalTypes(at file: URL, at time: Date) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v11 tags")
    try database.write { db in
        try db.execute(
            sql: """
                INSERT INTO capture (id, text, createdAt, refinedAt) VALUES (1, 'serendipia', ?, ?),
                    (2, 'ubuntu', ?, ?)
                """,
            arguments: [time, time, time, time])
        try db.execute(
            sql: """
                INSERT INTO card
                    (id, type, front, back, tags, source, createdAt, captureId, flagNote, flaggedAt, buriedAt)
                VALUES (1, 'word', 'serendipia', 'Un hallazgo por casualidad.', '["lenguaje"]',
                        'Un ensayo de Borges', ?, 1, NULL, NULL, NULL),
                    (2, 'question', '¿De dónde viene «serendipia»?', 'De un cuento persa.',
                        '["lenguaje", "historia"]', NULL, ?, 1, 'Falta un ejemplo', ?, NULL),
                    (3, 'concept', 'ubuntu', 'Soy porque somos.', '["filosofía"]', NULL, ?, 2, NULL, NULL, ?),
                    (4, 'quote', 'Caminante, no hay camino', 'Antonio Machado.', '[]', NULL, ?, 2, NULL, NULL, NULL)
                """,
            arguments: [time, time, time, time, time, time])
        try db.execute(sql: "DELETE FROM card WHERE id = 4")
        try db.execute(
            sql: "INSERT INTO capture (id, text, createdAt, expandsCardId) VALUES (3, 'Serendipia', ?, 1)",
            arguments: [time])
        try db.execute(
            sql: """
                INSERT INTO reviewLog (cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
                VALUES (1, 'firstView', NULL, ?, 8.25, 'reviewNow', 0),
                    (1, 'review', 'good', ?, NULL, 'appearance', 0),
                    (3, 'firstView', NULL, ?, 6, 'appearance', 0)
                """,
            arguments: [time, time + hours(1), time])
    }
    try database.close()
}

/// Saves a database at `file` as Ficha left it before placements, through
/// the schema's migrations up to the one before them, with three cards made
/// at `time`: serendipia, met then, good an hour later and good again ahead
/// of time two hours after that; ubuntu, met then from a card notification,
/// and again two hours later; and petricor, new.
func saveDatabaseBeforePlacements(at file: URL, at time: Date) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v13 images on cards")
    try database.write { db in
        try db.execute(
            sql: """
                INSERT INTO card (id, type, front, back, tags, createdAt)
                VALUES (1, 'word', 'serendipia', 'Un hallazgo por casualidad.', '[]', ?),
                    (2, NULL, 'ubuntu', 'Soy porque somos.', '[]', ?),
                    (3, 'word', 'petricor', 'El olor de la lluvia.', '[]', ?)
                """,
            arguments: [time, time, time])
        try db.execute(
            sql: """
                INSERT INTO reviewLog (cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
                VALUES (1, 'firstView', NULL, ?, 8.25, 'reviewNow', 0),
                    (2, 'firstView', NULL, ?, NULL, 'appearance', 0),
                    (1, 'review', 'good', ?, 3, 'appearance', 0),
                    (2, 'review', 'again', ?, 5, 'reviewNow', 0),
                    (1, 'review', 'good', ?, 2, 'reviewNow', 1)
                """,
            arguments: [time, time, time + hours(1), time + hours(2), time + hours(3)])
    }
    try database.close()
}

/// Saves a database at `file` as Ficha left it before it kept when a card's
/// front or back last changed, through the schema's migrations up to the one
/// before it, with two cards approved at `time`: serendipia and ubuntu.
func saveDatabaseBeforeEditedTimes(at file: URL, at time: Date) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v14 placements in the review log")
    try database.write { db in
        try db.execute(
            sql: """
                INSERT INTO card (id, type, front, back, tags, createdAt)
                VALUES (1, 'word', 'serendipia', 'Un hallazgo.', '[]', ?),
                    (2, 'concept', 'ubuntu', 'Soy porque somos.', '[]', ?)
                """,
            arguments: [time, time])
    }
    try database.close()
}

/// Saves a database at `file` as Ficha left it before sounds on cards,
/// through the schema's migrations up to the one before them, with two cards
/// approved at `time`: hornero, with `image` on its front, and ubuntu.
func saveDatabaseBeforeSounds(at file: URL, at time: Date, image: ImageName) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v16 follow-ups")
    try database.write { db in
        try db.execute(
            sql: """
                INSERT INTO card (id, type, front, back, frontImage, tags, createdAt)
                VALUES (1, 'word', 'hornero', 'Un pájaro.', ?, '[]', ?),
                    (2, 'concept', 'ubuntu', 'Soy porque somos.', NULL, '[]', ?)
                """,
            arguments: [image.rawValue, time, time])
    }
    try database.close()
}

/// Saves a database at `file` as Ficha left it before a card could go both
/// ways, through the schema's migrations up to the one before it, with two
/// cards approved at `time`: serendipia, met then and good an hour later,
/// and ubuntu, new.
func saveDatabaseBeforeBothWays(at file: URL, at time: Date) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v17 sounds on cards")
    try database.write { db in
        try db.execute(
            sql: """
                INSERT INTO card (id, type, front, back, tags, createdAt)
                VALUES (1, 'word', 'serendipia', 'Un hallazgo por casualidad.', '[]', ?),
                    (2, 'concept', 'ubuntu', 'Soy porque somos.', '[]', ?)
                """,
            arguments: [time, time])
        try db.execute(
            sql: """
                INSERT INTO reviewLog (cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
                VALUES (1, 'firstView', NULL, ?, 8.25, 'reviewNow', 0),
                    (1, 'review', 'good', ?, 3, 'appearance', 0)
                """,
            arguments: [time, time + hours(1)])
    }
    try database.close()
}

/// Saves a database at `file` as Ficha left it before the review log said
/// which way each answer went, through the schema's migrations up to the one
/// before it, with a card approved at `time` that goes both ways:
/// serendipia, met then and good an hour later.
func saveDatabaseBeforeWays(at file: URL, at time: Date) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v18 cards that go both ways")
    try database.write { db in
        try db.execute(
            sql: """
                INSERT INTO card (id, type, front, back, tags, createdAt, bothWays)
                VALUES (1, 'word', 'serendipia', 'Un hallazgo por casualidad.', '[]', ?, 1)
                """,
            arguments: [time])
        try db.execute(
            sql: """
                INSERT INTO reviewLog (cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
                VALUES (1, 'firstView', NULL, ?, 8.25, 'reviewNow', 0),
                    (1, 'review', 'good', ?, 3, 'appearance', 0)
                """,
            arguments: [time, time + hours(1)])
    }
    try database.close()
}

/// The names of the images and sounds on ubuntu, in `saveDatabaseBeforeIDs`,
/// which only its row holds.
private let ubuntuFiles = (
    frontImage: String(repeating: "a", count: 64) + ".png", backImage: String(repeating: "b", count: 64) + ".jpg",
    frontSound: String(repeating: "c", count: 64) + ".m4a", backSound: String(repeating: "d", count: 64) + ".m4a"
)

/// Saves a database at `file` as Ficha left it before rows had IDs unique
/// across devices, through the schema's migrations up to the one before them,
/// with everything made at `time`, and every column the migration copies
/// filled on some row: serendipia, approved from its capture, tagged
/// "lenguaje", which is blue, met then, good an hour later and hard ahead an
/// hour after that; ubuntu, tagged "filosofía", with a source, images and
/// sounds, edited, flagged and buried, going both ways and placed back first
/// by an import;
/// ojalá, a capture in the inbox that follows serendipia up, and another,
/// with a note and a source, that expands ubuntu; and petricor, with its
/// capture, the last one, and its first view, deleted.
func saveDatabaseBeforeIDs(at file: URL, at time: Date) throws {
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try Schema.migrator.migrate(database, upTo: "v19 the way each answer went")
    try database.write { db in
        try db.execute(
            sql: """
                INSERT INTO capture (id, text, createdAt, refinedAt)
                VALUES (1, 'serendipia', ?, ?), (4, 'petricor', ?, ?)
                """,
            arguments: [time, time, time, time])
        try db.execute(
            sql: """
                INSERT INTO card (id, type, front, back, tags, createdAt, captureId)
                VALUES (1, 'word', 'serendipia', 'Un hallazgo por casualidad.', '["lenguaje"]', ?, 1),
                    (3, 'word', 'petricor', 'El olor de la lluvia.', '[]', ?, 4)
                """,
            arguments: [time, time])
        try db.execute(
            sql: """
                INSERT INTO card (
                    id, type, front, back, tags, source, createdAt, flagNote, flaggedAt, buriedAt, frontImage,
                    backImage, editedAt, frontSound, backSound, bothWays)
                VALUES (
                    2, 'concept', 'ubuntu', 'Soy porque somos.', '["filosofía"]', 'Desmond Tutu', ?,
                    'Falta un ejemplo', ?, ?, ?, ?, ?, ?, ?, 1)
                """,
            arguments: [
                time, time + hours(4), time + hours(5), ubuntuFiles.frontImage, ubuntuFiles.backImage,
                time + hours(3), ubuntuFiles.frontSound, ubuntuFiles.backSound,
            ])
        try db.execute(
            sql: """
                INSERT INTO capture (id, text, note, source, createdAt, expandsCardId, followsUpCardId)
                VALUES (2, 'ojalá', NULL, NULL, ?, NULL, 1),
                    (3, 'ubuntu, en zulú', 'Del proverbio', 'Una charla', ?, 2, NULL)
                """,
            arguments: [time, time])
        try db.execute(
            sql: """
                INSERT INTO reviewLog
                    (cardId, kind, rating, step, due, answeredAt, responseTime, trigger, isAhead, way)
                VALUES (1, 'firstView', NULL, NULL, NULL, ?, 8.25, 'reviewNow', 0, 'frontFirst'),
                    (1, 'review', 'good', NULL, NULL, ?, 3, 'appearance', 0, 'frontFirst'),
                    (1, 'review', 'hard', NULL, NULL, ?, NULL, 'appearance', 1, 'frontFirst'),
                    (2, 'placement', NULL, 2, ?, ?, NULL, NULL, 0, 'backFirst'),
                    (3, 'firstView', NULL, NULL, NULL, ?, 6, 'reviewNow', 0, 'frontFirst')
                """,
            arguments: [time, time + hours(1), time + hours(2), time + days(4), time, time])
        try db.execute(sql: "INSERT INTO tag (name, color) VALUES ('lenguaje', 'blue')")
        try db.execute(sql: "DELETE FROM reviewLog WHERE cardId = 3")
        try db.execute(sql: "DELETE FROM card WHERE id = 3")
        try db.execute(sql: "DELETE FROM capture WHERE id = 4")
    }
    try database.close()
}

/// Checks that `engine` has every row of `saveDatabaseBeforeIDs`, saved at
/// `time`, as it was, each entry of the review log with an ID of its own and
/// answering none, and gives a new card or capture an id after the deleted
/// one's. A review log entry's id is never seen, so a deleted one's doesn't
/// matter.
func expectEveryRowWithAnIDAsBeforeIDs(in engine: Engine, at time: Date) throws {
    #expect(
        try engine.cards() == [
            Card(
                id: 1, type: .word, front: "serendipia", back: "Un hallazgo por casualidad.", frontImage: nil,
                backImage: nil, frontSound: nil, backSound: nil, tags: ["lenguaje"], source: nil, createdAt: time,
                editedAt: nil, captureID: 1, flag: nil, buriedAt: nil, setAsideBy: nil, bothWays: false),
            Card(
                id: 2, type: .concept, front: "ubuntu", back: "Soy porque somos.",
                frontImage: ImageName(rawValue: ubuntuFiles.frontImage),
                backImage: ImageName(rawValue: ubuntuFiles.backImage),
                frontSound: SoundName(rawValue: ubuntuFiles.frontSound),
                backSound: SoundName(rawValue: ubuntuFiles.backSound), tags: ["filosofía"], source: "Desmond Tutu",
                createdAt: time, editedAt: time + hours(3), captureID: nil,
                flag: Flag(note: "Falta un ejemplo", flaggedAt: time + hours(4)), buriedAt: time + hours(5),
                setAsideBy: nil, bothWays: true),
        ])
    #expect(try engine.sidebarTags() == [CardTag(name: "lenguaje", color: .blue)])
    let inbox = try engine.inbox()
    #expect(inbox.captures.isEmpty)
    #expect(
        inbox.followUps.map(\.capture) == [
            Capture(
                id: 2, text: "ojalá", note: nil, source: nil, createdAt: time, expandsCardID: nil,
                followsUpCardID: 1)
        ])
    #expect(
        inbox.expansions.map(\.capture) == [
            Capture(
                id: 3, text: "ubuntu, en zulú", note: "Del proverbio", source: "Una charla", createdAt: time,
                expandsCardID: 2, followsUpCardID: nil)
        ])
    #expect(
        try engine.reviewLog().map(\.withoutIDs) == [
            ReviewLogEntry(
                cardID: 1, kind: .firstView, answeredAt: time, responseTime: .milliseconds(8_250),
                trigger: .reviewNow),
            ReviewLogEntry(
                cardID: 1, kind: .review(.good), answeredAt: time + hours(1), responseTime: .seconds(3),
                trigger: .appearance),
            ReviewLogEntry(
                cardID: 1, kind: .review(.hard), answeredAt: time + hours(2), responseTime: nil,
                trigger: .appearance, isAhead: true),
            ReviewLogEntry(placing: 2, way: .backFirst, on: Placement(step: 2, due: time + days(4)), at: time),
        ])
    // Each entry has an ID of its own, and no review says which entry it
    // answered, so it answered the one before it.
    let log = try engine.reviewLog()
    #expect(Set(log.compactMap(\.uuid)).count == 4)
    #expect(log.allSatisfy { $0.answeredEntry == nil })
    // The ids of the card and the capture deleted before aren't given again.
    #expect(try engine.create(card(nil, front: "ataraxia", back: "Serenidad.")).id == 4)
    #expect(try engine.newCapture("eudaimonía").id == 5)
}

/// Checks that `engine` has every card of `saveDatabaseBeforeOptionalTypes`
/// as it was saved at `time`: its type, capture, standing, step and review
/// log, and the expansion still attached to its card, which follows none up.
func expectEveryCardAsItWasBeforeOptionalTypes(in engine: Engine, at time: Date) throws {
    let cards = try engine.cards()
    #expect(cards.map(\.id) == [1, 2, 3])
    #expect(cards.map(\.type) == [.word, .question, .concept])
    #expect(cards.map(\.captureID) == [1, 1, 2])
    #expect(cards.map(\.front) == ["serendipia", "¿De dónde viene «serendipia»?", "ubuntu"])
    #expect(cards.map(\.back) == ["Un hallazgo por casualidad.", "De un cuento persa.", "Soy porque somos."])
    #expect(cards.map(\.tags) == [["lenguaje"], ["lenguaje", "historia"], ["filosofía"]])
    #expect(cards.map(\.source) == ["Un ensayo de Borges", nil, nil])
    #expect(cards.map(\.createdAt) == [time, time, time])
    #expect(
        cards.map(\.standing) == [
            .inReviews, .inInbox(Flag(note: "Falta un ejemplo", flaggedAt: time)), .buried(at: time, flag: nil),
        ])
    let ladder = ReviewSettings.defaults.ladder
    // Its first view, then good an hour later: the second step, which waits
    // four hours.
    #expect(try engine.standing(of: 1, on: ladder) == .onLadder(step: 1, due: time + hours(5)))
    #expect(try engine.standing(of: 2, on: ladder) == .new)
    #expect(try engine.standing(of: 3, on: ladder) == .onLadder(step: 0, due: time + hours(1)))
    #expect(
        try engine.reviewLog().map(\.withoutIDs) == [
            ReviewLogEntry(
                cardID: 1, kind: .firstView, answeredAt: time, responseTime: .milliseconds(8_250),
                trigger: .reviewNow),
            ReviewLogEntry(
                cardID: 1, kind: .review(.good), answeredAt: time + hours(1), responseTime: nil,
                trigger: .appearance),
            ReviewLogEntry(
                cardID: 3, kind: .firstView, answeredAt: time, responseTime: .seconds(6), trigger: .appearance),
        ])
    #expect(try engine.inbox().expansions.map(\.card.id) == [1])
    #expect(try engine.inbox().followUps.isEmpty)
}

/// Saves a database at `file` as the first version of Ficha left it, written
/// by hand with that version's only migration and one capture, captured at
/// `time`.
func saveFirstVersionDatabase(at file: URL, capturing text: String, at time: Date) throws {
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
    let database = try DatabasePool(path: file.path(percentEncoded: false))
    try firstVersion.migrate(database)
    try database.write { db in
        try db.execute(sql: "INSERT INTO capture (text, createdAt) VALUES (?, ?)", arguments: [text, time])
    }
    try database.close()
}
