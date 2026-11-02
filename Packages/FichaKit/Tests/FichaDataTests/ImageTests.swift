import CoreGraphics
import FichaCore
import FichaSVG
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

    // ImageIO writes the profile of a color space the system doesn't name,
    // such as the one a PNG's gamma and chromaticities make, as Wikipedia's
    // images often have, with the day's date in it. A PNG in Adobe RGB reads
    // back in such a space.
    @Test(
        "an image comes in in its color space when the system names it, and otherwise in Display P3 when its colors are wider than sRGB's, or in sRGB, so it's named the same whatever day it comes in"
    )
    func anImageComesInInANamedColorSpace() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let gamma22 = try #require(
            CGColorSpace(
                calibratedRGBWhitePoint: [0.9505, 1, 1.089], blackPoint: [0, 0, 0], gamma: [2.2, 2.2, 2.2],
                matrix: [0.4124, 0.2126, 0.0193, 0.3576, 0.7152, 0.1192, 0.1805, 0.0722, 0.9505]))
        let adobeRGB = try #require(CGColorSpace(name: CGColorSpace.adobeRGB1998))
        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))

        let opaque = try engine.addImage(picture(width: 300, height: 200, in: gamma22))
        let seeThrough = try engine.addImage(picture(width: 300, height: 200, alpha: 0.5, in: gamma22))
        let wider = try engine.addImage(picture(width: 300, height: 200, in: adobeRGB))
        let named = try engine.addImage(picture(width: 300, height: 200, in: displayP3))

        #expect(
            try [opaque, seeThrough, wider, named].map { try colorSpaceName(of: engine.image($0)) } == [
                CGColorSpace.sRGB as String, CGColorSpace.sRGB as String, CGColorSpace.displayP3 as String,
                CGColorSpace.displayP3 as String,
            ])
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

    // A content alone, as from a refine session's draft that leaves the
    // images out. Drafts that put or take them off are in
    // RefiningWithFilesTests.
    @Test("fixing or expanding a card with a content alone keeps its images")
    func fixingOrExpandingWithAContentAloneKeepsACardsImages() throws {
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

    // A text file without image columns gives a card text alone. A zip's
    // back images are in ImagesInZipsTests.
    @Test("an import that updates a card keeps its images")
    func anImportThatUpdatesACardKeepsItsImages() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let hornero = try engine.create(
            card(.word, front: "hornero", back: "Un pájaro.", frontImage: bird, backImage: nest))
        let file = folder.appending(path: "pájaros.txt")
        try Data("hornero\tUn pájaro que hace su nido de barro.\n".utf8).write(to: file)

        let outcome = try await engine.importCards(engine.previewImport(of: file), choosing: ImportChoices())

        #expect(outcome.updated == 1)
        let updated = try #require(try engine.cards().first { $0.id == hornero.id })
        #expect(updated.back == "Un pájaro que hace su nido de barro.")
        #expect(updated.frontImage == bird && updated.backImage == nest)
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

    @Test("a front with only an image repeats no other card's front in the Cards window's form")
    func aFrontWithOnlyAnImageRepeatsNone() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        try engine.create(card(nil, front: "", back: "Un hornero.", frontImage: bird))

        #expect(try engine.frontsInUse().cardID(repeatedBy: "") == nil)
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

    @Test("the review panel shows the images of the cards it brings")
    func theReviewPanelShowsTheCardsImages() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let hornero = try engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backImage: nest))
        try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))

        let panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(.defaults), settings: .defaults)

        #expect(panel.content == .upperSide(hornero, isNew: true))
        #expect(try panel.images[bird]?.get() == engine.image(bird))
        #expect(try panel.images[nest]?.get() == engine.image(nest))
    }

    @Test("what isn't an image doesn't come in")
    func whatIsntAnImageDoesntComeIn() throws {
        let engine = try Engine(location: .inMemory, time: time)

        #expect(throws: EngineError.notAnImage) {
            try engine.addImage(Data("un hornero".utf8))
        }
    }

    // So that a card whose front is an SVG repeats its own when its deck is
    // imported again.
    @Test("an SVG is drawn the same, and named the same, whatever was drawn before it")
    func anSVGIsDrawnTheSame() throws {
        let first = InProcessSVGDrawer()
        let second = InProcessSVGDrawer()
        let moon = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><circle cx="50" cy="50" r="40"/></svg>
            """.utf8)

        let sun = try CardImage(drawing: sunSVG, with: first)
        _ = try CardImage(drawing: moon, with: second)

        #expect(try CardImage(drawing: sunSVG, with: second) == sun)
    }

    // WebKit draws on the main thread, which an import leaves free, as the
    // app runs it away from the main actor; on it, an SVG isn't drawn, rather
    // than waiting on itself.
    @MainActor
    @Test("an SVG isn't drawn on the main thread")
    func anSVGIsntDrawnOnTheMainThread() {
        #expect(throws: EngineError.notAnImage) {
            try CardImage(drawing: sunSVG, with: InProcessSVGDrawer())
        }
    }
}

/// A picture `width` by `height` pixels in one color, as a PNG, opaque unless
/// `alpha` is under 1, in the color space `space`, or sRGB: a test's own
/// image. Pictures of other colors or sizes are other images.
func picture(width: Int, height: Int, red: Double = 0.5, alpha: Double = 1, in space: CGColorSpace? = nil) throws
    -> Data
{
    let space = try space ?? #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
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

/// The color of the pixel `x` across and `y` down the image in `data`, as
/// its red, green and blue in sRGB, from 0 to 255.
func color(of data: Data, atX x: Int, y: Int) throws -> [Int] {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
        CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    // Core Graphics counts rows up from the bottom.
    context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    let pixel = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    return (0..<3).map { Int(pixel[$0]) }
}

/// Whether `color` is `expected`, give or take what converting its colors changes.
func isNear(_ color: [Int], _ expected: [Int]) -> Bool {
    color.count == expected.count && zip(color, expected).allSatisfy { abs($0 - $1) <= 8 }
}

/// An SVG of a sun, 300 by 200: a yellow circle on nothing, a test's own.
let sunSVG = Data(
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="300" height="200">\
    <circle cx="150" cy="100" r="80" fill="#f2b400"/></svg>
    """.utf8)

/// The format of the image in `data`, as its uniform type identifier.
func imageType(of data: Data) throws -> String {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceGetType(source)) as String
}

/// The name of the color space of the image in `data`, or nil when the
/// system names none for it.
private func colorSpaceName(of data: Data) throws -> String? {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return image.colorSpace?.name as String?
}
