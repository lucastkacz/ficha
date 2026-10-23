import FichaCore
import FichaData
import Foundation
import Testing
import ZIPFoundation

/// Tests on cards that travel with their images: an export of cards with
/// images is a zip with the text file and the images, and the import reads
/// such a zip back, from engines in memory on a Mac in Buenos Aires, into
/// files in a folder of the test's own.
final class ImagesInZipsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the files it exports and imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaImagesInZipsTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 23, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Another Ficha, with no cards, once it imports `file`, with every line
    /// read and without the tag named after the file.
    private func anotherFicha(importing file: URL) throws -> Engine {
        let other = try Engine(location: .inMemory, time: time, calendar: calendar)
        let preview = try other.previewImport(of: file)
        #expect(preview.leftOut == [])
        try other.importCards(
            preview,
            choosing: ImportChoices(tagNames: Dictionary(uniqueKeysWithValues: preview.proposedTags.map { ($0, "") })))
        return other
    }

    @Test("cards with images export as a zip and import back with the same images on the same sides")
    func cardsWithImagesExportAsAZipAndImportBack() throws {
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
            try engine.create(content)
        }
        let file = folder.appending(path: "Aves.zip")

        let count = try engine.export(.all, to: file)

        #expect(count == 4)
        let archive = try Archive(url: file, accessMode: .read)
        #expect(Set(archive.map(\.path)) == ["Aves.txt", bird.rawValue, nest.rawValue])
        let other = try anotherFicha(importing: file)
        #expect(try other.cards().map(content(of:)) == contents)
        #expect(try other.image(bird) == engine.image(bird))
        #expect(try other.image(nest) == engine.image(nest))
    }

    // Anki imports such a file, which a zip would keep from it.
    @Test("cards without images export as a text file, as before")
    func cardsWithoutImagesExportAsATextFile() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try engine.create(card(.word, front: "hornero", back: "Un pájaro.", tags: ["aves"], frontImage: bird))
        try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["palabras"]))
        try engine.create(card(nil, front: "serendipia", back: "Un hallazgo por casualidad.", tags: ["palabras"]))
        let file = folder.appending(path: "palabras.txt")

        let count = try engine.export(.tag("palabras"), to: file)

        #expect(count == 2)
        #expect(
            try String(contentsOf: file, encoding: .utf8) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource
                #tags column:3
                petricor\tEl olor de la lluvia.\tpalabras\tword\t
                serendipia\tUn hallazgo por casualidad.\tpalabras\t\t

                """)
    }

    @Test(
        "a missing image in a zip leaves its side without it, and a card left with an empty side stays out with its reason"
    )
    func aMissingImageLeavesItsSideWithoutIt() throws {
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
        let file = try zip(
            [
                ("Pájaros.txt", Data(text.utf8)),
                ("hornero.jpg", try picture(width: 2400, height: 1800, red: 0.8)),
                ("canto.jpg", Data("Un canto, no una imagen.".utf8)),
                ("cardenal.png", try picture(width: 300, height: 400, red: 0.9)),
            ], named: "Pájaros.zip")

        let preview = try engine.previewImport(of: file)
        try engine.importCards(preview, choosing: ImportChoices(tagNames: ["Pájaros": ""]))

        #expect(
            preview.leftOut == [
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

    @Test("a zip Finder made of a folder imports the text file in it with its images, whatever their case")
    func aZipFinderMadeOfAFolderImports() throws {
        let file = try zip(
            [
                ("Aves/Aves.txt", Data("#columns:Front\tBack\tFront image\n\tUn hornero.\thornero.jpg\n".utf8)),
                ("Aves/Hornero.JPG", try picture(width: 800, height: 600, red: 0.8)),
                ("Aves/.DS_Store", Data("Finder".utf8)),
                ("__MACOSX/Aves/._Aves.txt", Data("Finder".utf8)),
            ], named: "Aves.zip")

        let preview = try engine.previewImport(of: file)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.leftOut == [])
        let cards = try engine.cards()
        #expect(cards.map(\.back) == ["Un hornero."])
        #expect(cards.map(\.tags) == [["Aves"]])
        #expect(cards.first?.frontImage != nil)
    }

    @Test("a zip without one text file of cards, or that can't be opened as a zip, isn't read at all")
    func aZipWithoutOneTextFileIsntRead() throws {
        let photos = try zip([("hornero.jpg", try picture(width: 300, height: 200))], named: "Fotos.zip")
        let two = try zip(
            [("Aves.txt", Data("hornero\tUn pájaro.\n".utf8)), ("Más aves.csv", Data("tero,Un ave.\n".utf8))],
            named: "Dos.zip")
        let broken = folder.appending(path: "Rota.zip")
        try Data([0x50, 0x4B, 0x03, 0x04] + Array("no es un zip".utf8)).write(to: broken)

        #expect(throws: EngineError.unreadableFile("Fotos.zip", .noTextFileInZip)) {
            try engine.previewImport(of: photos)
        }
        #expect(throws: EngineError.unreadableFile("Dos.zip", .severalTextFilesInZip(["Aves.txt", "Más aves.csv"]))) {
            try engine.previewImport(of: two)
        }
        #expect(throws: EngineError.unreadableFile("Rota.zip", .unreadableZip)) {
            try engine.previewImport(of: broken)
        }
    }

    @Test(
        "a zip's cards update the cards they repeat with the back's image the file gives, keeping the front's, and one whose front is only an image comes in as new"
    )
    func aZipsCardsUpdateTheBacksImage() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let hornero = try engine.create(
            card(.word, front: "hornero", back: "Un pájaro.", frontImage: bird, backImage: nest))
        let tero = try engine.create(card(.word, front: "tero", back: "Un ave que grita.", backImage: nest))
        let onlyAnImage = try engine.create(card(nil, front: "", back: "Un hornero.", frontImage: bird))
        let text = """
            #columns:Front\tBack\tFront image\tBack image
            hornero\tUn pájaro que hace su nido de barro.\totro-hornero.jpg\thuevo.jpg
            tero\tUn ave que grita cuando alguien se acerca a su nido.\t\t
            \tUn hornero, otra vez.\thornero.jpg\t

            """
        let file = try zip(
            [
                ("Aves.txt", Data(text.utf8)),
                ("huevo.jpg", try picture(width: 800, height: 600, red: 0.1)),
                ("otro-hornero.jpg", try picture(width: 800, height: 600, red: 0.6)),
                ("hornero.jpg", try engine.image(bird)),
            ], named: "Aves.zip")

        let preview = try engine.previewImport(of: file)
        let outcome = try engine.importCards(preview, choosing: ImportChoices(tagNames: ["Aves": ""]))

        #expect(preview.repeatedCount == 2)
        #expect(outcome == ImportOutcome(added: 1, updated: 2, skipped: 0, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(cards.map(\.id).prefix(3) == [hornero.id, tero.id, onlyAnImage.id])
        #expect(
            cards.map(\.back) == [
                "Un pájaro que hace su nido de barro.", "Un ave que grita cuando alguien se acerca a su nido.",
                "Un hornero.", "Un hornero, otra vez.",
            ])
        let egg = try #require(cards[0].backImage)
        #expect(cards.map(\.frontImage) == [bird, nil, bird, bird])
        #expect(cards.map(\.backImage) == [egg, nil, nil, nil])
        // The nest's image, which no card uses any more, is gone.
        _ = try engine.image(egg)
        #expect(throws: EngineError.imagesFolder) {
            try engine.image(nest)
        }
    }

    /// Writes a zip named `name` in the test's folder, holding `files`, and
    /// returns it.
    private func zip(_ files: [(path: String, data: Data)], named name: String) throws -> URL {
        let file = folder.appending(path: name)
        try writeZip(files, to: file)
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
