import Foundation
internal import GRDB
import os

/// The data move's log: what the new data folder held once it matched the
/// old one, and the preferences file, or why they failed.
let moveLogger = Logger(subsystem: "com.lucastkacz.ficha", category: "data move")

/// Lucas's data move (ADR 0018, #309): the last build of the real Ficha
/// without its sandbox copies his data folder from Application Support's
/// into its App Group's folder, which the sandboxed app and its CLI share,
/// and leaves the old one as it was. SQLite's online backup and its
/// integrity check are SQLite's documented ways to copy a database in use
/// and to check it. The rest is our own: the hidden folder renamed into
/// place, the comparison of rows and files, `PRAGMA data_version` read to
/// catch another process's write, and the preferences carried in a plist
/// that's read in once (`PreferencesFile`).
public struct DataMove: Sendable, Equatable {
    /// The data folder the data moves from, as Application Support's.
    public let source: URL
    /// The data folder it moves to, as the one in the App Group's folder.
    public let target: URL

    /// The move from the data folder `source` to `target` while it waits:
    /// `source` holds a database, and `target` holds none, before the move
    /// ran or after it failed. Nil once it moved, and when there's nothing
    /// to move, as for anyone but Lucas.
    public init?(waitingFrom source: URL, to target: URL) {
        guard holdsDatabase(source), !holdsDatabase(target) else { return nil }
        self.source = source
        self.target = target
    }

    /// Runs the move: the database through SQLite's online backup, whole and
    /// consistent even while another process writes, and everything beside
    /// it, such as Images, Sounds and Backups, as files. The new folder then
    /// checks itself: SQLite's integrity check, the same rows in every table
    /// as the database had when it was copied, and the same files. It's made
    /// in a hidden folder beside `target`, which takes `target`'s name only
    /// once every check passed, so `target` holds a database only once it
    /// holds all of it, and only if no other process wrote to the database
    /// in `source` meanwhile, as the CLI can. When anything fails, the log
    /// says why, and the hidden folder goes: `target` stays as it was, and
    /// the move waits for the next try. A move first removes the hidden
    /// folders that moves the app was killed in left, and runs while no
    /// other process moves into `target`, so it never removes theirs. The
    /// database in `source` is opened read-only, so the move changes nothing
    /// there. Returns what the new folder holds, which the log says too.
    @discardableResult
    public func run() throws(DataMoveError) -> MovedData {
        var result: Result<MovedData, DataMoveError>?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: target, options: .forMerging, error: &coordinationError
        ) { _ in
            result = Result { () throws(DataMoveError) in try stage().finish() }
        }
        guard let result else {
            // The file coordinator says why it didn't run the move, as Apple
            // documents: one that doesn't say fails too, and says so.
            let reason = coordinationError.map { "\($0)" } ?? "the file coordinator didn't run it, nor say why"
            let error = DataMoveError.fileSystem(
                "Couldn't wait for other processes to move into the new data folder: \(reason)")
            moveLogger.error("Couldn't move the data folder: \(error.description, privacy: .public)")
            throw error
        }
        return try result.get()
    }

    /// The move's first half: the new folder, made and checked in its hidden
    /// folder, which waits for `finish` to give it `target`'s name. A staged
    /// move that never finishes, as when the app is killed, leaves its hidden
    /// folder behind.
    func stage() throws(DataMoveError) -> StagedDataMove {
        let staging = target.deletingLastPathComponent().appending(
            path: hiddenFolderPrefix + UUID().uuidString, directoryHint: .isDirectory)
        do throws(DataMoveError) {
            guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else {
                throw .targetExists(target)
            }
            removeHiddenFoldersLeft()
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            } catch {
                throw .fileSystem("Couldn't make a hidden folder for the move: \(error)")
            }
            let (original, version, rows) = try stageDatabase(from: source, in: staging)
            let files = try stageFiles(from: source, in: staging)
            return StagedDataMove(
                move: self, folder: staging, original: original, originalVersion: version,
                moved: MovedData(rows: rows, files: files))
        } catch {
            throw failed(error, removing: staging)
        }
    }

    /// How the names of the move's hidden folders begin, beside `target`:
    /// with a dot, which hides them, and `target`'s name.
    private var hiddenFolderPrefix: String {
        ".\(target.lastPathComponent) "
    }

    /// Removes the hidden folders beside `target` that moves the app was
    /// killed or crashed in left, each holding data that never got its name.
    /// One that can't be removed stays, and the log says why: it never takes
    /// `target`'s name.
    private func removeHiddenFoldersLeft() {
        let parent = target.deletingLastPathComponent()
        // A folder that isn't there yet holds none.
        let items = (try? FileManager.default.contentsOfDirectory(atPath: parent.path(percentEncoded: false))) ?? []
        for item in items where item.hasPrefix(hiddenFolderPrefix) {
            do {
                try FileManager.default.removeItem(at: parent.appending(path: item))
                moveLogger.notice("Removed \(item, privacy: .public), which a move that didn't finish left")
            } catch {
                moveLogger.error(
                    """
                    Couldn't remove \(item, privacy: .public), which a move that didn't finish left: \
                    \(String(describing: error), privacy: .public)
                    """)
            }
        }
    }

    /// `error`, once the move's hidden folder `staging` went, and the log
    /// said why the move failed.
    fileprivate func failed(_ error: DataMoveError, removing staging: URL) -> DataMoveError {
        // A hidden folder that can't go stays out of `target`, and the next
        // move removes it.
        try? FileManager.default.removeItem(at: staging)
        moveLogger.error(
            """
            Couldn't move the data folder \(source.path(percentEncoded: false), privacy: .public), which stays as \
            it was: \(error.description, privacy: .public)
            """)
        return error
    }
}

/// A data move whose new folder is made and checked in its hidden folder,
/// waiting for its name.
struct StagedDataMove {
    /// The move.
    let move: DataMove
    /// The hidden folder that holds the new folder.
    let folder: URL
    /// The old database, opened read-only, and held open since it was
    /// copied, so its `PRAGMA data_version` tells whether another connection
    /// wrote to it since, as SQLite documents.
    let original: DatabaseQueue
    /// The old database's `PRAGMA data_version` when it was copied.
    let originalVersion: Int
    /// What the new folder holds.
    let moved: MovedData

    /// The move's second half: gives the hidden folder the new folder's
    /// name, and returns what it holds, unless another process wrote to the
    /// old database since it was copied. When that fails, the hidden folder
    /// goes, and the log says why.
    func finish() throws(DataMoveError) -> MovedData {
        do throws(DataMoveError) {
            do {
                let version = try original.read(dataVersion(of:))
                try original.close()
                guard version == originalVersion else {
                    throw DataMoveError.sourceChanged(move.source)
                }
            } catch let error as DataMoveError {
                throw error
            } catch {
                throw .database("\(error)")
            }
            do {
                try FileManager.default.moveItem(at: folder, to: move.target)
            } catch {
                throw .fileSystem("Couldn't give the hidden folder the new folder's name: \(error)")
            }
        } catch {
            throw move.failed(error, removing: folder)
        }
        moveLogger.notice(
            """
            Moved the data folder \(move.source.path(percentEncoded: false), privacy: .public) to \
            \(move.target.path(percentEncoded: false), privacy: .public), and the new one matched: \
            \(moved.description, privacy: .public)
            """)
        return moved
    }
}

/// What the data move's new folder holds, once it matched the old one.
public struct MovedData: Sendable, Equatable, CustomStringConvertible {
    /// How many rows each of the database's tables holds, by its name.
    public let rows: [String: Int]
    /// The files beside the database, such as those in Images, Sounds and
    /// Backups, by their paths in the data folder.
    public let files: Set<String>

    public var description: String {
        "\(rows.values.reduce(0, +)) rows in \(rows.count) tables, and \(files.count) files"
    }
}

/// Copies the database in the data folder `source` into `staging`, the
/// move's hidden folder, through SQLite's online backup, and checks it.
/// Returns the old database, opened read-only, its `PRAGMA data_version`,
/// and how many rows each table holds. The version and the rows are read in
/// the same read as the backup, so they're those of the database the backup
/// got, even while another process writes.
private func stageDatabase(
    from source: URL, in staging: URL
) throws(DataMoveError) -> (original: DatabaseQueue, version: Int, rows: [String: Int]) {
    let sourceFile = databaseFile(in: source)
    guard FileManager.default.fileExists(atPath: sourceFile.path(percentEncoded: false)) else {
        throw .noDatabase(source)
    }
    do {
        var configuration = Configuration()
        configuration.readonly = true
        let original = try DatabaseQueue(path: sourceFile.path(percentEncoded: false), configuration: configuration)
        let staged = try DatabaseQueue(path: databaseFile(in: staging).path(percentEncoded: false))
        let (version, rows) = try original.read { db in
            let version = try dataVersion(of: db)
            let rows = try rowsByTable(in: db)
            try staged.writeWithoutTransaction { try db.backup(to: $0) }
            return (version, rows)
        }
        let problems = try staged.read { db in try String.fetchAll(db, sql: "PRAGMA integrity_check") }
        guard problems == ["ok"] else {
            throw DataMoveError.integrity(problems)
        }
        let stagedRows = try staged.read(rowsByTable(in:))
        guard stagedRows == rows else {
            throw DataMoveError.rows(expected: rows, moved: stagedRows)
        }
        try staged.close()
        return (original, version, rows)
    } catch let error as DataMoveError {
        throw error
    } catch {
        throw .database("\(error)")
    }
}

/// The database's `PRAGMA data_version`, which changes once another
/// connection wrote to it, as SQLite documents. A version SQLite doesn't
/// give fails, so the move never takes two missing ones for the same.
private func dataVersion(of db: Database) throws -> Int {
    guard let version = try Int.fetchOne(db, sql: "PRAGMA data_version") else {
        throw DataMoveError.database("PRAGMA data_version gave no version")
    }
    return version
}

/// How many rows each table of the database holds, by its name.
private func rowsByTable(in db: Database) throws -> [String: Int] {
    var rows: [String: Int] = [:]
    for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") {
        rows[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table.quotedDatabaseIdentifier)")
    }
    return rows
}

/// Copies everything in the data folder `source` but the database's own
/// files into `staging`, the move's hidden folder, checks that it holds the
/// same files, and returns their paths.
private func stageFiles(from source: URL, in staging: URL) throws(DataMoveError) -> Set<String> {
    do {
        let items = try FileManager.default.contentsOfDirectory(atPath: source.path(percentEncoded: false))
        for item in items where !isDatabaseFile(item) {
            try FileManager.default.copyItem(at: source.appending(path: item), to: staging.appending(path: item))
        }
    } catch {
        throw .fileSystem("Couldn't copy the files beside the database: \(error)")
    }
    let files = try filesBesideDatabase(in: source)
    let staged = try filesBesideDatabase(in: staging)
    guard files == staged else {
        throw .files(files.symmetricDifference(staged))
    }
    let different = files.filter {
        !FileManager.default.contentsEqual(
            atPath: source.appending(path: $0).path(percentEncoded: false),
            andPath: staging.appending(path: $0).path(percentEncoded: false))
    }
    guard different.isEmpty else {
        throw .files(different)
    }
    return files
}

/// The paths of the files in the data folder `folder`, in its folders too,
/// but the database's own. A folder that can't be listed fails, so the
/// move's check never compares no files at all.
func filesBesideDatabase(in folder: URL) throws(DataMoveError) -> Set<String> {
    guard let paths = FileManager.default.subpaths(atPath: folder.path(percentEncoded: false)) else {
        throw .fileSystem("Couldn't list the files in \(folder.path(percentEncoded: false))")
    }
    return Set(
        paths.filter { path in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(
                atPath: folder.appending(path: path).path(percentEncoded: false), isDirectory: &isFolder)
            return !isFolder.boolValue && !isDatabaseFile(path)
        })
}

/// Whether the data folder `folder` holds the database's file.
private func holdsDatabase(_ folder: URL) -> Bool {
    FileManager.default.fileExists(atPath: databaseFile(in: folder).path(percentEncoded: false))
}

/// Whether `path`, in a data folder, is the database's file, or one SQLite
/// keeps beside it while it's open.
private func isDatabaseFile(_ path: String) -> Bool {
    ["", "-wal", "-shm", "-journal"].contains { path == databaseFileName + $0 }
}

/// Why the data move failed. The old data folder is as it was, and the new
/// one's place holds nothing of it: opening the app again tries again. Each
/// says what happened, in English, for the log, which alone shows it.
public enum DataMoveError: Error, Equatable, CustomStringConvertible {
    /// The new data folder exists already, without a database.
    case targetExists(URL)
    /// The old data folder holds no database to move.
    case noDatabase(URL)
    /// Another process wrote to the database in this old data folder after
    /// it was copied, as the CLI can, so the new folder would miss the
    /// change.
    case sourceChanged(URL)
    /// SQLite failed, as it said.
    case database(String)
    /// SQLite's integrity check on the moved database found these problems.
    case integrity([String])
    /// The moved database's tables don't hold as many rows as the old one's
    /// did.
    case rows(expected: [String: Int], moved: [String: Int])
    /// These files, by their paths in the data folder, aren't the same in
    /// the new one.
    case files(Set<String>)
    /// A file or a folder couldn't be made, copied or named, as this says.
    case fileSystem(String)

    public var description: String {
        let tryAgain = "Quit Ficha and open it again to try again: it works from the old data folder meanwhile."
        return switch self {
        case .targetExists(let folder):
            """
            The new data folder, \(folder.path(percentEncoded: false)), exists already, without a database. Move it \
            to the Trash. \(tryAgain)
            """
        case .noDatabase(let folder):
            """
            \(folder.path(percentEncoded: false)) holds no database, \(databaseFileName), to move. Check that the \
            old data folder holds it. \(tryAgain)
            """
        case .sourceChanged(let folder):
            """
            The database in \(folder.path(percentEncoded: false)) changed while it moved, as when the ficha CLI \
            writes, so the new data folder would miss the change. \(tryAgain)
            """
        case .database(let reason):
            "SQLite failed: \(reason). \(tryAgain)"
        case .integrity(let problems):
            "SQLite's integrity check found problems in the moved database: \(problems.joined(separator: "; ")). \(tryAgain)"
        case .rows(let expected, let moved):
            "The moved database's tables don't hold the old one's rows: \(moved), not \(expected). \(tryAgain)"
        case .files(let paths):
            "These files aren't the same in the new data folder: \(paths.sorted().joined(separator: ", ")). \(tryAgain)"
        case .fileSystem(let reason):
            "\(reason). \(tryAgain)"
        }
    }
}
