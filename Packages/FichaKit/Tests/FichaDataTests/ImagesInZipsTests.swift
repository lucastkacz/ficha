import FichaCore
import FichaData
import FichaSVG
import Foundation
import Testing
import ZIPFoundation

/// Tests on cards that travel with their images in a deck's `.ficha` (#542):
/// an export of a deck is a zip with the text file and the images, and adding
/// a deck reads such a zip back, from engines in memory on a Mac in Buenos
/// Aires, into files in a folder of the test's own.
final class ImagesInZipsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the files it exports and adds.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaImagesInZipsTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 23, in: calendar))
        engine = try Engine(
            location: .inMemory, time: time, calendar: calendar, drawingSVGsWith: { InProcessSVGDrawer() })
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Another Ficha, with no cards, once it adds the deck of `file`, with
    /// every line read.
    private func anotherFicha(adding file: URL) async throws -> Engine {
        let other = try Engine(location: .inMemory, time: time, calendar: calendar)
        let deck = try await other.readDeckFile(at: file)
        #expect(deck.leftOut == [])
        try other.addDeck(deck)
        return other
    }

    @Test(
        "a deck's cards with images export as a zip and come back with the same images on the same sides",
        .bug(id: 542))
    func cardsWithImagesExportAsAZipAndImportBack() async throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        // A PNG, since it has transparency.
        let nest = try engine.addImage(picture(width: 600, height: 800, red: 0.3, alpha: 0.5))
        let contents = [
            try card(
                .word, front: "hornero", back: "Un pájaro que hace su nido de barro.", tags: ["aves"],
                source: "Un libro de aves", backImage: nest),
            try card(nil, front: "", back: "Un hornero.", frontImage: bird),
            try card(nil, front: "¿De quién es este nido?", back: "", frontImage: nest, backImage: bird),
            try card(.concept, front: "petricor", back: "El olor de la lluvia sobre la tierra seca."),
        ]
        for content in contents {
            try engine.create(content, deck: "Aves")
        }
        let file = folder.appending(path: "Aves.ficha")

        let count = try engine.export(.deck("Aves"), to: file)

        #expect(count == 4)
        let archive = try Archive(url: file, accessMode: .read)
        #expect(Set(archive.map(\.path)) == ["Aves.txt", "deck.json", bird.rawValue, nest.rawValue])
        let other = try await anotherFicha(adding: file)
        #expect(try other.cards().map(content(of:)) == contents)
        #expect(try other.image(bird) == engine.image(bird))
        #expect(try other.image(nest) == engine.image(nest))
    }

    @Test(
        "a missing image in a deck's .ficha leaves its side without it, and a card left with an empty side stays out with its reason",
        .bug(id: 542))
    func aMissingImageLeavesItsSideWithoutIt() async throws {
        let text = """
            #separator:tab
            #html:false
            #columns:Front\tBack\tFront image\tBack image
            hornero\tUn pájaro que hace su nido de barro.\thornero.jpg\t
            nido\tDe barro, con dos cámaras.\tnido.jpg\t
            \tUn tero.\ttero.jpg\t
            calandria\t\t\tcanto.jpg
            cardenal\tUn pájaro de copete rojo.\t\tcardenal.png

            """
        let file = try deckFile(
            "Pájaros.ficha", text,
            [
                ("hornero.jpg", try picture(width: 2400, height: 1800, red: 0.8)),
                ("canto.jpg", Data("Un canto, no una imagen.".utf8)),
                ("cardenal.png", try picture(width: 300, height: 400, red: 0.9)),
            ])

        let deck = try await engine.readDeckFile(at: file)
        try engine.addDeck(deck)

        #expect(
            deck.leftOut == [
                LeftOutLine(line: 6, reason: .missingImage("tero.jpg")),
                LeftOutLine(line: 7, reason: .notAnImage("canto.jpg")),
            ])
        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["hornero", "nido", "cardenal"])
        #expect(cards.map { $0.frontImage != nil } == [true, false, false])
        #expect(cards.map { $0.backImage != nil } == [false, false, true])
        let hornero = try #require(cards.first?.frontImage)
        #expect(try pixelSize(of: engine.image(hornero)) == (1600, 1200))
    }

    @Test("an SVG in a deck's .ficha comes in drawn, 1,600 pixels on its long side", .bug(id: 542))
    func anSVGInAZipComesInDrawn() async throws {
        let text = "#columns:Front\tBack\tFront image\n\tEl sol.\tsol.svg\n"
        let file = try deckFile("Cielo.ficha", text, [("sol.svg", sunSVG)])

        let deck = try await engine.readDeckFile(at: file)
        try engine.addDeck(deck)

        #expect(deck.leftOut == [])
        let sun = try #require(try engine.cards().first?.frontImage)
        #expect(try pixelSize(of: engine.image(sun)) == (1600, 1067))
    }

    @Test(
        "a damaged image in a deck's .ficha is one Ficha can't read, and the rest of the file comes in", .bug(id: 542))
    func aDamagedImageInAZipIsOneFichaCantRead() async throws {
        let text = "#columns:Front\tBack\tFront image\n\tUn nido.\tnido.jpg\nhornero\tUn pájaro.\tnido.jpg\n"
        // The image first, so that its name first comes in its header.
        let file = folder.appending(path: "Aves.ficha")
        try writeZip(
            [
                ("nido.jpg", try picture(width: 400, height: 300, red: 0.8)), ("Aves.txt", Data(text.utf8)),
                ("deck.json", Data(#"{"description": null, "emoji": null}"#.utf8)),
            ], to: file)
        var bytes = try Data(contentsOf: file)
        let name = try #require(bytes.firstRange(of: Data("nido.jpg".utf8)))
        bytes[name.upperBound + 20] ^= 0xFF
        try bytes.write(to: file)

        let deck = try await engine.readDeckFile(at: file)

        #expect(deck.leftOut == [LeftOutLine(line: 2, reason: .notAnImage("nido.jpg"))])
        #expect(deck.cardCount == 1)
    }

    @Test(
        "a deck's .ficha without one text file of cards, or that can't be opened as a zip, is a damaged deck's file",
        .bug(id: 542))
    func aZipWithoutOneTextFileIsntRead() async throws {
        let photos = folder.appending(path: "Fotos.ficha")
        try writeZip(
            [
                ("hornero.jpg", try picture(width: 300, height: 200)),
                ("deck.json", Data(#"{"description": null, "emoji": null}"#.utf8)),
            ], to: photos)
        let two = try deckFile("Dos.ficha", "hornero\tUn pájaro.\n", [("Más aves.csv", Data("tero,Un ave.\n".utf8))])
        let broken = folder.appending(path: "Rota.ficha")
        try Data([0x50, 0x4B, 0x03, 0x04] + Array("no es un zip".utf8)).write(to: broken)

        for file in [photos, two, broken] {
            await #expect(throws: EngineError.unreadableFile(file.lastPathComponent, .damagedDeckFile)) {
                try await engine.readDeckFile(at: file)
            }
        }
    }

    // A front's image counts when both fronts have one (#229's decision 3).
    @Test(
        "a deck's .ficha's cards that repeat the user's are skipped: a front with only an image repeats one with that image, and a front with an image not one with another",
        .bug(id: 542))
    func aZipsCardsUpdateTheBacksImage() async throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let hornero = try engine.create(
            card(.word, front: "hornero", back: "Un pájaro.", frontImage: bird, backImage: nest))
        let tero = try engine.create(card(.word, front: "tero", back: "Un ave que grita.", backImage: nest))
        let onlyAnImage = try engine.create(card(nil, front: "", back: "Un hornero.", frontImage: bird))
        let text = """
            #columns:Front\tBack\tFront image\tBack image
            hornero\tOtro hornero.\totro-hornero.jpg\t
            hornero\tUn pájaro que hace su nido de barro.\t\thuevo.jpg
            tero\tUn ave que grita cuando alguien se acerca a su nido.\t\t
            \tUn hornero, otra vez.\thornero.jpg\t

            """
        let file = try deckFile(
            "Aves.ficha", text,
            [
                ("huevo.jpg", try picture(width: 800, height: 600, red: 0.1)),
                ("otro-hornero.jpg", try picture(width: 800, height: 600, red: 0.6)),
                ("hornero.jpg", try engine.image(bird)),
            ])

        let outcome = try await engine.addDeck(at: file)

        #expect(outcome == ImportOutcome(added: 1, skipped: 3, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(cards.map(\.id).prefix(3) == [hornero.id, tero.id, onlyAnImage.id])
        #expect(cards.map(\.back) == ["Un pájaro.", "Un ave que grita.", "Un hornero.", "Otro hornero."])
        let otherBird = try #require(cards[3].frontImage)
        #expect(cards.map(\.frontImage) == [bird, nil, bird, otherBird])
        #expect(otherBird != bird)
        #expect(cards.map(\.backImage) == [nest, nest, nil, nil])
    }

    @Test(
        "a deck's .ficha's card with the very front image of a card repeats it, though a card before it with that front and no image could",
        .bug(id: 542))
    func aCardWithTheSameFrontImageRepeatsFirst() async throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try engine.create(card(.word, front: "hornero", back: "Un pájaro.", frontImage: bird))
        let text = """
            #columns:Front\tBack\tFront image
            hornero\tUn pájaro, sin foto.\t
            hornero\tUn pájaro que hace su nido de barro.\thornero.jpg

            """
        let file = try deckFile("Aves.ficha", text, [("hornero.jpg", try engine.image(bird))])

        let outcome = try await engine.addDeck(at: file)

        #expect(outcome == ImportOutcome(added: 1, skipped: 1, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(cards.first?.id == hornero.id)
        #expect(cards.map(\.back) == ["Un pájaro.", "Un pájaro, sin foto."])
        #expect(cards.map(\.frontImage) == [bird, nil])
    }

    /// Writes a deck's `.ficha` named `name` in the test's folder, with
    /// `text` as its text file and `files` beside it, and returns it.
    private func deckFile(_ name: String, _ text: String, _ files: [(name: String, data: Data)]) throws -> URL {
        let file = folder.appending(path: name)
        try writeDeckFile(at: file, text: text, files: files)
        return file
    }
}

/// Writes a zip to `file`, holding `files`, each a path in the zip and what
/// the file there holds, compressed: a test's own zip, as a person or a zip
/// tool makes one.
func writeZip(_ files: [(path: String, data: Data)], to file: URL) throws {
    let archive = try Archive(url: file, accessMode: .create, pathEncoding: nil)
    for (path, data) in files {
        try archive.addEntry(
            with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate
        ) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }
}
