import CoreGraphics
import CryptoKit
import FichaCore
import Foundation
internal import GRDB
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// The longest side, in pixels, an image keeps once it comes in: sharp on the
/// review panel and in the Cards window, and light, some 200 to 300 KB, for
/// the cards, the backups and later iCloud.
let longestImageSide = 1600

extension Engine {
    /// Brings in an image for a side of a card, as a form or an import does:
    /// shrinks it to `longestImageSide` pixels on its long side, unless it's
    /// smaller, keeps it where Ficha keeps images, and returns the name a
    /// card's side refers to it by. The same image coming in twice is kept
    /// once. Something that isn't an image Ficha can read is refused.
    public func addImage(_ data: Data) throws(EngineError) -> ImageName {
        let image = try CardImage(shrinking: data)
        try keepImage(image)
        return image.name
    }

    /// Keeps `image` where Ficha keeps images, unless it's there already.
    func keepImage(_ image: CardImage) throws(EngineError) {
        try images.keep(image)
    }

    /// The image named `name`, as Ficha keeps it: a JPEG, or a PNG for an
    /// image with transparency.
    public func image(_ name: ImageName) throws(EngineError) -> Data {
        try images.data(of: name)
    }

    /// Every image Ficha keeps, by name, whether a card uses it or not.
    func keptImages() throws(EngineError) -> Set<ImageName> {
        try images.names()
    }

    /// Removes the images among `names` that no card refers to any more, now
    /// that a change let go of them, such as deleting a card or replacing
    /// its image. One that couldn't be removed stays, and the engine logs
    /// why: the change is saved all the same.
    func removeImagesNoCardUses(among names: Set<ImageName>) {
        guard !names.isEmpty else { return }
        do throws(EngineError) {
            let unused = try read { db in try names.subtracting(imagesReferred(in: db)) }
            try images.remove(unused)
        } catch {
            logger.error("Couldn't remove the images no card uses: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Every image the cards in `db` refer to, on either side: none for a
/// database from before images on cards, such as an old backup. A name that
/// isn't an image's fails, as a card the engine never saved.
func imagesReferred(in db: Database) throws -> Set<ImageName> {
    let columns = try db.columns(in: "card").map(\.name)
    guard columns.contains("frontImage"), columns.contains("backImage") else {
        return []
    }
    let names = try String.fetchAll(
        db,
        sql: """
            SELECT frontImage FROM card WHERE frontImage IS NOT NULL
            UNION SELECT backImage FROM card WHERE backImage IS NOT NULL
            """)
    return try Set(
        names.map { name in
            guard let image = ImageName(rawValue: name) else {
                throw unreadable("A card has an image that isn't named as Ficha names them")
            }
            return image
        })
}

/// An image on its way to a side of a card, shrunk as every image that comes
/// in, with the name it's kept by.
struct CardImage: Sendable, Equatable {
    let name: ImageName
    /// The image as Ficha keeps it: a JPEG, or a PNG for an image with
    /// transparency.
    let data: Data

    /// The image `data`, which came in shrunk and named `name` already.
    init(name: ImageName, data: Data) {
        self.name = name
        self.data = data
    }

    /// The image in `data`, in any format the system reads, such as a JPEG, a
    /// PNG, a HEIC or a TIFF, turned upright as its orientation says,
    /// shrunk to `longestImageSide` pixels on its long side, never grown, and
    /// written as a JPEG, or a PNG when it has transparency, without its
    /// metadata, such as where a photo was taken. It's named by the SHA-256 of
    /// what's written. Something the system can't read as an image is
    /// refused.
    init(shrinking data: Data) throws(EngineError) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw .notAnImage
        }
        // Downsampling with a thumbnail, as Apple's "Image and Graphics Best
        // Practices" (WWDC 2018) does, decodes only what the smaller image
        // needs.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longestImageSide, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw .notAnImage
        }
        let isTransparent = hasTransparency(image)
        let written = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                written, (isTransparent ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)
        else {
            logger.error("ImageIO couldn't start writing an image")
            throw .notAnImage
        }
        let quality: [CFString: Any] = isTransparent ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, quality as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            logger.error("ImageIO couldn't write an image of \(image.width)×\(image.height) pixels")
            throw .notAnImage
        }
        self.data = written as Data
        let hash = SHA256.hash(data: self.data).map { String(format: "%02x", $0) }.joined()
        guard let name = ImageName(rawValue: "\(hash).\(isTransparent ? "png" : "jpg")") else {
            logger.error("An image's SHA-256 didn't make an image's name")
            throw .notAnImage
        }
        self.name = name
    }
}

/// Whether `image` has a pixel that isn't fully opaque. One with an alpha
/// channel is checked pixel by pixel, since many opaque images have one; one
/// that can't be checked counts as transparent, so it keeps its alpha.
private func hasTransparency(_ image: CGImage) -> Bool {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
        return false
    case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
        break
    @unknown default:
        break
    }
    let width = image.width
    let height = image.height
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        return true
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let pixels = context.data else {
        return true
    }
    let bytes = UnsafeBufferPointer(start: pixels.assumingMemoryBound(to: UInt8.self), count: width * height * 4)
    return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] < 255 }
}

/// Where the engine keeps the images on cards, each once, by its name: an
/// Images folder beside the database, with a file for each, or memory, for
/// an engine in memory.
enum ImageStore: Sendable {
    case folder(URL)
    case memory(ImagesInMemory)

    /// Keeps `image`, unless an image with its name is kept already: being
    /// named by its content, it's the same image.
    func keep(_ image: CardImage) throws(EngineError) {
        switch self {
        case .folder(let folder):
            let file = folder.appending(path: image.name.rawValue)
            guard !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }
            try reportingImageErrors {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try image.data.write(to: file, options: .atomic)
            }
        case .memory(let memory):
            memory.images.withLock { $0[image.name] = image.data }
        }
    }

    /// The image named `name`, or an error when it isn't kept.
    func data(of name: ImageName) throws(EngineError) -> Data {
        switch self {
        case .folder(let folder):
            try reportingImageErrors { try Data(contentsOf: folder.appending(path: name.rawValue)) }
        case .memory(let memory):
            try memory.images.withLock { images throws(EngineError) in
                guard let data = images[name] else {
                    logger.error("No image named \(name.rawValue, privacy: .public) is kept in memory")
                    throw .imagesFolder
                }
                return data
            }
        }
    }

    /// Every image kept, by name.
    func names() throws(EngineError) -> Set<ImageName> {
        switch self {
        case .folder(let folder):
            guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
            let files = try reportingImageErrors {
                try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            }
            return Set(files.compactMap(ImageName.init(rawValue:)))
        case .memory(let memory):
            return memory.images.withLock { Set($0.keys) }
        }
    }

    /// Removes the images named `names`, those kept: one that isn't is
    /// already gone.
    func remove(_ names: Set<ImageName>) throws(EngineError) {
        switch self {
        case .folder(let folder):
            for name in names {
                let file = folder.appending(path: name.rawValue)
                guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
                try reportingImageErrors { try FileManager.default.removeItem(at: file) }
            }
        case .memory(let memory):
            memory.images.withLock { images in
                for name in names {
                    images[name] = nil
                }
            }
        }
    }
}

/// The images of an engine in memory, gone with it.
final class ImagesInMemory: Sendable {
    let images = Mutex<[ImageName: Data]>([:])
}

/// Runs `work` on the Images folder, and when it fails, logs why and throws
/// the engine's error, whose message the user can read.
private func reportingImageErrors<Value>(_ work: () throws -> Value) throws(EngineError) -> Value {
    do {
        return try work()
    } catch {
        logger.error("The Images folder failed: \(String(describing: error), privacy: .public)")
        throw .imagesFolder
    }
}
