import Foundation
internal import GRDB
import os

/// The move's log: what the copy of a data folder held once it matched, and
/// the preferences file, or why they failed.
let moveLogger = Logger(subsystem: "com.lucastkacz.ficha", category: "data move")

/// What a data folder's copy holds, once it matched the folder it was copied
/// from.
public struct CopiedDataFolder: Sendable, Equatable, CustomStringConvertible {
    /// How many rows each of the database's tables holds, by its name.
    public let rows: [String: Int]
    /// The files beside the database, such as those in Images, Sounds and
    /// Backups, by their paths in the data folder.
    public let files: Set<String>

    public var description: String {
        "\(rows.values.reduce(0, +)) rows in \(rows.count) tables, and \(files.count) files"
    }
}

/// Copies the data folder `source` to `target`, which mustn't exist yet, as
/// the last build of the real Ficha without its sandbox does, from
/// Application Support's into its App Group's folder (ADR 0018): the
/// database through SQLite's online backup, whole and consistent even while
/// another process writes, and everything beside it, such as Images, Sounds
/// and Backups, as files. The copy then checks itself: SQLite's integrity
/// check, the same rows in every table as the database had when it was
/// copied, and the same files. It's made in a hidden folder beside `target`,
/// which takes `target`'s name only once every check passed, so `target`
/// holds a database only once it holds all of it. When anything fails, the
/// log says why, and the hidden folder goes: `target` stays as it was. The
/// database in `source` is opened read-only, so the copy changes nothing
/// there. Returns what the copy holds, which the log says too.
@discardableResult
public func copyDataFolder(from source: URL, to target: URL) throws(DataFolderCopyError) -> CopiedDataFolder {
    let parent = target.deletingLastPathComponent()
    let staging = parent.appending(
        path: ".\(target.lastPathComponent) \(UUID().uuidString)", directoryHint: .isDirectory)
    do throws(DataFolderCopyError) {
        guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else {
            throw .targetExists(target)
        }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            throw .fileSystem("Couldn't make a folder for the copy: \(error)")
        }
        let rows = try copyDatabase(from: source, to: staging)
        let files = try copyFiles(from: source, to: staging)
        do {
            try FileManager.default.moveItem(at: staging, to: target)
        } catch {
            throw .fileSystem("Couldn't give the copy its folder's name: \(error)")
        }
        let copied = CopiedDataFolder(rows: rows, files: files)
        moveLogger.notice(
            """
            Copied the data folder \(source.path(percentEncoded: false), privacy: .public) to \
            \(target.path(percentEncoded: false), privacy: .public), and the copy matched: \
            \(copied.description, privacy: .public)
            """)
        return copied
    } catch {
        try? FileManager.default.removeItem(at: staging)
        moveLogger.error(
            """
            Couldn't copy the data folder \(source.path(percentEncoded: false), privacy: .public), which stays as \
            it was: \(error.description, privacy: .public)
            """)
        throw error
    }
}

/// Copies the database in the data folder `source` into the data folder
/// `target` through SQLite's online backup, checks the copy, and returns how
/// many rows each table holds. The rows are counted in the same read as the
/// backup, so they're those the copy got, even while another process writes.
private func copyDatabase(from source: URL, to target: URL) throws(DataFolderCopyError) -> [String: Int] {
    let sourceFile = source.appending(path: databaseFileName)
    guard FileManager.default.fileExists(atPath: sourceFile.path(percentEncoded: false)) else {
        throw .noDatabase(source)
    }
    do {
        var configuration = Configuration()
        configuration.readonly = true
        let original = try DatabaseQueue(path: sourceFile.path(percentEncoded: false), configuration: configuration)
        let copy = try DatabaseQueue(path: target.appending(path: databaseFileName).path(percentEncoded: false))
        let rows = try original.read { db in
            let rows = try rowsByTable(in: db)
            try copy.writeWithoutTransaction { try db.backup(to: $0) }
            return rows
        }
        let problems = try copy.read { db in try String.fetchAll(db, sql: "PRAGMA integrity_check") }
        guard problems == ["ok"] else {
            throw DataFolderCopyError.integrity(problems)
        }
        let copied = try copy.read(rowsByTable(in:))
        guard copied == rows else {
            throw DataFolderCopyError.rows(expected: rows, copied: copied)
        }
        try copy.close()
        try original.close()
        return rows
    } catch let error as DataFolderCopyError {
        throw error
    } catch {
        throw .database("\(error)")
    }
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
/// files into the data folder `target`, checks that `target` holds the same
/// files, and returns their paths.
private func copyFiles(from source: URL, to target: URL) throws(DataFolderCopyError) -> Set<String> {
    do {
        let items = try FileManager.default.contentsOfDirectory(atPath: source.path(percentEncoded: false))
        for item in items where !isDatabaseFile(item) {
            try FileManager.default.copyItem(at: source.appending(path: item), to: target.appending(path: item))
        }
    } catch {
        throw .fileSystem("Couldn't copy the files beside the database: \(error)")
    }
    let files = filesBesideDatabase(in: source)
    let copied = filesBesideDatabase(in: target)
    guard files == copied else {
        throw .files(files.symmetricDifference(copied))
    }
    let different = files.filter {
        !FileManager.default.contentsEqual(
            atPath: source.appending(path: $0).path(percentEncoded: false),
            andPath: target.appending(path: $0).path(percentEncoded: false))
    }
    guard different.isEmpty else {
        throw .files(different)
    }
    return files
}

/// The paths of the files in the data folder `folder`, in its folders too,
/// but the database's own.
private func filesBesideDatabase(in folder: URL) -> Set<String> {
    let paths = FileManager.default.subpaths(atPath: folder.path(percentEncoded: false)) ?? []
    return Set(
        paths.filter { path in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(
                atPath: folder.appending(path: path).path(percentEncoded: false), isDirectory: &isFolder)
            return !isFolder.boolValue && !isDatabaseFile(path)
        })
}

/// The name of the engine's database file in a data folder.
private let databaseFileName = "Ficha.sqlite"

/// Whether `path`, in a data folder, is the database's file, or one SQLite
/// keeps beside it while it's open.
private func isDatabaseFile(_ path: String) -> Bool {
    ["", "-wal", "-shm", "-journal"].contains { path == databaseFileName + $0 }
}

/// Why a data folder couldn't be copied. The folder it was copied from is
/// as it was, and the one it went to holds nothing of it: opening the app
/// again tries again. Each says what happened, in English, for the log,
/// which alone shows it.
public enum DataFolderCopyError: Error, Equatable, CustomStringConvertible {
    /// The folder the copy goes to exists already.
    case targetExists(URL)
    /// The data folder holds no database to copy.
    case noDatabase(URL)
    /// SQLite failed, as it said.
    case database(String)
    /// SQLite's integrity check on the copy found these problems.
    case integrity([String])
    /// The copy's tables don't hold as many rows as the database's did.
    case rows(expected: [String: Int], copied: [String: Int])
    /// These files, by their paths in the data folder, aren't the same in
    /// the copy.
    case files(Set<String>)
    /// A file or a folder couldn't be made, copied or named, as this says.
    case fileSystem(String)

    public var description: String {
        let tryAgain = "Quit Ficha and open it again to try again: it works from the data folder it had meanwhile."
        return switch self {
        case .targetExists(let folder):
            "The copy's folder, \(folder.path(percentEncoded: false)), exists already. Move it to the Trash. \(tryAgain)"
        case .noDatabase(let folder):
            "\(folder.path(percentEncoded: false)) holds no database to copy."
        case .database(let reason):
            "SQLite failed: \(reason). \(tryAgain)"
        case .integrity(let problems):
            "SQLite's integrity check found problems in the copy: \(problems.joined(separator: "; ")). \(tryAgain)"
        case .rows(let expected, let copied):
            "The copy's tables don't hold the database's rows: \(copied), not \(expected). \(tryAgain)"
        case .files(let paths):
            "These files aren't the same in the copy: \(paths.sorted().joined(separator: ", ")). \(tryAgain)"
        case .fileSystem(let reason):
            "\(reason). \(tryAgain)"
        }
    }
}
