import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the images of a deck imported from an Anki package, of either
/// schema Anki writes: which image each side of a card gets once the import
/// is done, which cards stay out for want of one, and what the preview
/// reports, from packages the tests write in a folder of their own, into an
/// engine in memory on a Mac in Buenos Aires.
final class AnkiImageImportingTests {
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the packages it imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaAnkiImageImportingTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 23, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The preview of `package`, written as `name` in the test's folder.
    private func preview(_ package: AnkiPackage, named name: String = "Pájaros.apkg") throws -> ImportPreview {
        let file = folder.appending(path: name)
        try package.write(to: file)
        return try engine.previewImport(of: file)
    }

    /// Previews `package` and imports it, with `choices`.
    private func importPackage(_ package: AnkiPackage, choosing choices: ImportChoices = ImportChoices()) throws {
        try engine.importCards(preview(package), choosing: choices)
    }

    @Test(
        "a card with an image on its front and its name on its back comes in with the image on its front",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aFrontImageComesInOnTheFront(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [AnkiNote(type: .basic, fields: ["<img src=\"hornero.jpg\">", "hornero"])],
            media: ["hornero.jpg": try picture(width: 400, height: 300, red: 0.8)])

        try importPackage(package)

        let card = try #require(try engine.cards().first)
        #expect([card.front, card.back] == ["", "hornero"])
        #expect(card.backImage == nil)
        let image = try #require(card.frontImage)
        #expect(try pixelSize(of: engine.image(image)) == (400, 300))
    }

    // The same image twice on a side drops none, and a side whose images
    // are on the web brings none, as sounds.
    @Test(
        "a side with two images brings the first, and the preview counts it",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aSideWithTwoImagesBringsTheFirst(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["horneros", "<img src=\"macho.jpg\"> y <img src='hembra.jpg'>"]),
                AnkiNote(type: .basic, fields: ["<img src=macho.jpg><br><img src=macho.jpg>", "un hornero"]),
                AnkiNote(
                    type: .basic,
                    fields: [
                        "<img src=\"https://example.com/tero.jpg\"> tero", "<img alt='src=\"x\"' src=\"hembra.jpg\">",
                    ]),
            ],
            media: [
                "macho.jpg": try picture(width: 400, height: 300, red: 0.8),
                "hembra.jpg": try picture(width: 300, height: 400, red: 0.2),
            ])

        let preview = try preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.cardsWithImagesDropped == 1)
        let cards = try engine.cards()
        #expect(cards.map { [$0.front, $0.back] } == [["horneros", "y"], ["", "un hornero"], ["tero", ""]])
        #expect(
            try cards.map { try $0.frontImage.map { try pixelSize(of: engine.image($0)).width } } == [nil, 400, nil])
        #expect(
            try cards.map { try $0.backImage.map { try pixelSize(of: engine.image($0)).width } } == [400, nil, 300])
    }

    // Shared decks' templates hide images of their own, such as an icon a
    // script shows now and then, which Anki's reviewer doesn't show either.
    @Test(
        "an image a template hides, in a comment, a script or a hidden tag, isn't its side's image",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func anImageATemplateHidesIsntItsSidesImage(format: AnkiPackage.Format) throws {
        let decorated = AnkiNoteType(
            name: "Decorada", fields: ["Front", "Back"],
            templates: [
                AnkiCardTemplate(
                    name: "Card 1",
                    question: """
                        <a href="https://example.com"><img style="DISPLAY:none" id="taza" src="taza.png"></a>
                        <img hidden src="taza.png"><img src='taza.png' hidden="">
                        <!-- <img src="taza.png"> -->
                        <SCRIPT type="text/javascript">var icon = '<img src="taza.png">';</script>
                        <style>/* <img src="taza.png"> */</STYLE>
                        {{Front}}
                        """,
                    answer: "{{FrontSide}}<hr id=answer>{{Back}}")
            ])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: decorated, fields: ["<img src=\"hornero.jpg\">", "hornero"]),
                AnkiNote(type: decorated, fields: ["tero", "Grita cuando alguien se acerca."]),
            ],
            media: [
                "hornero.jpg": try picture(width: 400, height: 300, red: 0.8),
                "taza.png": try picture(width: 100, height: 100, red: 0.1),
            ])

        let preview = try preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.cardsWithImagesDropped == 0)
        let cards = try engine.cards()
        #expect(cards.map { [$0.front, $0.back] } == [["", "hornero"], ["tero", "Grita cuando alguien se acerca."]])
        #expect(
            try cards.map { try $0.frontImage.map { try pixelSize(of: engine.image($0)).width } } == [400, nil])
    }

    // A side with text comes in without the image it lacks; one with only
    // the image keeps the card out, as does one with only a file Ficha
    // can't read as an image, such as an SVG Anki made of a formula.
    @Test(
        "a side with only a missing image keeps the card out with its reason",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aSideWithOnlyAMissingImageKeepsTheCardOut(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["<img src=\"tero.jpg\">", "tero"]),
                AnkiNote(type: .basic, fields: ["hornero <img src=\"nido.jpg\">", "Un pájaro que hace su nido."]),
                AnkiNote(type: .basic, fields: ["la fórmula del área del círculo", "<img src=\"latex-area.svg\">"]),
                AnkiNote(type: .basic, fields: ["<div><img src=\"tero.jpg\"></div>", "<img src=\"tero.jpg\">"]),
            ],
            media: ["latex-area.svg": Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)])

        let preview = try preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(
            preview.leftOut == [
                LeftOutLine(line: 1, reason: .missingAnkiImage), LeftOutLine(line: 3, reason: .unreadableAnkiImage),
                LeftOutLine(line: 4, reason: .missingAnkiImage),
            ])
        let cards = try engine.cards()
        #expect(cards.map { [$0.front, $0.back] } == [["hornero", "Un pájaro que hace su nido."]])
        #expect(cards.map { [$0.frontImage, $0.backImage] } == [[nil, nil]])
    }

    // Anki draws a field's formula with LaTeX, and a package carries the
    // picture, named after the formula: these names are the ones Anki's own
    // tests expect (`rslib/src/latex.rs`).
    @Test(
        "a side that is only one of Anki's formulas comes in as the picture Anki drew of it, and one beside text, one of several, or one without its picture, as its LaTeX",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aFormulaAloneComesInAsAnkisPicture(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["Saludo", "[$]<b>hello</b>&nbsp; world[/$]"]),
                AnkiNote(type: .basic, fields: ["<div>[$$]math &amp; stuff[/$$]</div>", "Mates"]),
                // Anki reads `<br/>` as a line break in a formula, as `<br>`,
                // but not `<br />`.
                AnkiNote(type: .basic, fields: ["[latex]one<br/>and<div>two[/latex]", "Pasos"]),
                AnkiNote(type: .basic, fields: ["Un paso", "a[latex]one<br>and<div>two[/latex]b"]),
                AnkiNote(type: .basic, fields: ["Dos", "[$]x[/$] [$]y[/$]"]),
                AnkiNote(type: .basic, fields: ["Sin dibujo", "[$]z[/$]"]),
            ],
            media: [
                "latex-060219fbf3ddb74306abddaf4504276ad793b029.png": try picture(width: 300, height: 60, red: 0.1),
                "latex-8899f3f849ffdef6e4e9f2f34a923a1f608ebc07.png": try picture(width: 200, height: 60, red: 0.2),
                "latex-ef30b3f4141c33a5bf7044b0d1961d3399c05d50.png": try picture(width: 100, height: 60, red: 0.3),
            ])

        let preview = try preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.cardsWithImagesDropped == 0)
        let cards = try engine.cards()
        #expect(
            cards.map { [$0.front, $0.back] } == [
                ["Saludo", ""], ["", "Mates"], ["", "Pasos"], ["Un paso", "a[latex]one\nand\ntwo[/latex]b"],
                ["Dos", "[$]x[/$] [$]y[/$]"],
                ["Sin dibujo", "[$]z[/$]"],
            ])
        #expect(
            try cards.map { try $0.frontImage.map { try pixelSize(of: engine.image($0)).width } } == [
                nil, 200, 100, nil, nil, nil,
            ])
        #expect(
            try cards.map { try $0.backImage.map { try pixelSize(of: engine.image($0)).width } } == [
                300, nil, nil, nil, nil, nil,
            ])
    }

    // The rest of the package comes in, as when Anki exports a deck without
    // its media.
    @Test(
        "an image the media list names but the package lacks leaves its side without it",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func anImageThePackageLacksLeavesItsSideWithoutIt(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["hornero <img src=\"nido.jpg\">", "Un pájaro que hace su nido."]),
                AnkiNote(type: .basic, fields: ["<img src=\"nido.jpg\">", "un nido de hornero"]),
            ],
            media: ["nido.jpg": try picture(width: 400, height: 300, red: 0.8)],
            mediaMissingFromTheZip: ["nido.jpg"])

        let preview = try preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.leftOut == [LeftOutLine(line: 2, reason: .missingAnkiImage)])
        let cards = try engine.cards()
        #expect(cards.map { [$0.front, $0.back] } == [["hornero", "Un pájaro que hace su nido."]])
        #expect(cards.map(\.frontImage) == [nil])
    }

    // As an image Ficha can't read, rather than refusing the whole package.
    @Test("a damaged image keeps out a card with only it, and the rest of the package comes in")
    func aDamagedImageKeepsItsCardOut() throws {
        let package = AnkiPackage(
            format: .current,
            notes: [
                AnkiNote(type: .basic, fields: ["<img src=\"nido.jpg\">", "un nido de hornero"]),
                AnkiNote(type: .basic, fields: ["<img src=\"tero.jpg\">", "tero"]),
            ],
            media: [
                "nido.jpg": try picture(width: 400, height: 300, red: 0.8),
                "tero.jpg": try picture(width: 300, height: 400, red: 0.2),
            ],
            damagedMedia: ["nido.jpg"])

        let preview = try preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.leftOut == [LeftOutLine(line: 1, reason: .unreadableAnkiImage)])
        let cards = try engine.cards()
        #expect(cards.map(\.back) == ["tero"])
        #expect(try cards.map { try $0.frontImage.map { try pixelSize(of: engine.image($0)).width } } == [300])
    }

    @Test("a big image comes in shrunk", arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aBigImageComesInShrunk(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [AnkiNote(type: .basic, fields: ["el esqueleto", "<img src=\"esqueleto.png\">"])],
            media: ["esqueleto.png": try picture(width: 2400, height: 3200, red: 0.9)])

        try importPackage(package)

        let image = try #require(try engine.cards().first?.backImage)
        #expect(try pixelSize(of: engine.image(image)) == (1200, 1600))
    }

    // Anki keeps a name in a field with HTML's references, and some decks
    // with percent signs, as a browser's address has them; a name with a
    // percent sign of its own is found as it is.
    @Test(
        "an image is found by its name as Anki writes it, with HTML's references and percent signs",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func anImageIsFoundByItsNameAsAnkiWritesIt(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["<img src=\"hornero &amp; nido.jpg\">", "un hornero en su nido"]),
                AnkiNote(type: .basic, fields: ["<img src=\"nido%20de%20barro.jpg\">", "un nido de barro"]),
                AnkiNote(type: .basic, fields: ["<img src=\"100%.jpg\">", "todo"]),
            ],
            media: [
                "hornero & nido.jpg": try picture(width: 400, height: 300, red: 0.8),
                "nido de barro.jpg": try picture(width: 300, height: 400, red: 0.2),
                "100%.jpg": try picture(width: 200, height: 200, red: 0.5),
            ])

        let preview = try preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.leftOut == [])
        #expect(
            try engine.cards().map { try $0.frontImage.map { try pixelSize(of: engine.image($0)).width } } == [
                400, 300, 200,
            ])
    }

    @Test(
        "a card the deck repeats takes the image on Anki's back, or none, when it's updated, and keeps its front's",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func anUpdatedCardTakesTheImageOnAnkisBack(format: AnkiPackage.Format) throws {
        let mine = try engine.addImage(picture(width: 200, height: 200, red: 0.1))
        try engine.create(card(nil, front: "hornero", back: "Un pájaro.", frontImage: mine, backImage: mine))
        try engine.create(card(nil, front: "tero", back: "Otro pájaro.", backImage: mine))
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["hornero", "Hace su nido de barro. <img src=\"nido.jpg\">"]),
                AnkiNote(type: .basic, fields: ["tero", "Grita cuando alguien se acerca."]),
            ],
            media: ["nido.jpg": try picture(width: 300, height: 400, red: 0.2)])

        try importPackage(package)

        let cards = try engine.cards()
        #expect(cards.map(\.back) == ["Hace su nido de barro.", "Grita cuando alguien se acerca."])
        #expect(cards.map(\.frontImage) == [mine, nil])
        #expect(try cards.map { try $0.backImage.map { try pixelSize(of: engine.image($0)).width } } == [300, nil])
    }
}
