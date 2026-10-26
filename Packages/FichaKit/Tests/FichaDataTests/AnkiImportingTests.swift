import FichaCore
import FichaData
import Foundation
import Testing

/// A package of each schema Anki writes: schema 11, as current Anki exports
/// a deck with "Support older Anki versions" ticked, and as older Ankis do;
/// and schema 18, compressed with zstd, as current Anki exports it by
/// default.
private let schemas: [AnkiPackage.Format] = [.supportOlderAnkiVersions, .current]

/// A package of each version Anki writes, as Ficha reads them all: Anki
/// 2.0's, Anki 2.1's before 2.1.50, and current Anki's two.
private let everyVersion: [AnkiPackage.Format] = [.anki20, .anki21, .supportOlderAnkiVersions, .current]

/// Tests on importing a deck from an Anki package, from any Anki: which
/// cards there are once the import is done, with which sides and tags, and
/// what the preview reports, from packages the tests write in a folder of
/// their own, into an engine in memory on a Mac in Buenos Aires.
final class AnkiImportingTests {
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the packages it imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaAnkiImportingTests-\(UUID().uuidString)",
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

    /// Writes `package` to a file named `name` in the test's folder, and
    /// returns the file.
    private func file(_ name: String, _ package: AnkiPackage) throws -> URL {
        let file = folder.appending(path: name)
        try package.write(to: file)
        return file
    }

    /// Previews `package`, written as `name`, and imports it with `choices`,
    /// and returns what the import did.
    @discardableResult
    private func importPackage(
        _ package: AnkiPackage, named name: String = "Mazo.apkg", choosing choices: ImportChoices = ImportChoices()
    ) async throws -> ImportOutcome {
        try await engine.importCards(engine.previewImport(of: file(name, package)), choosing: choices)
    }

    @Test("a Basic note becomes one card, with its Front and Back as plain text", arguments: schemas)
    func aBasicNoteBecomesOneCard(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic,
                    fields: ["<b>corazón</b>", "El órgano que bombea<br>la sangre&nbsp;por el cuerpo."])
            ])

        let outcome = try await importPackage(package)

        #expect(outcome == ImportOutcome(added: 1, updated: 0, skipped: 0, copyBeforeImport: nil))
        let card = try #require(try engine.cards().first)
        #expect([card.front, card.back] == ["corazón", "El órgano que bombea\nla sangre por el cuerpo."])
        #expect(card.type == nil)
        #expect(card.source == nil)
    }

    // As Core 2000's fronts, where Anki shows the sentence's sound button
    // between the part of speech and the sentence: the lines around it are
    // left empty once the sound is apart from the text.
    @Test("a run of empty lines on a side folds into one empty line, and one empty line stays", arguments: schemas)
    func aRunOfEmptyLinesFoldsIntoOne(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic,
                    fields: [
                        "sustantivo<br><br><br>[sound:arroz.mp3]<br><br><br>Como arroz.",
                        "<div>arroz</div><div><br></div><div>El grano.</div><br><br><br><div>comida</div>",
                    ])
            ])

        try await importPackage(package)

        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["sustantivo\n\nComo arroz.", "arroz\n\nEl grano.\n\ncomida"]
            ])
    }

    // The stock kind Anki records tells it, also once its user changed the
    // templates, as the third note's.
    @Test(
        "a note of Basic (and reversed card), or of Basic (optional reversed card) with text in Add Reverse, becomes one card that goes both ways",
        arguments: schemas,
        [
            AnkiNote(type: .basicAndReversed, fields: ["perro", "dog"]),
            AnkiNote(type: .basicOptionalReversed, fields: ["perro", "dog", "y"]),
            AnkiNote(
                type: AnkiNoteType(
                    name: "Basic (and reversed card)", originalStockKind: 2, fields: ["Front", "Back"],
                    templates: [
                        AnkiCardTemplate(
                            name: "Card 1", question: "<div class=word>{{Front}}</div>",
                            answer: "{{FrontSide}}\n\n<hr id=answer>\n\n<div class=meaning>{{Back}}</div>"),
                        AnkiCardTemplate(
                            name: "Card 2", question: "<div class=meaning>{{Back}}</div>",
                            answer: "{{FrontSide}}\n\n<hr id=answer>\n\n<div class=word>{{Front}}</div>"),
                    ]),
                fields: ["perro", "dog"]),
        ])
    func aReversedNoteBecomesOneCardThatGoesBothWays(format: AnkiPackage.Format, note: AnkiNote) async throws {
        let outcome = try await importPackage(AnkiPackage(format: format, notes: [note]))

        #expect(outcome.added == 1)
        #expect(try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"]])
        #expect(try engine.cards().map(\.bothWays) == [true])
    }

    // Anki records the stock note type it made a note type from since
    // 2.1.62, so an older note type is told by its templates, whatever the
    // language its fields were named in, in any package.
    @Test(
        "a reversed note of a note type made before Anki recorded its stock kind becomes one card that goes both ways",
        arguments: everyVersion,
        [
            AnkiNote(type: AnkiNoteType.basicAndReversed.madeBeforeStockKinds, fields: ["perro", "dog"]),
            AnkiNote(
                type: AnkiNoteType(
                    name: "Básico (tarjeta invertida opcional)", fields: ["Anverso", "Reverso", "Añadir reverso"],
                    templates: [
                        AnkiCardTemplate(
                            name: "Tarjeta 1", question: "{{Anverso}}",
                            answer: "{{FrontSide}}\n\n<hr id=answer>\n\n{{Reverso}}"),
                        AnkiCardTemplate(
                            name: "Tarjeta 2", question: "{{#Añadir reverso}}{{Reverso}}{{/Añadir reverso}}",
                            answer: "{{FrontSide}}\n\n<hr id=answer>\n\n{{Anverso}}"),
                    ]),
                fields: ["perro", "dog", "sí"]),
        ])
    func aReversedNoteOfAnOlderNoteTypeBecomesOneCard(format: AnkiPackage.Format, note: AnkiNote) async throws {
        try await importPackage(AnkiPackage(format: format, notes: [note]))

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"]])
        #expect(try engine.cards().map(\.bothWays) == [true])
    }

    @Test("a note of another note type with two cards becomes two cards, each going one way", arguments: everyVersion)
    func aNoteOfAnotherTypeWithTwoCardsBecomesTwoCards(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [AnkiNote(type: .wordAndMeaning, fields: ["perro", "dog", "Mi perro ladra."])])

        try await importPackage(package)

        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"], ["dog", "perro\nMi perro ladra."]])
        #expect(try engine.cards().map(\.bothWays) == [false, false])
    }

    // Both ways is how a card is reviewed, as its progress, which an update
    // keeps too.
    @Test(
        "a reversed note repeats a card of the user's by its first card's front, and updates it keeping its own Both ways",
        arguments: schemas)
    func aReversedNoteRepeatsByItsFront(format: AnkiPackage.Format) async throws {
        try approveCard("gato", in: engine)
        try approveCard("dog", in: engine)
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basicAndReversed, fields: ["gato", "cat"]),
                AnkiNote(type: .basicAndReversed, fields: ["perro", "dog"]),
            ])
        let preview = try await engine.previewImport(of: file("Animales.apkg", package))

        let outcome = try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.repeatedCount == 1)
        #expect(outcome == ImportOutcome(added: 1, updated: 1, skipped: 0, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(
            cards.map { [$0.front, $0.back] } == [
                ["gato", "cat"], ["dog", "Lo que quiere decir «dog»."], ["perro", "dog"],
            ])
        #expect(cards.map(\.bothWays) == [false, false, true])
    }

    @Test("a note of Basic (optional reversed card) without text in Add Reverse comes in one way", arguments: schemas)
    func anOptionalReversedNoteWithoutAddReverseComesInOneWay(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [AnkiNote(type: .basicOptionalReversed, fields: ["gato", "cat", ""])])

        try await importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["gato", "cat"]])
        #expect(try engine.cards().map(\.bothWays) == [false])
    }

    @Test("a field shown only on the answer side, like Extra, comes in on the back", arguments: schemas)
    func aFieldShownOnTheAnswerComesInOnTheBack(format: AnkiPackage.Format) async throws {
        // A note type of someone's own, with a hint on the question, and an
        // example on the answer, or a line saying there's none.
        let vocabulary = AnkiNoteType(
            name: "Vocabulario", fields: ["Palabra", "Significado", "Ejemplo", "Pista"],
            templates: [
                AnkiCardTemplate(
                    name: "Tarjeta 1",
                    question: "{{Palabra}}{{#Pista}}<br>{{hint:Pista}}{{/Pista}}",
                    answer: """
                        {{FrontSide}}

                        <hr id=answer>

                        {{Significado}}
                        {{#Ejemplo}}<br><i>{{text:Ejemplo}}</i>{{/Ejemplo}}
                        {{^Ejemplo}}<br>Sin ejemplo.{{/Ejemplo}}
                        """)
            ])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: vocabulary,
                    fields: ["serendipia", "Un hallazgo por casualidad.", "Fue <b>pura</b> serendipia.", "Suerte"]),
                AnkiNote(type: vocabulary, fields: ["petricor", "El olor de la lluvia.", "<br>", ""]),
                AnkiNote(
                    type: .cloze,
                    fields: ["La {{c1::mitocondria}} produce energía.", "La llaman <i>la central</i> de la célula."]),
            ])

        try await importPackage(package)

        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["serendipia\nSuerte", "Un hallazgo por casualidad.\nFue pura serendipia."],
                ["petricor", "El olor de la lluvia.\nSin ejemplo."],
                [
                    "La [...] produce energía.",
                    "La mitocondria produce energía.\nLa llaman la central de la célula.",
                ],
            ])
    }

    @Test("a typed answer comes in on the back, also when the answer shows it through FrontSide", arguments: schemas)
    func aTypedAnswerComesInOnTheBack(format: AnkiPackage.Format) async throws {
        // Anki's Basic (type in the answer), and the reversed card of a
        // shared deck, whose answer is its question and the line, so Anki
        // shows the right answer where the box was, and moves the line above
        // it.
        let typing = AnkiNoteType(
            name: "Basic (type in the answer)", originalStockKind: 4, fields: ["Front", "Back"],
            templates: [
                AnkiCardTemplate(
                    name: "Card 1", question: "{{Front}}\n\n{{type:Back}}",
                    answer: "{{Front}}\n\n<hr id=answer>\n\n{{type:Back}}")
            ])
        let terms = AnkiNoteType(
            name: "Términos", fields: ["Término", "Definición"],
            templates: [
                AnkiCardTemplate(
                    name: "Definición", question: "{{Definición}}\n{{type:Término}}",
                    answer: "{{FrontSide}}\n\n<hr id=answer>\n\n")
            ])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: typing, fields: ["perro", "dog"]),
                AnkiNote(type: terms, fields: ["fémur", "El hueso del <b>muslo</b>."]),
            ])

        try await importPackage(package)

        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["perro", "dog"], ["El hueso del muslo.", "fémur"],
            ])
    }

    @Test(
        "a typed answer to a cloze comes once when its gaps say the same, and one compared without accents comes too",
        arguments: schemas)
    func typedAnswersToAClozeAndWithoutAccentsComeInOnTheBack(format: AnkiPackage.Format) async throws {
        // A cloze to type in, as Anki's manual has it, with no line, and a
        // card that compares what's typed without accents.
        let typedCloze = AnkiNoteType(
            name: "Cloze (type in the answer)", isCloze: true, fields: ["Text", "Back Extra"],
            templates: [
                AnkiCardTemplate(
                    name: "Cloze", question: "{{cloze:Text}}\n{{type:cloze:Text}}",
                    answer: "{{cloze:Text}}\n{{type:cloze:Text}}")
            ])
        let withoutAccents = AnkiNoteType(
            name: "Sin acentos", fields: ["Front", "Back"],
            templates: [
                AnkiCardTemplate(
                    name: "Card 1", question: "{{Front}}\n{{type:nc:Back}}", answer: "{{FrontSide}}\n<hr id=answer>")
            ])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: typedCloze,
                    fields: ["Todos los caminos llevan a {{c1::Roma}}, y {{c1::Roma}} no se hizo en un día.", ""]),
                AnkiNote(type: withoutAccents, fields: ["heart", "corazón"]),
            ])

        try await importPackage(package)

        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                [
                    "Todos los caminos llevan a [...], y [...] no se hizo en un día.",
                    "Todos los caminos llevan a Roma, y Roma no se hizo en un día. Roma",
                ],
                ["heart", "corazón"],
            ])
    }

    @Test(
        "a box to type the answer in shows nothing when only the answer has it, or it asks for a special field",
        arguments: schemas)
    func typedAnswersAnkiCantFillShowNothing(format: AnkiPackage.Format) async throws {
        // Anki's reviewer takes the right answer from the question's box,
        // and from the note's fields alone.
        let onTheAnswerOnly = AnkiNoteType(
            name: "Solo en la respuesta", fields: ["Front", "Back"],
            templates: [
                AnkiCardTemplate(
                    name: "Card 1", question: "{{Front}}", answer: "{{Front}}\n<hr id=answer>\n{{Back}}\n{{type:Back}}")
            ])
        let askingForTags = AnkiNoteType(
            name: "Etiquetas", fields: ["Front", "Back"],
            templates: [
                AnkiCardTemplate(
                    name: "Card 1", question: "{{Front}}\n{{type:Tags}}",
                    answer: "{{FrontSide}}\n<hr id=answer>\n{{Back}}")
            ])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: onTheAnswerOnly, fields: ["dog", "perro"]),
                AnkiNote(type: askingForTags, fields: ["cat", "gato"], tags: ["animales"]),
            ])

        try await importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["dog", "perro"], ["cat", "gato"]])
    }

    @Test(
        "furigana, from Anki's filter or in HTML, comes in as the reading in parentheses after its kanji, and kanji and kana as Anki shows them",
        arguments: schemas)
    func furiganaComesInAsTheReadingInParentheses(format: AnkiPackage.Format) async throws {
        // Shared Japanese decks' notes: Anki draws the reading small over the
        // kanji, which Ficha's plain text can't.
        let japanese = AnkiNoteType(
            name: "Japonés", fields: ["Oración", "Significado"],
            templates: [
                AnkiCardTemplate(
                    name: "Card 1", question: "{{kanji:Oración}}",
                    answer: "{{FrontSide}}\n<hr id=answer>\n{{furigana:Oración}}<br>{{kana:Oración}}<br>{{Significado}}"
                )
            ])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: japanese,
                    fields: ["それはとってもいい&nbsp;話[はなし]だ。この 本[ほん]も。[sound:hanashi.mp3]", "Es una muy buena historia."]),
                AnkiNote(
                    type: .basic,
                    fields: [
                        "<ruby>私<rt>わたし</rt></ruby>の<ruby><rb>名前</rb><rp>(</rp><rt>なまえ</rt><rp>)</rp></ruby>",
                        "mi nombre",
                    ]),
                // HTML lets a ruby's text and parentheses go without their
                // closing tags, and a browser shows no space at their ends.
                AnkiNote(
                    type: .basic,
                    fields: [
                        "<ruby>漢<rp>(<rt> かん <rp>)</ruby><ruby>字<rt>じ<rb>辞</rb><rt>じ</rt><rb>典</rb><rt>てん</rt>\n</ruby>です",
                        "Es un diccionario de kanji.",
                    ]),
            ])

        try await importPackage(package)

        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                [
                    "それはとってもいい話だ。この本も。",
                    """
                    それはとってもいい話（はなし）だ。この本（ほん）も。
                    それはとってもいいはなしだ。このほんも。
                    Es una muy buena historia.
                    """,
                ],
                ["私（わたし）の名前（なまえ）", "mi nombre"],
                ["漢（かん）字（じ）辞（じ）典（てん）です", "Es un diccionario de kanji."],
            ])
    }

    // Shared chemistry and pharmacology decks' notes. Unicode has no
    // subscript d or q, and its other small letters, such as the i
    // below, are phonetic signs, which the system font mostly lacks.
    @Test(
        "a superscript or a subscript comes in as Unicode's when Unicode has each of its characters as one, and as its text otherwise",
        arguments: schemas)
    func superscriptsAndSubscriptsComeInAsUnicodes(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic,
                    fields: [
                        "SO<sub>4</sub><sup>2-</sup>", "Ca<sup>2+</sup>, β<sub>1</sub> y x<sup><b>(n−1)</b></sup>",
                    ]),
                AnkiNote(
                    type: .basic,
                    fields: [
                        "V<sub>max</sub> y K<sub style=\"font-weight: bold;\">m</sub>",
                        "V<sub>d</sub>, G<sub>q</sub>, G<sub>i</sub>, GABA<sub>A</sub> y el 2<sup>nd</sup>",
                    ]),
                AnkiNote(type: .cloze, fields: ["La {{c1::K<sub>m</sub>}} de la enzima", ""]),
                // A browser shows the spaces and the line break at its own
                // size, a line break takes away the spaces before it, and
                // what isn't closed isn't a superscript in Ficha.
                AnkiNote(
                    type: .basic,
                    fields: ["Na<sup>+ ions</sup> y 10 <sup> 3 </sup>m", "a&nbsp;&nbsp;<sup><br>23</sup> y x<sup>2"]),
            ])

        try await importPackage(package)

        let sides = try engine.cards().map { [$0.front, $0.back] }
        #expect(
            sides == [
                ["SO₄²⁻", "Ca²⁺, β₁ y x⁽ⁿ⁻¹⁾"],
                ["Vₘₐₓ y Kₘ", "Vd, Gq, Gi, GABAA y el 2nd"],
                ["La [...] de la enzima", "La Kₘ de la enzima"],
                ["Na+ ions y 10 ³ m", "a\n²³ y x2"],
            ])
    }

    @Test(
        "a cloze note with two gaps becomes two cards, each hiding its own gap, a hint shown as \"[hint]\"",
        arguments: schemas)
    func aClozeNoteBecomesACardForEachGap(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .cloze,
                    fields: ["{{c1::Buenos Aires}} es la capital de {{c2::la Argentina::un país}}.", ""])
            ])

        try await importPackage(package)

        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["[...] es la capital de la Argentina.", "Buenos Aires es la capital de la Argentina."],
                ["Buenos Aires es la capital de [un país].", "Buenos Aires es la capital de la Argentina."],
            ])
    }

    // Default, which every package has, names no subject, so it gives no
    // tag, not even to the decks below it.
    @Test(
        "subdecks become one tag per part, Anki tags come as they are, an underscore as a space, and renamed or removed tags apply",
        arguments: schemas)
    func decksAndAnkiTagsBecomeTags(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["fémur", "El hueso del muslo."], tags: ["repaso", "hueso_largo"],
                    deck: "Medicina::Anatomía"),
                AnkiNote(
                    type: .basic, fields: ["sístole", "La contracción del corazón."], tags: ["repaso"],
                    deck: "Medicina::Fisiología"),
                AnkiNote(
                    type: .basic, fields: ["arritmia", "Un ritmo irregular del corazón."], tags: ["Medicina::Cardio"]),
                AnkiNote(
                    type: .basic, fields: ["gripe", "Una infección por el virus de la influenza."],
                    deck: "Default::Viejas"),
            ])
        let preview = try await engine.previewImport(of: file("Medicina.apkg", package))

        try engine.importCards(preview, choosing: ImportChoices(tagNames: ["Medicina": "medicina", "repaso": " "]))

        #expect(
            preview.proposedTags == [
                "Medicina", "Anatomía", "repaso", "hueso largo", "Fisiología", "Medicina::Cardio", "Viejas",
            ])
        #expect(
            try engine.cards().map(\.tags) == [
                ["medicina", "Anatomía", "hueso largo"], ["medicina", "Fisiología"], ["Medicina::Cardio"], ["Viejas"],
            ])
    }

    // A side with only a sound comes in with it, or stays out for want of
    // it: AnkiSoundImportingTests.
    @Test(
        "a card whose side holds only an image on the web, and an Image Occlusion card, stay out with their reasons",
        arguments: schemas)
    func webImageOnlySidesAndImageOcclusionStayOut(format: AnkiPackage.Format) async throws {
        // A note type whose template names a field it lacks, for which Anki
        // shows an error.
        let broken = AnkiNoteType(
            name: "Rota", fields: ["Frente", "Dorso"],
            templates: [AnkiCardTemplate(name: "Tarjeta 1", question: "{{Frente}}", answer: "{{Reverso}}")])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["<img src=\"https://example.com/perro.jpg\">", "dog"]),
                AnkiNote(type: .basic, fields: ["gato", "cat [sound:cat.mp3]"]),
                AnkiNote(
                    type: .imageOcclusion,
                    fields: [
                        """
                        {{c1::image-occlusion:rect:left=.1:top=.2:width=.3:height=.1:oi=1}}<br>\
                        {{c2::image-occlusion:ellipse:left=.5:top=.6:rx=.1:ry=.1:oi=1}}
                        """,
                        "<img src=\"esqueleto.png\">", "Los huesos", "", "",
                    ]),
                AnkiNote(type: broken, fields: ["casa", "house"]),
            ])

        let preview = try await engine.previewImport(of: file("Inglés.apkg", package))
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(
            preview.leftOut == [
                LeftOutLine(line: 1, reason: .emptyAnkiSide), LeftOutLine(line: 3, reason: .ankiImageOcclusion),
                LeftOutLine(line: 4, reason: .ankiImageOcclusion), LeftOutLine(line: 5, reason: .brokenAnkiTemplate),
            ])
        #expect(try engine.cards().map { [$0.front, $0.back] } == [["gato", "cat"]])
    }

    // Shared decks still carry it, under its own name or another, and its
    // cards would show the whole image, the answer with it.
    @Test(
        "a card of Image Occlusion Enhanced, the add-on before Anki's own, stays out as an Image Occlusion card",
        arguments: schemas)
    func imageOcclusionEnhancedStaysOut(format: AnkiPackage.Format) async throws {
        var renamed = AnkiNoteType.imageOcclusionEnhanced
        renamed.name = "Oclusión"
        let fields = [
            "e2f1-ao-1", "Los huesos", "<img src=\"esqueleto.png\">", "<img src=\"e2f1-ao-1-Q.svg\">", "", "", "",
            "", "", "<img src=\"e2f1-ao-1-A.svg\">", "<img src=\"e2f1-ao-O.svg\">",
        ]
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .imageOcclusionEnhanced, fields: fields),
                AnkiNote(type: renamed, fields: fields),
                AnkiNote(type: .basic, fields: ["gato", "cat"]),
            ])

        let preview = try await engine.previewImport(of: file("Huesos.apkg", package))
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(
            preview.leftOut == [
                LeftOutLine(line: 1, reason: .ankiImageOcclusion), LeftOutLine(line: 2, reason: .ankiImageOcclusion),
            ])
        #expect(try engine.cards().map { [$0.front, $0.back] } == [["gato", "cat"]])
    }

    // Anki 2.1 before 2.1.50 also wrote no `meta`, and its collection.anki21
    // beside a placeholder collection.anki2, which Ficha never reads.
    @Test(
        "an Anki 2.0 package with no meta imports, as does a 2.1 one from its newer collection",
        arguments: [AnkiPackage.Format.anki20, .anki21])
    func packagesWithoutMetaImport(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(format: format, notes: [AnkiNote(type: .basic, fields: ["perro", "dog"])])

        try await importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"]])
    }

    @Test(
        "every card comes in new, the new ones first in Anki's order of new cards, then the rest by note and template",
        arguments: schemas)
    func everyCardComesInNewInAnkisOrder(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 10)),
                AnkiNote(type: .basic, fields: ["dos", "two"], progress: .newAt(position: 5)),
                AnkiNote(type: .wordAndMeaning, fields: ["tres", "three", ""], progress: .newAt(position: 2)),
                AnkiNote(
                    type: .wordAndMeaning, fields: ["cuatro", "four", ""], progress: .review(due: 5, interval: 3)),
            ])

        try await importPackage(package)

        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["tres", "three", "dos", "uno", "cuatro", "four"])
        #expect(try cards.allSatisfy { try engine.standing(of: $0.id, on: ReviewSettings.defaults.ladder) == .new })
    }

    @Test(
        "repeated cards are updated with the deck's back and tags, keeping their type and source, or skipped, as chosen",
        arguments: schemas, [ImportChoices.RepeatedCards.update, .skip])
    func repeatedCardsAreUpdatedOrSkipped(format: AnkiPackage.Format, choice: ImportChoices.RepeatedCards) async throws
    {
        let heart = try approve(
            card(.word, front: "Corazón", back: "Un órgano.", tags: ["biología"], source: "Un libro"), in: engine)
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["corazón", "El órgano que bombea la sangre."], tags: ["anatomía"],
                    deck: "Medicina"),
                AnkiNote(type: .basic, fields: ["pulmón", "El órgano de la respiración."], deck: "Medicina"),
            ])
        let preview = try await engine.previewImport(of: file("Medicina.apkg", package))

        let outcome = try engine.importCards(preview, choosing: ImportChoices(repeatedCards: choice))

        #expect(preview.repeatedCount == 1)
        let cards = try engine.cards()
        #expect(cards.first?.id == heart.id)
        #expect(cards.dropFirst().map(\.front) == ["pulmón"])
        switch choice {
        case .update:
            #expect(outcome == ImportOutcome(added: 1, updated: 1, skipped: 0, copyBeforeImport: nil))
            #expect(
                cards.first.flatMap(content(of:))
                    == (try card(
                        .word, front: "Corazón", back: "El órgano que bombea la sangre.",
                        tags: ["biología", "Medicina", "anatomía"], source: "Un libro")))
        case .skip:
            #expect(outcome == ImportOutcome(added: 1, updated: 0, skipped: 1, copyBeforeImport: nil))
            #expect(cards.first == heart)
        }
    }

    @Test("a deck whose package holds images and sounds comes in", arguments: schemas)
    func aDeckWithMediaComesIn(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["perro <img src=\"perro.jpg\">", "dog [sound:dog.mp3]"]),
                AnkiNote(type: .basic, fields: ["gato", "cat"]),
            ],
            media: ["perro.jpg": Data("una foto".utf8), "dog.mp3": Data("un ladrido".utf8)])

        try await importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"], ["gato", "cat"]])
    }

    // Its collection decompresses to several times the buffer zstd hands
    // out at a time, 128 KB.
    @Test("a long card comes in whole from a package current Anki exports by default")
    func aLongCardComesInWhole() async throws {
        let back = Array(repeating: "En un lugar de la Mancha, de cuyo nombre no quiero acordarme.", count: 8_000)
        let package = AnkiPackage(
            format: .current,
            notes: [AnkiNote(type: .basic, fields: ["El Quijote", back.joined(separator: "<br>")])])

        try await importPackage(package)

        #expect(try engine.cards().map(\.back) == [back.joined(separator: "\n")])
    }

    @Test(
        "a package with a number beyond what Ficha counts with can't be read, and Ficha goes on",
        arguments: schemas, DamagedNumber.allCases)
    func aPackageWithANumberOutOfRangeCantBeRead(format: AnkiPackage.Format, number: DamagedNumber) async throws {
        let damaged = try file("Dañado.apkg", number.package(format: format))

        await #expect(throws: EngineError.unreadableFile("Dañado.apkg", .unreadableAnkiPackage)) {
            try await engine.previewImport(of: damaged)
        }
    }

    // The placeholder holds a note asking to update Anki, which would come
    // in as a card of its own.
    @Test(
        "a package current Anki exports by default imports from its collection.anki21b, never the placeholder beside it"
    )
    func aCurrentPackageNeverReadsItsPlaceholder() async throws {
        let package = AnkiPackage(format: .current, notes: [AnkiNote(type: .basic, fields: ["perro", "dog"])])

        try await importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"]])
    }
}

/// A number a damaged package holds, too large or too small for what Ficha
/// works out from it.
enum DamagedNumber: CaseIterable, CustomTestStringConvertible {
    /// A review card's interval, in days, as long as a number can be.
    case interval
    /// A review card's due day, the last a number can count.
    case dueDay
    /// A cloze card's template index, as large as a number can be.
    case templateIndex
    /// The collection's creation offset, as small as a number can be.
    case creationOffset

    var testDescription: String {
        "\(self)"
    }

    /// A package of `format` with the number.
    func package(format: AnkiPackage.Format) -> AnkiPackage {
        switch self {
        case .interval:
            AnkiPackage(
                format: format,
                notes: [
                    AnkiNote(type: .basic, fields: ["corazón", "heart"], progress: .review(due: 30, interval: .max))
                ])
        case .dueDay:
            AnkiPackage(
                format: format,
                notes: [
                    AnkiNote(type: .basic, fields: ["corazón", "heart"], progress: .review(due: .max, interval: 10))
                ])
        case .templateIndex:
            AnkiPackage(
                format: format,
                notes: [AnkiNote(type: .cloze, fields: ["El {{c1::corazón}} late.", ""], damagedTemplateIndex: .max)])
        case .creationOffset:
            AnkiPackage(
                format: format, notes: [AnkiNote(type: .basic, fields: ["corazón", "heart"])], creationOffset: .min)
        }
    }
}
