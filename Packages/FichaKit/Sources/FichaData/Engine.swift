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
/// writes each change in one transaction.
public struct Engine: Sendable {
    private let database: any DatabaseWriter
    private let time: any TimeSource

    /// Opens the database at `location`, creating it if it doesn't exist yet,
    /// and migrates it to this version's schema. A database that a newer
    /// version of Ficha migrated is refused, and left as it was.
    public init(location: DatabaseLocation, time: any TimeSource) throws(EngineError) {
        let database = try reportingStorageErrors { () throws -> any DatabaseWriter in
            switch location {
            case .folder(let folder):
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return try DatabasePool(path: folder.appending(path: "Ficha.sqlite").path(percentEncoded: false))
            case .inMemory:
                return try DatabaseQueue()
            }
        }
        if try reportingStorageErrors({ try database.read(Schema.migrator.hasBeenSuperseded) }) {
            logger.error("Refused a database that a newer version of Ficha migrated")
            throw .migratedByNewerVersion
        }
        try reportingStorageErrors { try Schema.migrator.migrate(database) }
        self.database = database
        self.time = time
    }

    /// Saves a capture in the inbox, cleaned up as `CaptureContent` says. A
    /// capture without text isn't saved.
    public func capture(text: String, note: String?, source: String?) throws(EngineError) {
        guard let content = CaptureContent(text: text, note: note, source: source) else {
            throw .emptyCapture
        }
        let createdAt = time.now
        try reportingStorageErrors {
            try database.write { db in
                try db.execute(
                    sql: "INSERT INTO capture (text, note, source, createdAt) VALUES (?, ?, ?, ?)",
                    arguments: [content.text, content.note, content.source, createdAt]
                )
            }
        }
    }

    /// The captures waiting in the inbox, oldest first.
    public func inbox() throws(EngineError) -> [Capture] {
        try reportingStorageErrors {
            try database.read { db in
                try Row.fetchAll(db, sql: "SELECT * FROM capture ORDER BY id").map(Capture.init(row:))
            }
        }
    }

    /// How many captures wait in the inbox.
    public func inboxCount() throws(EngineError) -> Int {
        try reportingStorageErrors {
            try database.read { db in
                try Table("capture").fetchCount(db)
            }
        }
    }
}

/// Runs work on the database. When SQLite fails, it logs why and throws the
/// engine's error, whose message Lucas can read.
private func reportingStorageErrors<Value>(_ work: () throws -> Value) throws(EngineError) -> Value {
    do {
        return try work()
    } catch {
        logger.error("The database failed: \(String(describing: error))")
        throw .storage
    }
}
