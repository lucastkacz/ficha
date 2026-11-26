import AVFoundation
import CoreGraphics
import FichaCore
import FichaData
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

// For the command, which reads the cards as JSON, and the JSON it prints
// their result as.
@testable import FichaCLI

/// Tests on `ficha add` (ADR 0041): the cards a refine session passes as JSON
/// on its standard input, added straight into their decks by an engine in
/// memory that takes files from a Downloads folder of the test's own, as the
/// CLI's sandbox does (ADR 0018), and the JSON it prints.
final class AddCommandTests {
    let time: ManualTimeSource
    /// A folder of the test's own, which holds its Downloads folder.
    let folder: URL
    /// The Downloads folder, the one the engine takes files from.
    let downloads: URL
    let engine: Engine

    init() throws {
        let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
        let folder = URL.temporaryDirectory.appending(
            path: "FichaAddCommandTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let downloads = folder.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        self.time = time
        self.folder = folder
        self.downloads = downloads
        engine = try Engine(location: .inMemory, time: time, refineFilesOnlyIn: downloads)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // The capture waits in the inbox before and after: the cards come in
    // without it.
    @Test(
        "`ficha add` saves a list's cards as new, in its order, each in its deck, and prints them as `ficha approve` does, with no capture",
        .bug(id: 534))
    func addSavesTheCardsAsNew() async throws {
        guard case .saved(let capture) = try engine.capture(text: "coloratura", note: nil, source: nil) else {
            Issue.record("The capture wasn't saved.")
            return
        }
        let input = Data(
            """
            [
              {"type": "word", "front": "serendipia", "back": "Un hallazgo valioso que se da por casualidad.",
               "tags": ["etimología"], "source": null, "deck": "Idiomas::Español", "bothWays": true},
              {"type": null, "front": "hornero", "back": "Un pájaro que hace su nido de barro.", "tags": [],
               "source": "Aves argentinas"}
            ]
            """.utf8)

        let printed = try await add(input)

        let cards = try engine.cards()
        #expect(FichaCommand.configuration.subcommands.contains { $0 == AddCommand.self })
        #expect(cards.map(\.front) == ["serendipia", "hornero"])
        #expect(cards.map(\.deck) == ["Idiomas::Español", Deck.defaultName])
        #expect(cards.map(\.bothWays) == [true, false])
        #expect(cards.map(\.source) == [nil, "Aves argentinas"])
        #expect(cards.allSatisfy { $0.captureID == nil && $0.createdAt == time.now && $0.standing == .inReviews })
        #expect(try engine.reviewLog().isEmpty)
        #expect(try printed == json(cards))
        #expect(try engine.inbox().captures == [capture])
    }

    @Test(
        "`ficha add` puts on a side a picture or a sound from Downloads, given in the same file fields as `ficha approve`",
        .bug(id: 534))
    func addPutsFilesFromDownloads() async throws {
        let photo = downloads.appending(path: "hornero.png")
        let song = downloads.appending(path: "canto.wav")
        try picture().write(to: photo)
        try tone().write(to: song)
        let input = Data(
            """
            [{"type": "word", "front": "hornero", "back": "Un pájaro que hace su nido de barro.", "tags": [],
              "source": null, "frontImage": "\(photo.path(percentEncoded: false))",
              "backSound": "\(song.path(percentEncoded: false))"}]
            """.utf8)

        let printed = try await add(input)

        let card = try #require(try engine.cards().first)
        #expect(card.frontImage != nil && card.backSound != nil)
        #expect(card.backImage == nil && card.frontSound == nil)
        #expect(try printed == json([card]))
    }

    // " serendipia " repeats Serendipia by the duplicate rule, and the
    // second hornero the first; ibuprofeno's type and Idiomas don't exist
    // yet, so a list that made them would leave them behind.
    @Test(
        "`ficha add` adds none of a list in which a card's front repeats another card's, and its error names that card",
        .bug(id: 534))
    func addRefusesAListWithADuplicate() async throws {
        let serendipia = try engine.create(
            try #require(CardContent(type: .word, front: "Serendipia", back: "Un hallazgo.", tags: [], source: nil)))
        let repeatsACard = Data(
            """
            [
              {"type": "Fármaco", "front": "ibuprofeno", "back": "Un antiinflamatorio.", "tags": [], "source": null,
               "deck": "Medicina"},
              {"type": "word", "front": " serendipia ", "back": "Un hallazgo por casualidad.", "tags": [],
               "source": null, "deck": "Idiomas"}
            ]
            """.utf8)
        let repeatsTheList = Data(
            """
            [
              {"type": null, "front": "hornero", "back": "Un pájaro.", "tags": [], "source": null},
              {"type": null, "front": "nido", "back": "Lo hace el hornero.", "tags": [], "source": null},
              {"type": null, "front": "Hornero", "back": "Un pájaro de barro.", "tags": [], "source": null}
            ]
            """.utf8)
        let repeatedCard = DuplicateCardError(
            position: 1, front: " serendipia ", repeated: .card(id: serendipia.id, front: "Serendipia"))
        let repeatedInList = DuplicateCardError(
            position: 2, front: "Hornero", repeated: .cardInList(position: 0, front: "hornero"))

        await #expect(throws: repeatedCard) { try await self.add(repeatsACard) }
        await #expect(throws: repeatedInList) { try await self.add(repeatsTheList) }

        #expect(try engine.cards() == [serendipia])
        #expect(try engine.userTypes().isEmpty)
        #expect(try engine.decks().map(\.name) == [Deck.defaultName])
        #expect(
            repeatedCard.errorDescription == """
                Card [1], “serendipia”, repeats card \(serendipia.id), “Serendipia”, so no card of the list was \
                added. Leave it out, or give it a front of its own, and add the list again.
                """)
        #expect(repeatedInList.errorDescription?.hasPrefix("Card [2], “Hornero”, repeats card [0], “hornero”,") == true)
    }

    /// Runs `ficha add` on the engine with `input` on its standard input, as
    /// the CLI runs it, and returns the JSON it prints.
    private func add(_ input: Data) async throws -> String {
        try json(await AddCommand().add(reading: input, on: engine))
    }
}

/// A picture of 800 by 600 pixels in one color, as a PNG: a test's own image,
/// made as FichaDataTests' `picture` makes one.
private func picture() throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
        CGContext(
            data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(srgbRed: 0.8, green: 0.6, blue: 0.4, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// A tone of 440 hertz lasting a second, mono, as a WAV file's data: a test's
/// own sound, made as FichaDataTests' `tone` makes one.
private func tone() throws -> Data {
    let file = URL.temporaryDirectory.appending(path: "FichaTone-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: file) }
    let format = try #require(
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
    buffer.frameLength = 44_100
    let samples = try #require(buffer.floatChannelData)
    for frame in 0..<44_100 {
        samples[0][frame] = Float(sin(2 * Double.pi * 440 * Double(frame) / 44_100) * 0.5)
    }
    do {
        let wav = try AVAudioFile(
            forWriting: file,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try wav.write(from: buffer)
    }
    return try Data(contentsOf: file)
}
