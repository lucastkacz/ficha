import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// The folder the engine saves its copies in, Backups, in its data
    /// folder, or nil for an engine in memory, which saves none.
    public var backupsFolder: URL? {
        dataFolder.map(folderOfBackups(in:))
    }

    /// Every copy in the Backups folder, newest first: the backups, and the
    /// copies before an update, a restore or an import.
    public func copies() throws(EngineError) -> [DatabaseCopy] {
        guard let backupsFolder else {
            return []
        }
        return try listCopies(in: backupsFolder)
    }

    /// Saves a backup when none was saved yet in the hour, day or week the
    /// engine's time is in, as `settings` says, and then lets the oldest
    /// backups beyond the number kept go: the app asks as it launches, and as
    /// time passes. Returns the backup it saved, or nil when one was saved
    /// already in that hour, day or week.
    @discardableResult
    public func backUpIfDue(_ settings: BackupSettings) throws(EngineError) -> DatabaseCopy? {
        let backupTimes = try copies().filter { $0.kind == .backup }.map(\.savedAt)
        guard settings.isBackupDue(at: time.now, savedAt: backupTimes, calendar: calendar) else {
            return nil
        }
        return try backUpNow(settings)
    }

    /// Saves a backup now, as Back Up Now does, and then lets the oldest
    /// backups beyond the number `settings` keeps go, with the images and
    /// sounds no remaining copy refers to. It's the backup of the hour, day
    /// or week it's saved in. Returns the backup.
    @discardableResult
    public func backUpNow(_ settings: BackupSettings) throws(EngineError) -> DatabaseCopy {
        let backup = try saveCopy(.backup)
        let extras = try copies().filter { $0.kind == .backup }.dropFirst(settings.keptCount)
        for extra in extras {
            try removeCopy(extra)
        }
        if !extras.isEmpty {
            dropFilesNoCopyUses()
        }
        return backup
    }

    /// Brings back the copy in the Backups folder named `name`, in place of
    /// everything as it is now, which it first saves as a copy before a
    /// restore, so restoring that copy undoes the restore. SQLite's online
    /// backup copies the copy into the database, the reverse of saving one:
    /// the database's file stays where it is, in write-ahead logging, so the
    /// other engines on it, like the CLI's or the app's, read the restored
    /// cards from then on, and hear that it changed. The images and sounds
    /// the copy's cards refer to come back before the cards do, and those
    /// only the cards it replaces used go, which the copy before the restore
    /// keeps. A copy that a newer version of Ficha migrated is refused, and
    /// nothing changes. One that an older version left is migrated once it's
    /// restored, with a copy before an update, as when the engine opens the
    /// database.
    @discardableResult
    public func restore(_ name: String) throws(EngineError) -> Restoration {
        guard let dataFolder, let backupsFolder else {
            logger.error("An engine in memory has no Backups folder to restore a copy from")
            throw .backupsFolder
        }
        guard let copy = try copies().first(where: { $0.name == name }) else {
            throw .copyNotFound(name)
        }
        // While no other engine opens the database, which could migrate it
        // at the same time.
        let (restoration, replaced) = try whileNoOtherProcessOpens(databaseFile(in: dataFolder)) {
            () throws(EngineError) in
            let source = try reportingStorageErrors {
                var configuration = Configuration()
                configuration.readonly = true
                return try DatabaseQueue(
                    path: backupsFolder.appending(path: name).path(percentEncoded: false), configuration: configuration)
            }
            if try reportingStorageErrors({ try source.read(Schema.migrator.hasBeenSuperseded) }) {
                logger.error("Refused to restore \(name, privacy: .public), which a newer version of Ficha migrated")
                throw .copyMigratedByNewerVersion(name)
            }
            let copyBeforeRestore = try saveCopy(.beforeRestore)
            let replaced = try read(FilesReferred.init(in:))
            try bringBackFiles(
                try reportingStorageErrors { try source.read(FilesReferred.init(in:)) }, from: backupsFolder,
                into: dataFolder)
            try reportingStorageErrors { try source.backup(to: database) }
            try migrate(database, savingACopyIn: backupsFolder, at: time.now)
            return (Restoration(restored: copy, copyBeforeRestore: copyBeforeRestore), replaced)
        }
        removeFilesNoCardUses(images: replaced.images, sounds: replaced.sounds)
        databaseChanges.post()
        logger.notice("Restored \(name, privacy: .public)")
        return restoration
    }

    /// Moves `copies` from the Backups folder to the Trash, where Lucas can
    /// bring them back from, and returns where each one went, in order. A
    /// copy of any kind can go. When one can't, those before it are in the
    /// Trash already, and the rest stay. The images and sounds no remaining
    /// copy refers to go for good: a copy put back from the Trash restores
    /// without those its cards no longer have.
    @discardableResult
    public func moveToTrash(_ copies: [DatabaseCopy]) throws(EngineError) -> [URL] {
        guard let backupsFolder else {
            logger.error("An engine in memory has no Backups folder to move copies from")
            throw .backupsFolder
        }
        var trashed: [URL] = []
        defer {
            if !trashed.isEmpty {
                dropFilesNoCopyUses()
            }
        }
        for copy in copies {
            var inTrash: NSURL?
            do {
                try FileManager.default.trashItem(
                    at: backupsFolder.appending(path: copy.name), resultingItemURL: &inTrash)
            } catch CocoaError.fileNoSuchFile {
                throw .copyNotFound(copy.name)
            } catch {
                logger.error("Couldn't move \(copy.name, privacy: .public) to the Trash: \(String(describing: error))")
                throw .backupsFolder
            }
            if let inTrash {
                trashed.append(inTrash as URL)
            }
        }
        return trashed
    }

    /// Saves a copy of `kind` of the database as it is now in the Backups
    /// folder, at the engine's time, and returns it.
    private func saveCopy(_ kind: DatabaseCopy.Kind) throws(EngineError) -> DatabaseCopy {
        guard let backupsFolder else {
            logger.error("An engine in memory has no Backups folder to save a copy in")
            throw .backupsFolder
        }
        return try FichaData.saveCopy(of: database, as: kind, at: time.now, in: backupsFolder)
    }

    /// Removes `copy` from the Backups folder for good.
    private func removeCopy(_ copy: DatabaseCopy) throws(EngineError) {
        guard let backupsFolder else { return }
        do {
            try FileManager.default.removeItem(at: backupsFolder.appending(path: copy.name))
        } catch {
            logger.error("Couldn't remove the copy \(copy.name, privacy: .public): \(String(describing: error))")
            throw .backupsFolder
        }
    }
}

/// What a restore did: the copy it brought back, and the copy before a
/// restore it saved first, which restoring undoes it.
public struct Restoration: Sendable, Equatable, Encodable {
    public let restored: DatabaseCopy
    public let copyBeforeRestore: DatabaseCopy
}

/// The Backups folder in the data folder `folder`.
func folderOfBackups(in folder: URL) -> URL {
    folder.appending(path: "Backups", directoryHint: .isDirectory)
}

/// Every copy in `folder`, newest first, and of two in the same second, the
/// one saved later first. Files whose names aren't a copy's are left out.
func listCopies(in folder: URL) throws(EngineError) -> [DatabaseCopy] {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
    do {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
        return try files.compactMap { file -> DatabaseCopy? in
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, let size = values.fileSize else {
                return nil
            }
            return DatabaseCopy(name: file.lastPathComponent, size: Int64(size))
        }
        .sorted { ($0.savedAt, $0.number, $0.name) > ($1.savedAt, $1.number, $1.name) }
    } catch CocoaError.fileReadNoSuchFile {
        return []
    } catch {
        logger.error("Couldn't list the copies in the Backups folder: \(String(describing: error))")
        throw .backupsFolder
    }
}

/// Moves the copies before an update that versions of Ficha before backups
/// saved next to the database in `folder`, named after their migration, like
/// `Ficha before v2 cards.sqlite`, into `backups`, the Backups folder, each
/// as a copy before an update saved when its file was last written. One that
/// can't be moved stays where it is, which the log says: Ficha still opens.
/// So does one with a write-ahead log next to it, which may hold part of it.
func moveOldCopiesBeforeAnUpdate(from folder: URL, into backups: URL) {
    let files: [URL]
    do {
        files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
    } catch {
        logger.error("Couldn't look for old copies before an update: \(String(describing: error))")
        return
    }
    for file in files where file.lastPathComponent.hasPrefix("Ficha before ") && file.pathExtension == "sqlite" {
        let name = file.lastPathComponent
        guard !FileManager.default.fileExists(atPath: file.path(percentEncoded: false) + "-wal") else {
            logger.error("Left the old copy \(name, privacy: .public) where it is: a write-ahead log is next to it")
            continue
        }
        do {
            guard let savedAt = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else {
                logger.error("Left the old copy \(name, privacy: .public) where it is: it has no date")
                continue
            }
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            let copy = try moveIntoBackups(file, as: .beforeUpdate, savedAt: savedAt, in: backups)
            logger.notice(
                "Moved the old copy \(name, privacy: .public) into Backups, as \(copy.name, privacy: .public)")
        } catch {
            logger.error("Left the old copy \(name, privacy: .public) where it is: \(String(describing: error))")
        }
    }
}

/// Saves a copy of `database` as it is now in `folder`, the Backups folder of
/// its data folder, as a copy of `kind` saved at `time`, and returns it.
/// SQLite's online backup copies it whole and consistent, even while another
/// process writes. The images and sounds its cards refer to go to those the
/// copies share, from the data folder's Images and Sounds folders. The copy
/// is written under a hidden name first, and then given its own once its
/// files are kept, so a copy that failed halfway never shows as one, and
/// never replaces another.
@discardableResult
func saveCopy(
    of database: any DatabaseWriter, as kind: DatabaseCopy.Kind, at time: Date, in folder: URL
) throws(EngineError) -> DatabaseCopy {
    let file = folder.appending(path: ".\(UUID().uuidString).sqlite")
    // The backup gives the copy the database's write-ahead logging, which
    // leaves files of its own next to the hidden one, until the copy leaves
    // it.
    defer {
        for logFile in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: file.path(percentEncoded: false) + logFile)
        }
    }
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
        logger.error("Couldn't make the Backups folder: \(String(describing: error))")
        throw .backupsFolder
    }
    let files: FilesReferred
    do {
        let copy = try DatabaseQueue(path: file.path(percentEncoded: false))
        try database.backup(to: copy)
        // A file on its own, with no write-ahead log to open it with.
        try copy.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        files = try copy.read(FilesReferred.init(in:))
        try copy.close()
    } catch {
        logger.error("Couldn't save a copy of the database: \(String(describing: error))")
        try? FileManager.default.removeItem(at: file)
        throw .storage
    }
    do throws(EngineError) {
        try shareFiles(files, from: folder.deletingLastPathComponent(), into: folder)
    } catch {
        try? FileManager.default.removeItem(at: file)
        throw error
    }
    return try moveIntoBackups(file, as: kind, savedAt: time, in: folder)
}

/// Moves `file` into `folder` with the name of the copy of `kind` saved at
/// `time`, numbered after the copies of its kind saved in the same second,
/// and returns the copy: a move never replaces a file that's there.
func moveIntoBackups(_ file: URL, as kind: DatabaseCopy.Kind, savedAt time: Date, in folder: URL)
    throws(EngineError) -> DatabaseCopy
{
    do {
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: file])
        }
        var number = 1
        while true {
            let copy = DatabaseCopy(kind, savedAt: time, number: number, size: Int64(size))
            do {
                try FileManager.default.moveItem(at: file, to: folder.appending(path: copy.name))
                return copy
            } catch CocoaError.fileWriteFileExists {
                number += 1
            }
        }
    } catch {
        logger.error("Couldn't name a copy in the Backups folder: \(String(describing: error))")
        throw .backupsFolder
    }
}
