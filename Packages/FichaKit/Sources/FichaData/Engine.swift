import FichaCore
import Foundation
internal import GRDB
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "engine")

/// Where the engine keeps the database.
public enum DatabaseLocation: Sendable {
    /// A file in this data folder, which is created if it doesn't exist yet.
    case folder(URL)
    /// In memory, gone with the engine: for tests.
    case inMemory
}

/// The engine: the one way the app and the `ficha` CLI read and write Lucas's
/// cards (ADRs 0004 and 0005). It owns the database and its migrations, and
/// writes each change in one transaction. The app and the CLI each open their
/// own engine on the same database, and each hears about the other's changes.
public struct Engine: Sendable {
    private let database: any DatabaseWriter
    private let databaseChanges: DatabaseChanges
    private let time: any TimeSource

    /// Opens the database at `location`, creating it if it doesn't exist yet,
    /// and migrates it to this version's schema. Before migrating a database
    /// that an older version of Ficha left, it saves a copy of it next to it.
    /// A database that a newer version migrated is refused, and left as it was.
    public init(location: DatabaseLocation, time: any TimeSource) throws(EngineError) {
        let (database, databaseChanges) = try reportingStorageErrors {
            () throws -> (any DatabaseWriter, DatabaseChanges) in
            switch location {
            case .folder(let folder):
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appending(path: "Ficha.sqlite").path(percentEncoded: false)
                // The app and the CLI write to the same file, so a write waits
                // for the other process's to end instead of failing, as GRDB's
                // guide to sharing a database says.
                var configuration = Configuration()
                configuration.busyMode = .timeout(5)
                return (try DatabasePool(path: file, configuration: configuration), DatabaseChanges(database: file))
            case .inMemory:
                return (try DatabaseQueue(), DatabaseChanges(database: "in memory \(UUID().uuidString)"))
            }
        }
        if try reportingStorageErrors({ try database.read(Schema.migrator.hasBeenSuperseded) }) {
            logger.error("Refused a database that a newer version of Ficha migrated")
            throw .migratedByNewerVersion
        }
        if case .folder(let folder) = location,
            let migration = try reportingStorageErrors({ try database.read(firstMigrationToApply) })
        {
            try saveCopy(of: database, in: folder, before: migration)
        }
        try reportingStorageErrors { try Schema.migrator.migrate(database) }
        self.database = database
        self.databaseChanges = databaseChanges
        self.time = time
    }

    /// Every change to the database from now on, by this engine or by another
    /// one on the same database, such as the CLI's while the app runs. Changes
    /// that come while one waits to be handled are merged into it.
    public func changes() -> AsyncStream<Void> {
        databaseChanges.stream()
    }

    /// Saves a capture in the inbox, cleaned up as `CaptureContent` says, and
    /// returns it. A capture without text isn't saved.
    @discardableResult
    public func capture(text: String, note: String?, source: String?) throws(EngineError) -> Capture {
        guard let content = CaptureContent(text: text, note: note, source: source) else {
            throw .emptyCapture
        }
        let createdAt = time.now
        return try write { db in
            try db.execute(
                sql: "INSERT INTO capture (text, note, source, createdAt) VALUES (?, ?, ?, ?)",
                arguments: [content.text, content.note, content.source, createdAt]
            )
            return Capture(
                id: db.lastInsertedRowID,
                text: content.text,
                note: content.note,
                source: content.source,
                createdAt: createdAt
            )
        }
    }

    /// The captures waiting in the inbox, oldest first.
    public func inbox() throws(EngineError) -> [Capture] {
        try reportingStorageErrors {
            try database.read { db in
                try capturesInInbox.order(Column("id")).fetchAll(db).map(Capture.init(row:))
            }
        }
    }

    /// How many captures wait in the inbox.
    public func inboxCount() throws(EngineError) -> Int {
        try reportingStorageErrors {
            try database.read { db in
                try capturesInInbox.fetchCount(db)
            }
        }
    }

    /// Approves a capture into one or more cards: saves them as new cards, in
    /// the order given, takes the capture out of the inbox and returns the
    /// cards.
    @discardableResult
    public func approve(_ captureID: Int64, into cards: [CardContent]) throws(EngineError) -> [Card] {
        guard !cards.isEmpty else {
            throw .noCards
        }
        let createdAt = time.now
        return try write { db in
            try takeOutOfInbox(captureID, at: createdAt, in: db)
            for card in cards {
                try db.execute(
                    sql: """
                        INSERT INTO card (type, front, back, tags, source, createdAt, captureId)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        card.type.rawValue, card.front, card.back, try tagsJSON(card.tags), card.source,
                        createdAt, captureID,
                    ]
                )
            }
            return try Row.fetchAll(
                db, sql: "SELECT * FROM card WHERE captureId = ? ORDER BY id", arguments: [captureID]
            )
            .map(Card.init(row:))
        }
    }

    /// Discards a capture: takes it out of the inbox without cards, and
    /// returns it.
    @discardableResult
    public func discard(_ captureID: Int64) throws(EngineError) -> Capture {
        let refinedAt = time.now
        return try write { db in
            try takeOutOfInbox(captureID, at: refinedAt, in: db)
        }
    }

    /// Every card, in the order Lucas approved them.
    public func cards() throws(EngineError) -> [Card] {
        try reportingStorageErrors {
            try database.read { db in
                try Row.fetchAll(db, sql: "SELECT * FROM card ORDER BY id").map(Card.init(row:))
            }
        }
    }

    /// Runs `updates` in one transaction, then tells every engine on the
    /// database that it changed.
    private func write<Value>(_ updates: (Database) throws -> Value) throws(EngineError) -> Value {
        let value = try reportingStorageErrors { try database.write(updates) }
        databaseChanges.post()
        return value
    }
}

/// The first migration this version would apply to a database that an older
/// version left, or nil when the database is new or already up to date.
private func firstMigrationToApply(_ db: Database) throws -> String? {
    let applied = try Schema.migrator.appliedIdentifiers(db)
    guard !applied.isEmpty else {
        return nil
    }
    return Schema.migrator.migrations.first { !applied.contains($0) }
}

/// Saves a copy of the database as it is in its data folder, named after the
/// migration it's about to get, so a bad update can't lose Lucas's cards.
private func saveCopy(of database: any DatabaseWriter, in folder: URL, before migration: String) throws(EngineError) {
    try reportingStorageErrors {
        let copy = try DatabaseQueue(
            path: folder.appending(path: "Ficha before \(migration).sqlite").path(percentEncoded: false))
        try database.backup(to: copy)
    }
    logger.notice("Saved a copy of the database before the migration \(migration, privacy: .public)")
}

/// The captures that wait in the inbox: those not refined yet, into cards or
/// into none.
private var capturesInInbox: QueryInterfaceRequest<Row> {
    Table("capture").filter(Column("refinedAt") == nil)
}

/// Takes a capture out of the inbox, as refined at `time`, and returns it, or
/// throws when it isn't in the inbox.
@discardableResult
private func takeOutOfInbox(_ captureID: Int64, at time: Date, in db: Database) throws -> Capture {
    guard let row = try capturesInInbox.filter(Column("id") == captureID).fetchOne(db) else {
        throw EngineError.captureNotInInbox(captureID)
    }
    try db.execute(sql: "UPDATE capture SET refinedAt = ? WHERE id = ?", arguments: [time, captureID])
    return try Capture(row: row)
}

/// A card's tags as the `card` table keeps them: a JSON array.
private func tagsJSON(_ tags: [String]) throws -> String {
    String(decoding: try JSONEncoder().encode(tags), as: UTF8.self)
}

/// Runs work on the database. The engine's own errors pass through as they
/// are; when SQLite fails, it logs why and throws the engine's error, whose
/// message Lucas can read.
private func reportingStorageErrors<Value>(_ work: () throws -> Value) throws(EngineError) -> Value {
    do {
        return try work()
    } catch let error as EngineError {
        throw error
    } catch {
        logger.error("The database failed: \(String(describing: error))")
        throw .storage
    }
}
