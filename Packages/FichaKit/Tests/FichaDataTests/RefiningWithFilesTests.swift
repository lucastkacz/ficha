import AVFoundation
import FichaCore
import Foundation
import Testing

// For the images and sounds the engine keeps, as ImageTests and SoundTests
// read them.
@testable import FichaData

/// Tests on the images and sounds a refine session puts on cards through the
/// `ficha` CLI: approving and fixing cards with a file for a side, given by
/// its path or by the name Ficha holds it by, and putting one on, or taking
/// one off, a side of any card.
final class RefiningWithFilesTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    /// A folder of the test's own, for the files it gives by their path.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaRefiningWithFilesTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("approving a capture puts on each side the image or the sound a file holds, shrunk or converted")
    func approvingPutsFilesFromTheirPaths() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("coloratura")
        let photo = try file("soprano.png", holding: picture(width: 2400, height: 1200, red: 0.8))
        let excerpt = try file("coloratura.wav", holding: tone(seconds: 1, hertz: 440))

        let cards = try await engine.approve(
            capture.id,
            into: [
                draft(
                    .word, front: "coloratura", back: "Los ornamentos rápidos del canto.",
                    frontImage: .put(.file(photo)), backSound: .put(.file(excerpt))),
                draft(.concept, front: "aria", back: "Una canción de una ópera."),
            ])

        #expect(cards.map(\.front) == ["coloratura", "aria"])
        let image = try #require(cards[0].frontImage)
        let sound = try #require(cards[0].backSound)
        #expect(cards[0].backImage == nil && cards[0].frontSound == nil)
        #expect(cards[1].images.isEmpty && cards[1].sounds.isEmpty)
        let size = try pixelSize(of: engine.image(image))
        #expect(size.width == 1600 && size.height == 800)
        #expect(try soundFormat(of: engine.sound(sound)).id == kAudioFormatMPEG4AAC)
        #expect(try engine.keptImages() == [image])
        #expect(try engine.keptSounds() == [sound])
    }

    // As a refine session copies a card from `ficha cards`, which names its
    // files.
    @Test("approving a capture puts on a side an image or a sound Ficha holds, by its name, and refuses one it doesn't")
    func approvingPutsFilesByTheirNames() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let la = try await addTone(440, to: engine)
        let unknown = try #require(SoundName(rawValue: String(repeating: "a", count: 64) + ".m4a"))
        let capture = try engine.newCapture("hornero")

        await #expect(throws: EngineError.noFileNamed(unknown.rawValue)) {
            try await engine.approve(
                capture.id,
                into: [
                    draft(
                        nil, front: "", back: "Un hornero.", frontImage: .put(.image(bird)),
                        backSound: .put(.sound(unknown)))
                ])
        }
        let cards = try await engine.approve(
            capture.id,
            into: [
                draft(nil, front: "", back: "Un hornero.", frontImage: .put(.image(bird)), backSound: .put(.sound(la)))
            ])

        #expect(cards.map(\.front) == [""])
        #expect(cards.map(\.frontImage) == [bird])
        #expect(cards.map(\.backSound) == [la])
        #expect(try engine.inbox().captures.isEmpty)
    }

    @Test(
        "fixing a card keeps the images and sounds it leaves out, takes off those it gives as null, and puts those it gives"
    )
    func fixingChangesTheFilesItGives() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let hornero = try engine.create(
            card(
                .word, front: "hornero", back: "Un pájaro.", frontImage: bird, backImage: nest, frontSound: la,
                backSound: mi))
        try engine.flag(hornero.id, note: note("Poner su canto"))
        let song = try file("canto.wav", holding: tone(seconds: 1, hertz: 523))
        time.advance(by: 60)

        let fixed = try await engine.fix(
            hornero.id,
            with: draft(
                .word, front: "hornero", back: "Un pájaro que hace su nido de barro.", backImage: .remove,
                backSound: .put(.file(song))))

        #expect(fixed.back == "Un pájaro que hace su nido de barro.")
        #expect(fixed.frontImage == bird && fixed.backImage == nil)
        #expect(fixed.frontSound == la)
        let canto = try #require(fixed.backSound)
        #expect(![la, mi].contains(canto))
        #expect(fixed.flag == nil)
        #expect(fixed.editedAt == time.now)
        #expect(try engine.keptImages() == [bird])
        #expect(try engine.keptSounds() == [la, canto])
    }

    // `ficha cards` names a card's files, and a side with only a file has an
    // empty text.
    @Test("fixing a card copied with its files' names keeps them, and a side with only an image keeps its empty text")
    func fixingACopiedCardKeepsItsFiles() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let la = try await addTone(440, to: engine)
        let hornero = try engine.create(card(nil, front: "", back: "Un hornero.", frontImage: bird, backSound: la))
        try engine.flag(hornero.id, note: note("Ponerle una etiqueta"))
        time.advance(by: 60)

        let fixed = try await engine.fix(
            hornero.id,
            with: draft(
                nil, front: "", back: "Un hornero.", tags: ["aves"], frontImage: .put(.image(bird)),
                backSound: .put(.sound(la))))

        #expect(fixed.tags == ["aves"])
        #expect(fixed.frontImage == bird && fixed.backSound == la)
        #expect(fixed.editedAt == nil)
        #expect(try engine.keptImages() == [bird])
        #expect(try engine.keptSounds() == [la])
    }

    @Test(
        "approving an expansion keeps its card's step and the images and sounds it leaves out, and puts those it gives")
    func approvingAnExpansionKeepsTheFilesItLeavesOut() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let la = try await addTone(440, to: engine)
        let aria = try engine.create(card(.word, front: "aria", back: "Una canción.", frontImage: bird, backSound: la))
        try engine.climb(aria, to: 1, movingForward: time)
        let standing = try engine.standing(of: aria.id, on: ReviewSettings.defaults.ladder)
        let expansion = try engine.expand(text: "aria", note: "De una ópera", source: nil)
        let excerpt = try file("nessun-dorma.wav", holding: tone(seconds: 1, hertz: 392))

        let approved = try await engine.approveExpansion(
            expansion.id,
            into: draft(.word, front: "aria", back: "Una canción de una ópera.", frontSound: .put(.file(excerpt))))

        #expect(approved.back == "Una canción de una ópera.")
        #expect(approved.frontImage == bird && approved.backImage == nil)
        let nessunDorma = try #require(approved.frontSound)
        #expect(approved.backSound == la)
        #expect(try engine.standing(of: aria.id, on: ReviewSettings.defaults.ladder) == standing)
        #expect(try engine.inbox().expansions.isEmpty)
        #expect(try engine.keptSounds() == [la, nessunDorma])
    }

    @Test("putting a file on a side of a card tells an image from a sound, a video's too, and replaces the side's own")
    func puttingAFileOnASideTellsItsKind() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let hornero = try engine.create(card(.word, front: "hornero", back: "Un pájaro.", backImage: nest))
        try engine.flag(hornero.id, note: note("Poner su canto"))
        let photo = try file("hornero.png", holding: picture(width: 1200, height: 900, red: 0.8))
        let song = try file("canto.mov", holding: await video(seconds: 2, withSoundOf: 523))
        time.advance(by: 60)

        let withPhoto = try await engine.attach(.file(photo), to: .back, of: hornero.id)
        let withSong = try await engine.attach(.file(song), to: .front, of: hornero.id)

        let photoName = try #require(withPhoto.backImage)
        let songName = try #require(withSong.frontSound)
        #expect(photoName != nest)
        #expect(withSong.backImage == photoName)
        #expect(withSong.frontImage == nil && withSong.backSound == nil)
        #expect(withSong.back == "Un pájaro.")
        #expect(withSong.flag?.note == "Poner su canto")
        #expect(withSong.editedAt == time.now)
        #expect(try soundFormat(of: engine.sound(songName)).id == kAudioFormatMPEG4AAC)
        #expect(try engine.keptImages() == [photoName])
        #expect(try engine.keptSounds() == [songName])
    }

    @Test("putting an image or a sound Ficha holds on a side, by its name, works on a buried card, which stays buried")
    func puttingAFileByItsNameOnABuriedCard() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let la = try await addTone(440, to: engine)
        let hornero = try engine.create(card(.word, front: "hornero", back: "Un pájaro."))
        try engine.bury(hornero.id)

        try await engine.attach(.image(bird), to: .front, of: hornero.id)
        let buried = try await engine.attach(.sound(la), to: .back, of: hornero.id)

        #expect(buried.frontImage == bird && buried.backSound == la)
        #expect(buried.buriedAt != nil)
    }

    @Test("taking a side's image or sound off a card keeps the rest of it, and the file goes once no card uses it")
    func takingAFileOffASide() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let la = try await addTone(440, to: engine)
        let hornero = try engine.create(
            card(.word, front: "hornero", back: "Un pájaro.", frontImage: bird, backSound: la))
        try engine.create(card(nil, front: "¿Qué pájaro canta así?", back: "El hornero.", frontSound: la))
        time.advance(by: 60)

        let withoutImage = try engine.detach(.image, from: .front, of: hornero.id)
        let withoutSound = try engine.detach(.sound, from: .back, of: hornero.id)

        #expect(withoutImage.frontImage == nil && withoutImage.backSound == la)
        #expect(withoutSound.images.isEmpty && withoutSound.sounds.isEmpty)
        #expect(withoutSound.front == "hornero" && withoutSound.back == "Un pájaro.")
        #expect(withoutSound.editedAt == time.now)
        #expect(try engine.keptImages().isEmpty)
        #expect(try engine.keptSounds() == [la])
    }

    @Test("taking off a file a side doesn't have, or all a side holds, is refused, and the card stays as it was")
    func takingOffWhatIsntThereOrAllASideHolds() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try engine.create(card(nil, front: "", back: "Un hornero.", frontImage: bird))

        #expect(throws: EngineError.noFileOnSide(hornero.id, .sound, .front)) {
            try engine.detach(.sound, from: .front, of: hornero.id)
        }
        #expect(throws: EngineError.noFileOnSide(hornero.id, .image, .back)) {
            try engine.detach(.image, from: .back, of: hornero.id)
        }
        #expect(throws: EngineError.sideLeftBlank(hornero.id)) {
            try engine.detach(.image, from: .front, of: hornero.id)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.detach(.image, from: .front, of: 99)
        }
        #expect(try engine.cards() == [hornero])
        #expect(try engine.keptImages() == [bird])
    }

    @Test("a file that isn't the image or the sound its side's field asks for, or isn't there, is refused")
    func aFileOfTheWrongKindOrMissingIsRefused() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let la = try await addTone(440, to: engine)
        let capture = try engine.newCapture("hornero")
        let song = try file("canto.wav", holding: tone(seconds: 1, hertz: 523))
        let photo = try file("hornero.png", holding: picture(width: 800, height: 600, red: 0.8))
        let missing = folder.appending(path: "nido.jpg")
        let hornero = { (frontImage: FileChange, backSound: FileChange) in
            [draft(.word, front: "hornero", back: "Un pájaro.", frontImage: frontImage, backSound: backSound)]
        }

        await #expect(throws: EngineError.fileNotAnImage("canto.wav")) {
            try await engine.approve(capture.id, into: hornero(.put(.file(song)), .keep))
        }
        await #expect(throws: EngineError.fileNotAnImage(la.rawValue)) {
            try await engine.approve(capture.id, into: hornero(.put(.sound(la)), .keep))
        }
        await #expect(throws: EngineError.fileNotASound("hornero.png")) {
            try await engine.approve(capture.id, into: hornero(.keep, .put(.file(photo))))
        }
        await #expect(throws: EngineError.noSuchFile(missing.path(percentEncoded: false))) {
            try await engine.approve(capture.id, into: hornero(.put(.file(missing)), .keep))
        }
        await #expect(throws: EngineError.noSuchFile(missing.path(percentEncoded: false))) {
            try await engine.approve(capture.id, into: hornero(.keep, .put(.file(missing))))
        }
        #expect(try engine.inbox().captures.map(\.id) == [capture.id])
        #expect(try engine.keptImages().isEmpty)
        #expect(try engine.keptSounds() == [la])
    }

    @Test(
        "putting a file that's neither an image nor a sound, or isn't there, or on a card that doesn't exist, is refused"
    )
    func puttingAFileIsRefused() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let hornero = try engine.create(card(.word, front: "hornero", back: "Un pájaro."))
        let notes = try file("notas.txt", holding: Data("Hace su nido de barro.".utf8))
        let photo = try file("hornero.png", holding: picture(width: 800, height: 600, red: 0.8))
        let missing = folder.appending(path: "nido.jpg")

        await #expect(throws: EngineError.notAnImageOrSound("notas.txt")) {
            try await engine.attach(.file(notes), to: .front, of: hornero.id)
        }
        await #expect(throws: EngineError.noSuchFile(missing.path(percentEncoded: false))) {
            try await engine.attach(.file(missing), to: .front, of: hornero.id)
        }
        await #expect(throws: EngineError.cardNotFound(99)) {
            try await engine.attach(.file(photo), to: .front, of: 99)
        }
        #expect(try engine.cards() == [hornero])
        #expect(try engine.keptImages().isEmpty)
    }

    @Test("a refused approval or fix keeps none of the files it brought in, and changes nothing")
    func aRefusedChangeKeepsNoneOfItsFiles() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("hornero")
        let hornero = try engine.create(card(.word, front: "hornero", back: "Un pájaro."))
        let photo = try file("hornero.png", holding: picture(width: 800, height: 600, red: 0.8))
        let withPhoto = draft(.word, front: "hornero", back: "Un pájaro.", frontImage: .put(.file(photo)))

        await #expect(throws: EngineError.blankSideOnNewCard(position: 1)) {
            try await engine.approve(
                capture.id, into: [withPhoto, draft(.word, front: "nido", back: " ", frontImage: .remove)])
        }
        await #expect(throws: EngineError.captureNotInInbox(99)) {
            try await engine.approve(99, into: [withPhoto])
        }
        await #expect(throws: EngineError.cardNotFlagged(hornero.id)) {
            try await engine.fix(hornero.id, with: withPhoto)
        }
        await #expect(throws: EngineError.cardNotFound(99)) {
            try await engine.fix(99, with: withPhoto)
        }
        #expect(try engine.inbox().captures.map(\.id) == [capture.id])
        #expect(try engine.cards() == [hornero])
        #expect(try engine.keptImages().isEmpty)
    }

    @Test(
        "a side's file, as a refine session writes it, is a name Ficha holds when it reads as one, and a path otherwise"
    )
    func aFilesTextIsANameOrAPath() throws {
        let image = try #require(ImageName(rawValue: String(repeating: "a", count: 64) + ".jpg"))
        let sound = try #require(SoundName(rawValue: String(repeating: "b", count: 64) + ".m4a"))

        #expect(FileForSide(image.rawValue) == .image(image))
        #expect(FileForSide(sound.rawValue) == .sound(sound))
        #expect(path(of: FileForSide("/Users/lucas/Música/canto.mp3")) == "/Users/lucas/Música/canto.mp3")
        #expect(
            path(of: FileForSide("~/Música/canto.mp3"))
                == URL.homeDirectory.appending(path: "Música/canto.mp3").path(percentEncoded: false))
        #expect(
            path(of: FileForSide("Música/canto.mp3"))
                == URL.currentDirectory().appending(path: "Música/canto.mp3").path(percentEncoded: false))
        #expect(path(of: FileForSide("\(image.rawValue).png")) != nil)
        #expect(FileForSide(" ") == nil)
    }

    /// The path of the file on the Mac `file` gives, or nil when it gives
    /// none, or a name.
    private func path(of file: FileForSide?) -> String? {
        guard case .file(let url) = file else { return nil }
        return url.path(percentEncoded: false)
    }

    /// Writes `data` to a file named `name` in the test's folder, and returns
    /// where it is, to give a file by its path.
    private func file(_ name: String, holding data: Data) throws -> URL {
        let file = folder.appending(path: name)
        try data.write(to: file)
        return file
    }
}

/// A card for a test to approve, fix or expand from a refine session: it
/// always has a front and a back, and no tags or source unless the test gives
/// them, and changes no side's image or sound unless the test says so.
func draft(
    _ type: CardType?,
    front: String,
    back: String,
    tags: [String] = [],
    source: String? = nil,
    frontImage: FileChange = .keep,
    backImage: FileChange = .keep,
    frontSound: FileChange = .keep,
    backSound: FileChange = .keep
) -> CardDraft {
    CardDraft(
        type: type, front: front, back: back, tags: tags, source: source, frontImage: frontImage,
        backImage: backImage, frontSound: frontSound, backSound: backSound)
}
