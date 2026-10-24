import FichaCore
import Foundation
internal import GRDB

// The images the copies in the Backups folder keep, each once for all of
// them, in an Images folder of the Backups folder's own: saving a copy adds
// the images it refers to that the folder lacks, deleting copies drops the
// images no remaining copy refers to, and restoring a copy brings back to the
// cards' Images folder the images it refers to.

extension Engine {
    /// What the images the copies in the Backups folder share weigh, in
    /// bytes: each image once, however many copies refer to it. None for an
    /// engine in memory, which keeps no copies.
    public func sharedImagesSize() throws(EngineError) -> Int64 {
        guard let backupsFolder else {
            return 0
        }
        let folder = folderOfSharedImages(in: backupsFolder)
        let key = URLResourceKey.fileSizeKey
        do {
            return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key])
                .filter { ImageName(rawValue: $0.lastPathComponent) != nil }
                .reduce(0) { total, file in
                    guard let size = try file.resourceValues(forKeys: [key]).fileSize else {
                        throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: file])
                    }
                    return total + Int64(size)
                }
        } catch CocoaError.fileReadNoSuchFile {
            return 0
        } catch {
            logger.error("Couldn't weigh the images the copies share: \(String(describing: error), privacy: .public)")
            throw .backupsFolder
        }
    }

    /// Drops from the images the copies share those no copy in the Backups
    /// folder refers to any more, now that copies went: pruned, or moved to
    /// the Trash. One that couldn't be dropped stays, and the log says why:
    /// the copies went all the same. When a copy can't be read, none is
    /// dropped, since it may refer to any of them.
    func dropImagesNoCopyUses() {
        guard let backupsFolder else { return }
        let shared = FileStore<ImageName>.folder(folderOfSharedImages(in: backupsFolder))
        do throws(EngineError) {
            var referred: Set<ImageName> = []
            for copy in try copies() {
                referred.formUnion(try imagesReferred(byCopyIn: backupsFolder.appending(path: copy.name)))
            }
            try shared.remove(try shared.names().subtracting(referred))
        } catch {
            logger.error("Couldn't drop the images no copy uses: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Every image the cards in the copy saved in `file` refer to, which it
/// reads without changing it.
func imagesReferred(byCopyIn file: URL) throws(EngineError) -> Set<ImageName> {
    try reportingStorageErrors {
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: file.path(percentEncoded: false), configuration: configuration)
            .read(imagesReferred(in:))
    }
}

/// The folder in the Backups folder `backups` where the copies keep the
/// images their cards refer to, each once for all of them.
func folderOfSharedImages(in backups: URL) -> URL {
    backups.appending(path: "Images", directoryHint: .isDirectory)
}

/// Adds to `shared`, the copies' images folder, each of `images` it lacks,
/// from `live`, the cards' Images folder. An image is named by its content,
/// so one `shared` has is the same image. On APFS, copying a file clones it,
/// which takes no room until either changes, and an image never does. An
/// image `live` lacks too is left out, and the log says so: the copy keeps
/// the cards all the same, as the database had them.
func shareImages(_ images: Set<ImageName>, from live: URL, into shared: URL) throws(EngineError) {
    do {
        try copyImages(images, from: live, into: shared) { image in
            logger.error("A copy refers to the image \(image.rawValue, privacy: .public), which isn't in Images")
        }
    } catch {
        logger.error("Couldn't keep a copy's images in the Backups folder: \(String(describing: error))")
        throw .backupsFolder
    }
}

/// Brings back to `live`, the cards' Images folder, each of `images` it
/// lacks, from `shared`, the copies' images folder, as a restore does before
/// the cards show up. An image `shared` lacks too, which a copy saved before
/// copies kept images can refer to, is left out, and the log says so: its
/// card shows without it.
func bringBackImages(_ images: Set<ImageName>, from shared: URL, into live: URL) throws(EngineError) {
    do {
        try copyImages(images, from: shared, into: live) { image in
            logger.error(
                "A restored copy refers to the image \(image.rawValue, privacy: .public), which no copy keeps")
        }
    } catch {
        logger.error("Couldn't bring back a restored copy's images: \(String(describing: error))")
        throw .imagesFolder
    }
}

/// Copies into `folder` each of `images` it lacks, from `source`, making
/// `folder` when there's one to copy. An image `source` lacks too is left
/// out, and `missing` is told its name.
private func copyImages(_ images: Set<ImageName>, from source: URL, into folder: URL, missing: (ImageName) -> Void)
    throws
{
    guard !images.isEmpty else { return }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for image in images.sorted(by: { $0.rawValue < $1.rawValue }) {
        let file = source.appending(path: image.rawValue)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            missing(image)
            continue
        }
        try copyImage(file, into: folder)
    }
}

/// Copies the image file `file` into `folder`, unless an image with its name
/// is there already. It's copied under a hidden name first, and then given
/// its own, so an image copied halfway never shows as one.
private func copyImage(_ file: URL, into folder: URL) throws {
    let destination = folder.appending(path: file.lastPathComponent)
    guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else { return }
    let hidden = folder.appending(path: ".\(UUID().uuidString)")
    try FileManager.default.copyItem(at: file, to: hidden)
    do {
        try FileManager.default.moveItem(at: hidden, to: destination)
    } catch CocoaError.fileWriteFileExists {
        // Another process copied it in the meantime: the same image.
        try FileManager.default.removeItem(at: hidden)
    } catch {
        try? FileManager.default.removeItem(at: hidden)
        throw error
    }
}
