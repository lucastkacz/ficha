import FichaCore
import FichaSVG
import Foundation
internal import GRDB
import os

/// The engine's log, for FichaData's files.
let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "engine")

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
    let database: any DatabaseWriter
    let databaseChanges: DatabaseChanges
    /// The data folder the database is in, or nil when it's in memory.
    let dataFolder: URL?
    let time: any TimeSource
    /// The Mac's calendar, whose days the new cards are counted by.
    let calendar: Calendar
    /// Where the images on cards are kept: the Images folder beside the
    /// database, or memory with it.
    let images: FileStore<ImageName>
    /// Where the sounds on cards are kept: the Sounds folder beside the
    /// database, or memory with it.
    let sounds: FileStore<SoundName>
    /// The Downloads folder, when a refine session's files may come from
    /// there alone, as in the `ficha` CLI's sandbox (ADR 0018), or nil when
    /// they may come from anywhere.
    let refineFilesOnlyIn: URL?
    /// A new SVG drawer for each import's SVGs, or nil when its imports draw
    /// none.
    let newSVGDrawer: (@Sendable () -> any SVGDrawer)?

    /// Opens the database at `location`, creating it if it doesn't exist yet,
    /// and migrates it to this version's schema. Before migrating a database
    /// that an older version of Ficha left, it saves a copy before an update
    /// in the Backups folder, where it first moves those that versions before
    /// backups left next to the database. A database that a newer version
    /// migrated is refused, and left as it was. Days start at midnight by
    /// `calendar`: the Mac's, except in tests. A refine session's files come
    /// from `downloads` alone, the Downloads folder, when it's given, and from
    /// anywhere when it isn't. An import draws its SVGs with a drawer
    /// `newSVGDrawer` makes, in the app its XPC service, and without one, as
    /// in the CLI and on the iPhone, which don't import, it draws none.
    public init(
        location: DatabaseLocation,
        time: any TimeSource,
        calendar: Calendar = .autoupdatingCurrent,
        refineFilesOnlyIn downloads: URL? = nil,
        drawingSVGsWith newSVGDrawer: (@Sendable () -> any SVGDrawer)? = nil
    ) throws(EngineError) {
        switch location {
        case .folder(let folder):
            let file = databaseFile(in: folder)
            database = try whileNoOtherProcessOpens(file) { () throws(EngineError) in
                let pool = try reportingStorageErrors {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    // The app and the CLI write to the same file, so a write
                    // waits for the other process's to end instead of failing,
                    // as GRDB's guide to sharing a database says.
                    var configuration = Configuration()
                    configuration.busyMode = .timeout(5)
                    return try DatabasePool(path: file.path(percentEncoded: false), configuration: configuration)
                }
                let backups = folderOfBackups(in: folder)
                moveOldCopiesBeforeAnUpdate(from: folder, into: backups)
                try migrate(pool, savingACopyIn: backups, at: time.now)
                return pool
            }
            databaseChanges = DatabaseChanges(database: file.path(percentEncoded: false))
            dataFolder = folder
            images = .folder(folderOfImages(in: folder))
            sounds = .folder(FichaData.folder(of: SoundName.self, in: folder))
        case .inMemory:
            let queue = try reportingStorageErrors { try DatabaseQueue() }
            try migrate(queue, savingACopyIn: nil, at: time.now)
            database = queue
            databaseChanges = DatabaseChanges(database: "in memory \(UUID().uuidString)")
            dataFolder = nil
            images = .memory(FilesInMemory())
            sounds = .memory(FilesInMemory())
        }
        self.time = time
        self.calendar = calendar
        refineFilesOnlyIn = downloads
        self.newSVGDrawer = newSVGDrawer
    }

    /// Every change to the database from now on, by this engine or by another
    /// one on the same database, such as the CLI's while the app runs, but
    /// the plan of appearances the engine keeps, which changes no card.
    /// Changes that come while one waits to be handled are merged into it.
    public func changes() -> AsyncStream<Void> {
        databaseChanges.stream()
    }

    /// The current time the engine works with: the system's, except in tests
    /// and in Ficha Dev, whose debug tools move it forward.
    public var now: Date {
        time.now
    }

    /// Saves a capture in the inbox, cleaned up as `CaptureContent` says, and
    /// returns it, unless it's a duplicate of a card or a capture in the inbox:
    /// then it isn't saved, and the result says what it repeats, for Lucas to
    /// expand or ignore it. A capture without text isn't saved.
    public func capture(text: String, note: String?, source: String?) throws(EngineError) -> CaptureResult {
        guard let content = CaptureContent(text: text, note: note, source: source) else {
            throw .emptyCapture
        }
        let createdAt = time.now
        return try write { db in
            if let repeated = try repeated(by: content.text, in: db) {
                return .duplicate(of: repeated)
            }
            return .saved(try save(content, expanding: nil, at: createdAt, in: db))
        }
    }

    /// What waits in the inbox: the captures, the expansions and the
    /// follow-ups, oldest first, and the flagged cards, the first flagged
    /// first.
    public func inbox() throws(EngineError) -> Inbox {
        try read { db in
            let captures = try capturesWaiting(in: db)
            return Inbox(
                captures: captures.filter { $0.expandsCardID == nil && $0.followsUpCardID == nil },
                expansions: try captures.compactMap { try $0.expansion(in: db) },
                followUps: try captures.compactMap { try $0.followUp(in: db) },
                flaggedCards: try flaggedCardsWaiting(in: db)
            )
        }
    }

    /// Approves a capture into one or more cards: saves them as new cards,
    /// each going one way, in the order given, takes the capture out of the
    /// inbox and returns the cards.
    @discardableResult
    public func approve(_ captureID: Int64, into cards: [CardContent]) throws(EngineError) -> [Card] {
        try approve(captureID, into: cards.map { ($0, false) })
    }

    /// Approves a capture into one or more cards, as `approve(_:into:)` does,
    /// each going both ways when it says so.
    func approve(_ captureID: Int64, into cards: [(content: CardContent, bothWays: Bool)]) throws(EngineError)
        -> [Card]
    {
        guard !cards.isEmpty else {
            throw .noCards
        }
        let createdAt = time.now
        return try write { db in
            try takeOutOfInbox(captureID, at: createdAt, in: db)
            for card in cards {
                try insertCard(card.content, bothWays: card.bothWays, capturedAs: captureID, at: createdAt, in: db)
            }
            return try FichaData.cards(
                in: Row.fetchAll(
                    db, sql: "SELECT * FROM card WHERE captureId = ? ORDER BY id", arguments: [captureID]),
                in: db)
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
        try read(allCards(in:))
    }

    /// Runs `work` on the database as it is, in one read.
    func read<Value>(_ work: (Database) throws -> Value) throws(EngineError) -> Value {
        try reportingStorageErrors { try database.read(work) }
    }

    /// Runs `updates` in one transaction, then tells every engine on the
    /// database that it changed.
    func write<Value>(_ updates: (Database) throws -> Value) throws(EngineError) -> Value {
        let value = try writeWithoutTelling(updates)
        databaseChanges.post()
        return value
    }

    /// Runs `updates` in one transaction, as `write` does, but tells no
    /// engine that the database changed: for a write that changes no card,
    /// which an engine listening for changes would answer with another one.
    /// Every write to the cards, captures, review log and tags goes through
    /// here, which first tells the triggers that record each change to sync
    /// when the write happens. Two writes don't, and record nothing: a
    /// restore, which replaces the whole database, as it was when it was
    /// copied, and a migration, which changes the schema.
    func writeWithoutTelling<Value>(_ updates: (Database) throws -> Value) throws(EngineError) -> Value {
        let now = time.now
        return try reportingStorageErrors {
            try database.write { db in
                try db.execute(sql: "UPDATE syncWrite SET at = ?", arguments: [now])
                return try updates(db)
            }
        }
    }
}

/// The name of the database's file in a data folder.
let databaseFileName = "Ficha.sqlite"

/// The database's file in the data folder `folder`.
func databaseFile(in folder: URL) -> URL {
    folder.appending(path: databaseFileName)
}

/// Runs `work` on `file` while no other process does the same, as GRDB's guide
/// to sharing a database says: Ficha and its CLI may open the database at the
/// same time, and both could migrate it, or copy it once it's migrated.
func whileNoOtherProcessOpens<Value>(
    _ file: URL,
    _ work: () throws(EngineError) -> Value
) throws(EngineError) -> Value {
    var result: Result<Value, EngineError>?
    var coordinationError: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(
        writingItemAt: file,
        options: .forMerging,
        error: &coordinationError
    ) { _ in
        result = Result(catching: work)
    }
    guard let result else {
        logger.error("Couldn't wait for other processes to open the database: \(String(describing: coordinationError))")
        throw .storage
    }
    return try result.get()
}

/// Migrates the database to this version's schema. A database that a newer
/// version migrated is refused, and one that an older version left is saved
/// first, at `time`, as a copy before an update in `backups`, the Backups
/// folder, if there's one.
func migrate(_ database: any DatabaseWriter, savingACopyIn backups: URL?, at time: Date) throws(EngineError) {
    if try reportingStorageErrors({ try database.read(Schema.migrator.hasBeenSuperseded) }) {
        logger.error("Refused a database that a newer version of Ficha migrated")
        throw .migratedByNewerVersion
    }
    if let backups, let migration = try reportingStorageErrors({ try database.read(firstMigrationToApply) }) {
        try saveCopy(of: database, as: .beforeUpdate, at: time, in: backups)
        logger.notice("Saved a copy of the database before the migration \(migration, privacy: .public)")
    }
    try reportingStorageErrors { try Schema.migrator.migrate(database) }
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

/// The captures that wait in the inbox: those not refined yet, into cards or
/// into none.
var capturesInInbox: QueryInterfaceRequest<Row> {
    Table("capture").filter(Column("refinedAt") == nil)
}

/// The capture with this id, as it is now, or an error when it isn't in the
/// inbox.
func captureInInbox(_ captureID: Int64, in db: Database) throws -> Capture {
    guard let row = try capturesInInbox.filter(Column("id") == captureID).fetchOne(db) else {
        throw EngineError.captureNotInInbox(captureID)
    }
    return try Capture(row: row)
}

/// Takes a capture out of the inbox, as refined at `time`, and returns it, or
/// throws when it isn't in the inbox.
@discardableResult
func takeOutOfInbox(_ captureID: Int64, at time: Date, in db: Database) throws -> Capture {
    let capture = try captureInInbox(captureID, in: db)
    try db.execute(sql: "UPDATE capture SET refinedAt = ? WHERE id = ?", arguments: [time, captureID])
    return capture
}

/// Runs work on the database. The engine's own errors pass through as they
/// are; when a card's review log can't be followed, or SQLite fails, it logs
/// why and throws the engine's error, whose message Lucas can read.
func reportingStorageErrors<Value>(_ work: () throws -> Value) throws(EngineError) -> Value {
    do {
        return try work()
    } catch let error as EngineError {
        throw error
    } catch let error as UnexpectedReviewLog {
        logger.error(
            """
            Card \(error.cardID)'s review log has reviews but no first view or placement to start them, \
            or a placement that doesn't start it or is on a step below the first
            """)
        throw .unreadableReviewLog(error.cardID)
    } catch {
        logger.error("The database failed: \(String(describing: error))")
        throw .storage
    }
}

/// The error for a row whose values this version of Ficha doesn't know.
func unreadable(_ description: String) -> DecodingError {
    DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: description))
}
