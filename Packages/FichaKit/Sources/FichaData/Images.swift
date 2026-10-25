import CoreGraphics
import CryptoKit
import FichaCore
import Foundation
internal import GRDB
import ImageIO
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
        try images.keep(image.data, as: image.name)
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
}

/// The Images folder in the data folder `folder`, where the engine keeps the
/// images on cards, beside the database and the Backups folder.
func folderOfImages(in folder: URL) -> URL {
    FichaData.folder(of: ImageName.self, in: folder)
}

/// Every image the cards in `db` refer to, on either side, as
/// `namesReferred(_:in:)` reads them.
func imagesReferred(in db: Database) throws -> Set<ImageName> {
    try namesReferred(ImageName.self, in: db)
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
    /// metadata, such as where a photo was taken, in its color space when the
    /// system names it, such as sRGB or Display P3, and otherwise in Display
    /// P3 when its colors go past sRGB's, or in sRGB. It's named by the
    /// SHA-256 of what's written. Something the system can't read as an image
    /// is refused.
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
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw .notAnImage
        }
        let isTransparent = hasTransparency(thumbnail)
        guard let image = inNamedColorSpace(thumbnail, keepingAlpha: isTransparent) else {
            logger.error(
                "Core Graphics couldn't draw an image of \(thumbnail.width)×\(thumbnail.height) pixels in Display P3 or sRGB"
            )
            throw .notAnImage
        }
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

/// `image` itself when the system names its color space, such as sRGB or
/// Display P3, and otherwise `image` drawn in Display P3 when its colors go
/// past sRGB's, as a photo's in Adobe RGB do, or in sRGB, with its alpha
/// when `keepingAlpha`; nil when it can't be drawn. ImageIO writes the
/// profile of a space the system doesn't name, such as the one a PNG's gamma
/// and chromaticities make, with the day's date in it, so the same image
/// would be written, and named, apart on another day. Display P3 keeps most
/// of the colors a wider space has, and sRGB is what a browser assumes of an
/// image that names no space.
private func inNamedColorSpace(_ image: CGImage, keepingAlpha: Bool) -> CGImage? {
    guard let space = image.colorSpace, space.name == nil else {
        return image
    }
    let alpha: CGImageAlphaInfo = keepingAlpha ? .premultipliedLast : .noneSkipLast
    guard let named = CGColorSpace(name: space.isWideGamutRGB ? CGColorSpace.displayP3 : CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: named,
            bitmapInfo: alpha.rawValue)
    else {
        return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
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
