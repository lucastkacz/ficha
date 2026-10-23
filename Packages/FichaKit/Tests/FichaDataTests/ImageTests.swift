import CoreGraphics
import FichaCore
import Foundation
import GRDB
import ImageIO
import Testing
import UniformTypeIdentifiers

// For the images the engine keeps, which #220's backups keep too.
@testable import FichaData

/// Tests on images on cards: each side holds text, an image, or both, and
/// Ficha keeps each image once, shrunk as it comes in, until no card uses it.
final class ImageTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    /// A data folder of the test's own, for the tests on the Images folder,
    /// which the engine creates when it first opens it.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaImageTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("the same image added twice is kept once, beside the database, and reads back as it was kept")
    func theSameImageAddedTwiceIsKeptOnce() throws {
        let engine = try Engine(location: .folder(folder), time: time)
        let bird = try picture(width: 2400, height: 1800, red: 0.8)

        let first = try engine.addImage(bird)
        let kept = try engine.image(first)
        let second = try engine.addImage(bird)
        let other = try engine.addImage(picture(width: 2400, height: 1800, red: 0.3))

        #expect(second == first)
        #expect(other != first)
        #expect(try engine.keptImages() == [first, other])
        #expect(try Engine(location: .folder(folder), time: time).image(first) == kept)
    }

    @Test("a card can have an image on its front, its back, both, or a side with only an image")
    func aCardCanHaveImagesOnItsSides() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 600, height: 800, red: 0.3))

        let onFront = try engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let onBack = try engine.create(card(nil, front: "hornero", back: "Su nido es de barro.", backImage: nest))
        let onBoth = try engine.create(
            card(nil, front: "¿De quién es?", back: "Del hornero.", frontImage: nest, backImage: bird))
        let onlyAnImage = try engine.create(card(nil, front: "  ", back: "Un hornero.", frontImage: bird))

        #expect([onFront, onBack, onBoth, onlyAnImage].map(\.frontImage) == [bird, nil, nest, bird])
        #expect([onFront, onBack, onBoth, onlyAnImage].map(\.backImage) == [nil, nest, bird, nil])
        #expect(onlyAnImage.front == "")
        #expect(try engine.cards() == [onFront, onBack, onBoth, onlyAnImage])
        #expect(CardContent(type: nil, front: "  ", back: "Un hornero.", tags: [], source: nil) == nil)
        #expect(
            CardContent(type: nil, front: "¿Qué pájaro es?", back: " ", tags: [], source: nil, frontImage: bird) == nil)
    }

    @Test("an image that comes in is at most about 1,600 pixels on its long side, and a smaller one keeps its size")
    func anImageThatComesInIsShrunk() throws {
        let engine = try Engine(location: .inMemory, time: time)

        let wide = try engine.addImage(picture(width: 4000, height: 3000))
        let tall = try engine.addImage(picture(width: 1000, height: 2400))
        let small = try engine.addImage(picture(width: 640, height: 480))

        #expect(try pixelSize(of: engine.image(wide)) == (1600, 1200))
        #expect(try pixelSize(of: engine.image(tall)) == (667, 1600))
        #expect(try pixelSize(of: engine.image(small)) == (640, 480))
    }

    @Test("an image comes in as a JPEG, or as a PNG when it has transparency")
    func anImageComesInAsAJPEGOrAPNG() throws {
        let engine = try Engine(location: .inMemory, time: time)

        let opaque = try engine.addImage(picture(width: 300, height: 200))
        let seeThrough = try engine.addImage(picture(width: 300, height: 200, alpha: 0.5))

        #expect(opaque.rawValue.hasSuffix(".jpg"))
        #expect(try imageType(of: engine.image(opaque)) == UTType.jpeg.identifier)
        #expect(seeThrough.rawValue.hasSuffix(".png"))
        #expect(try imageType(of: engine.image(seeThrough)) == UTType.png.identifier)
    }

    @Test("deleting the only card that uses an image deletes it, and one another card uses stays")
    func deletingACardDeletesTheImagesNoOtherCardUses() throws {
        let engine = try Engine(location: .folder(folder), time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let hornero = try engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backImage: nest))
        let nido = try engine.create(
            card(nil, front: "¿De quién es este nido?", back: "Del hornero.", frontImage: nest))

        try engine.delete([hornero.id])

        #expect(try engine.keptImages() == [nest])
        #expect(throws: EngineError.imagesFolder) {
            try engine.image(bird)
        }
        try engine.delete([nido.id])
        #expect(try engine.keptImages().isEmpty)
    }

    @Test("replacing or removing a side's image deletes the old one once no card uses it")
    func replacingAnImageDeletesTheOldOne() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let egg = try engine.addImage(picture(width: 800, height: 600, red: 0.1))
        let hornero = try engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backImage: nest))
        try engine.create(card(nil, front: "¿De quién es este nido?", back: "Del hornero.", frontImage: nest))

        let edited = try engine.edit(
            hornero.id, with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: egg))

        #expect(edited.frontImage == egg)
        #expect(edited.backImage == nil)
        #expect(try engine.keptImages() == [nest, egg])
    }

    // A refine session drafts text alone: `ficha fix` and `ficha
    // approve-expansion` never add an image, nor take one away.
    @Test("fixing or changing a card's text through the CLI keeps its images")
    func theCLIKeepsACardsImages() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let flagged = try engine.create(card(.word, front: "hornero", back: "Un pájaro.", frontImage: bird))
        let expanded = try engine.create(
            card(.word, front: "nido", back: "Donde nace un pájaro.", frontImage: nest, backImage: bird))
        try engine.flag(flagged.id, note: note("Decir que hace su nido de barro"))
        let expansion = try engine.expand(text: "nido", note: "También el de las avispas", source: nil)
        #expect(expansion.expandsCardID == expanded.id)

        let fixed = try engine.fix(
            flagged.id, with: card(.word, front: "hornero", back: "Un pájaro que hace su nido de barro."))
        let approved = try engine.approveExpansion(
            expansion.id, into: card(.word, front: "nido", back: "Donde nace un pájaro, o viven las avispas."))

        #expect(fixed.back == "Un pájaro que hace su nido de barro.")
        #expect(fixed.frontImage == bird && fixed.backImage == nil)
        #expect(approved.back == "Donde nace un pájaro, o viven las avispas.")
        #expect(approved.frontImage == nest && approved.backImage == bird)
        #expect(try engine.keptImages() == [bird, nest])
    }

    // As `ficha cards` prints a card, so a refine session knows it has one.
    @Test("a card's encoding has frontImage and backImage only when set, by name")
    func aCardsEncodingNamesItsImages() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let withImage = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let withNone = try engine.create(card(nil, front: "hornero", back: "Un pájaro."))

        let encoded = try [withImage, withNone].map { card in
            try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        }

        #expect(encoded[0]["frontImage"] as? String == bird.rawValue)
        #expect(encoded[0]["backImage"] == nil)
        #expect(encoded[1]["frontImage"] == nil)
        #expect(encoded[1]["backImage"] == nil)
    }

    @Test("a front with only an image repeats no other card's front")
    func aFrontWithOnlyAnImageRepeatsNone() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        try engine.create(card(nil, front: "", back: "Un hornero.", frontImage: bird))

        #expect(try engine.cardRepeated(byFront: "") == nil)
        #expect(try engine.create(card(nil, front: "", back: "Un nido.", frontImage: nest)).frontImage == nest)
    }

    // An older backup is such a database too, which #220's backups ask.
    @Test("a database from before images on cards migrates with its cards as they were, and refers to no image")
    func aDatabaseFromBeforeImagesRefersToNone() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Ficha.sqlite")
        try saveDatabaseBeforeOptionalTypes(at: file, at: time.now)
        let old = try DatabaseQueue(path: file.path(percentEncoded: false))
        #expect(try old.read(imagesReferred(in:)).isEmpty)
        try old.close()

        let engine = try Engine(location: .folder(folder), time: time)

        try expectEveryCardAsItWasBeforeOptionalTypes(in: engine, at: time.now)
        #expect(try engine.cards().allSatisfy { $0.frontImage == nil && $0.backImage == nil })
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try engine.edit(1, with: card(.word, front: "serendipia", back: "Un hallazgo.", backImage: bird))
        #expect(try engine.read(imagesReferred(in:)) == [bird])
    }

    @Test("what isn't an image doesn't come in")
    func whatIsntAnImageDoesntComeIn() throws {
        let engine = try Engine(location: .inMemory, time: time)

        #expect(throws: EngineError.notAnImage) {
            try engine.addImage(Data("un hornero".utf8))
        }
    }
}

/// A picture `width` by `height` pixels in one color, as a PNG, opaque unless
/// `alpha` is under 1: a test's own image. Pictures of other colors or sizes
/// are other images.
func picture(width: Int, height: Int, red: Double = 0.5, alpha: Double = 1) throws -> Data {
    let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(srgbRed: red, green: 0.6, blue: 0.4, alpha: alpha))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// The width and height in pixels of the image in `data`.
func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (image.width, image.height)
}

/// The format of the image in `data`, as its uniform type identifier.
func imageType(of data: Data) throws -> String {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceGetType(source)) as String
}
