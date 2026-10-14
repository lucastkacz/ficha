import FichaCore
import Foundation
internal import GRDB

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
        let database = try storage { () throws -> any DatabaseWriter in
            switch location {
            case .folder(let folder):
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return try DatabasePool(path: folder.appending(path: "Ficha.sqlite").path(percentEncoded: false))
            case .inMemory:
                return try DatabaseQueue()
            }
        }
        if try storage({ try database.read(Schema.migrator.hasBeenSuperseded) }) {
            throw .migratedByNewerVersion
        }
        try storage { try Schema.migrator.migrate(database) }
        self.database = database
        self.time = time
    }

    /// Saves a capture in the inbox, without surrounding spaces. A blank note or
    /// source is left out, and a capture without text isn't saved.
    public func capture(text: String, note: String?, source: String?) throws(EngineError) {
        guard let text = nonBlank(text) else {
            throw .emptyCapture
        }
        let note = nonBlank(note)
        let source = nonBlank(source)
        let createdAt = time.now
        try storage {
            try database.write { db in
                try db.execute(
                    sql: "INSERT INTO capture (text, note, source, createdAt) VALUES (?, ?, ?, ?)",
                    arguments: [text, note, source, createdAt]
                )
            }
        }
    }

    /// The captures waiting in the inbox, oldest first.
    public func inbox() throws(EngineError) -> [Capture] {
        try storage {
            try database.read { db in
                try Row.fetchAll(db, sql: "SELECT * FROM capture ORDER BY id").map(Capture.init(row:))
            }
        }
    }
}

/// The value without surrounding spaces, or nil when nothing is left.
private func nonBlank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

/// Runs work on the database, turning what SQLite throws into the engine's error.
private func storage<Value>(_ work: () throws -> Value) throws(EngineError) -> Value {
    do {
        return try work()
    } catch let error as EngineError {
        throw error
    } catch {
        throw .storage(String(describing: error))
    }
}
