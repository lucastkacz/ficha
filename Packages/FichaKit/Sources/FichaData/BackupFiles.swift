import FichaCore
import Foundation
internal import GRDB

// The files on cards the copies in the Backups folder keep, images and
// sounds, each once for all of them, in a folder of each kind in the Backups
// folder, named as the data folder's: saving a copy adds the files it refers
// to that the folder lacks, deleting copies drops the files no remaining copy
// refers to, and restoring a copy brings back to the data folder the files
// it refers to. One module keeps every kind, so a kind never keeps its files
// in the backups its own way.

extension Engine {
    /// What the images the copies in the Backups folder share weigh, in
    /// bytes: each image once, however many copies refer to it. None for an
    /// engine in memory, which keeps no copies.
    public func sharedImagesSize() throws(EngineError) -> Int64 {
        try sharedSize(of: ImageName.self)
    }

    /// What the sounds the copies in the Backups folder share weigh, in
    /// bytes, as `sharedImagesSize()` weighs the images.
    public func sharedSoundsSize() throws(EngineError) -> Int64 {
        try sharedSize(of: SoundName.self)
    }

    /// Drops from the files the copies share those no copy in the Backups
    /// folder refers to any more, now that copies went: pruned, or moved to
    /// the Trash. One that couldn't be dropped stays, and the log says why:
    /// the copies went all the same. When a copy can't be read, none is
    /// dropped, since it may refer to any of them.
    func dropFilesNoCopyUses() {
        guard let backupsFolder else { return }
        var referred = FilesReferred()
        do throws(EngineError) {
            for copy in try copies() {
                referred.formUnion(try FilesReferred(byCopyIn: backupsFolder.appending(path: copy.name)))
            }
        } catch {
            logger.error(
                "Couldn't read which files the copies use, so none was dropped: \(String(describing: error), privacy: .public)"
            )
            return
        }
        dropShared(keeping: referred.images, in: backupsFolder)
        dropShared(keeping: referred.sounds, in: backupsFolder)
    }

    /// What the files named by `Name` the copies share weigh, in bytes.
    private func sharedSize<Name: NameOfFileOnCard>(of _: Name.Type) throws(EngineError) -> Int64 {
        guard let backupsFolder else {
            return 0
        }
        let folder = folderOfShared(Name.self, in: backupsFolder)
        let key = URLResourceKey.fileSizeKey
        do {
            return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key])
                .filter { Name(rawValue: $0.lastPathComponent) != nil }
                .reduce(0) { total, file in
                    guard let size = try file.resourceValues(forKeys: [key]).fileSize else {
                        throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: file])
                    }
                    return total + Int64(size)
                }
        } catch CocoaError.fileReadNoSuchFile {
            return 0
        } catch {
            logger.error(
                "Couldn't weigh the \(Name.kind, privacy: .public)s the copies share: \(String(describing: error), privacy: .public)"
            )
            throw .backupsFolder
        }
    }

    /// Drops from the files named by `Name` the copies in `backups` share
    /// those not among `referred`, logging why when it can't.
    private func dropShared<Name: NameOfFileOnCard>(keeping referred: Set<Name>, in backups: URL) {
        let shared = FileStore<Name>.folder(folderOfShared(Name.self, in: backups))
        do throws(EngineError) {
            try shared.remove(try shared.names().subtracting(referred))
        } catch {
            logger.error(
                "Couldn't drop the \(Name.kind, privacy: .public)s no copy uses: \(String(describing: error), privacy: .public)"
            )
        }
    }
}

/// The files the cards in a database refer to, of every kind, on either
/// side, as `namesReferred(_:in:)` reads them.
struct FilesReferred: Sendable, Equatable {
    var images: Set<ImageName> = []
    var sounds: Set<SoundName> = []

    /// No file.
    init() {}

    /// The files the cards in `db` refer to.
    init(in db: Database) throws {
        images = try namesReferred(ImageName.self, in: db)
        sounds = try namesReferred(SoundName.self, in: db)
    }

    /// The files the cards in the copy saved in `file` refer to, which it
    /// reads without changing it.
    init(byCopyIn file: URL) throws(EngineError) {
        self = try reportingStorageErrors {
            var configuration = Configuration()
            configuration.readonly = true
            return try DatabaseQueue(path: file.path(percentEncoded: false), configuration: configuration)
                .read(FilesReferred.init(in:))
        }
    }

    /// Adds the files `other` refers to.
    mutating func formUnion(_ other: FilesReferred) {
        images.formUnion(other.images)
        sounds.formUnion(other.sounds)
    }
}

/// The folder in the Backups folder `backups` where the copies keep the
/// files named by `Name` their cards refer to, each once for all of them,
/// named as the data folder's.
func folderOfShared<Name: NameOfFileOnCard>(_: Name.Type, in backups: URL) -> URL {
    folder(of: Name.self, in: backups)
}

/// Adds to the files the copies in the Backups folder `backups` share each
/// of `files` they lack, from the data folder `data`, where the cards keep
/// them. A file on a card is named by its content, so one the copies share
/// is the same file. On APFS, copying a file clones it, which takes no room
/// until either changes, and a file on a card never does. A file the data
/// folder lacks too is left out, and the log says so: the copy keeps the
/// cards all the same, as the database had them.
func shareFiles(_ files: FilesReferred, from data: URL, into backups: URL) throws(EngineError) {
    try shareFiles(files.images, from: data, into: backups)
    try shareFiles(files.sounds, from: data, into: backups)
}

/// Brings back to the data folder `data` each of `files` it lacks, from the
/// files the copies in the Backups folder `backups` share, as a restore does
/// before the cards show up. A file the copies lack too, which a copy saved
/// before copies kept files of its kind can refer to, is left out, and the
/// log says so: its card shows without it.
func bringBackFiles(_ files: FilesReferred, from backups: URL, into data: URL) throws(EngineError) {
    try bringBackFiles(files.images, from: backups, into: data)
    try bringBackFiles(files.sounds, from: backups, into: data)
}

/// Adds the files `names` to those the copies in `backups` share, as
/// `shareFiles(_:from:into:)` says.
private func shareFiles<Name: NameOfFileOnCard>(_ names: Set<Name>, from data: URL, into backups: URL)
    throws(EngineError)
{
    do {
        try copyFiles(names, from: folder(of: Name.self, in: data), into: folderOfShared(Name.self, in: backups)) {
            name in
            logger.error(
                "A copy refers to the \(Name.kind, privacy: .public) \(name.rawValue, privacy: .public), which isn't in \(Name.folderName, privacy: .public)"
            )
        }
    } catch {
        logger.error(
            "Couldn't keep a copy's \(Name.kind, privacy: .public)s in the Backups folder: \(String(describing: error))"
        )
        throw .backupsFolder
    }
}

/// Brings back the files `names` to the data folder `data`, as
/// `bringBackFiles(_:from:into:)` says.
private func bringBackFiles<Name: NameOfFileOnCard>(_ names: Set<Name>, from backups: URL, into data: URL)
    throws(EngineError)
{
    do {
        try copyFiles(names, from: folderOfShared(Name.self, in: backups), into: folder(of: Name.self, in: data)) {
            name in
            logger.error(
                "A restored copy refers to the \(Name.kind, privacy: .public) \(name.rawValue, privacy: .public), which no copy keeps"
            )
        }
    } catch {
        logger.error(
            "Couldn't bring back a restored copy's \(Name.kind, privacy: .public)s: \(String(describing: error))")
        throw Name.folderError
    }
}

/// Copies into `folder` each of `names` it lacks, from `source`, making
/// `folder` when there's one to copy. One `source` lacks too is left out,
/// and `missing` is told its name.
private func copyFiles<Name: NameOfFileOnCard>(
    _ names: Set<Name>, from source: URL, into folder: URL, missing: (Name) -> Void
) throws {
    let lacking = names.filter {
        !FileManager.default.fileExists(atPath: folder.appending(path: $0.rawValue).path(percentEncoded: false))
    }
    guard !lacking.isEmpty else { return }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in lacking.sorted(by: { $0.rawValue < $1.rawValue }) {
        let file = source.appending(path: name.rawValue)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            missing(name)
            continue
        }
        try copyFile(file, into: folder)
    }
}

/// Copies the file on a card `file` into `folder`, unless a file with its
/// name is there already. It's copied under a hidden name first, and then
/// given its own, so a file copied halfway never shows as one.
private func copyFile(_ file: URL, into folder: URL) throws {
    let destination = folder.appending(path: file.lastPathComponent)
    guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else { return }
    let hidden = folder.appending(path: ".\(UUID().uuidString)")
    try FileManager.default.copyItem(at: file, to: hidden)
    do {
        try FileManager.default.moveItem(at: hidden, to: destination)
    } catch CocoaError.fileWriteFileExists {
        // Another process copied it in the meantime: the same file.
        try FileManager.default.removeItem(at: hidden)
    } catch {
        try? FileManager.default.removeItem(at: hidden)
        throw error
    }
}
