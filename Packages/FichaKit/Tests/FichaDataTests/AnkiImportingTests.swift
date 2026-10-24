import FichaCore
import FichaData
import Foundation
import Testing

/// A package of each schema Anki writes: schema 11, as current Anki exports
/// a deck with "Support older Anki versions" ticked, and as older Ankis do;
/// and schema 18, compressed with zstd, as current Anki exports it by
/// default.
private let schemas: [AnkiPackage.Format] = [.supportOlderAnkiVersions, .current]

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
    ) throws -> ImportOutcome {
        try engine.importCards(engine.previewImport(of: file(name, package)), choosing: choices)
    }

    @Test("a Basic note becomes one card, with its Front and Back as plain text", arguments: schemas)
    func aBasicNoteBecomesOneCard(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic,
                    fields: ["<b>corazón</b>", "El órgano que bombea<br>la sangre&nbsp;por el cuerpo."])
            ])

        let outcome = try importPackage(package)

        #expect(outcome == ImportOutcome(added: 1, updated: 0, skipped: 0, copyBeforeImport: nil))
        let card = try #require(try engine.cards().first)
        #expect([card.front, card.back] == ["corazón", "El órgano que bombea\nla sangre por el cuerpo."])
        #expect(card.type == nil)
        #expect(card.source == nil)
    }

    @Test("a reversed note becomes two cards", arguments: schemas)
    func aReversedNoteBecomesTwoCards(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basicAndReversed, fields: ["perro", "dog"])
            ])

        try importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"], ["dog", "perro"]])
    }

    @Test("a field shown only on the answer side, like Extra, comes in on the back", arguments: schemas)
    func aFieldShownOnTheAnswerComesInOnTheBack(format: AnkiPackage.Format) throws {
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

        try importPackage(package)

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
    func aTypedAnswerComesInOnTheBack(format: AnkiPackage.Format) throws {
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

        try importPackage(package)

        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["perro", "dog"], ["El hueso del muslo.", "fémur"],
            ])
    }

    @Test(
        "a typed answer to a cloze comes once when its gaps say the same, and one compared without accents comes too",
        arguments: schemas)
    func typedAnswersToAClozeAndWithoutAccentsComeInOnTheBack(format: AnkiPackage.Format) throws {
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

        try importPackage(package)

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
    func typedAnswersAnkiCantFillShowNothing(format: AnkiPackage.Format) throws {
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

        try importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["dog", "perro"], ["cat", "gato"]])
    }

    @Test(
        "a cloze note with two gaps becomes two cards, each hiding its own gap, a hint shown as \"[hint]\"",
        arguments: schemas)
    func aClozeNoteBecomesACardForEachGap(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .cloze,
                    fields: ["{{c1::Buenos Aires}} es la capital de {{c2::la Argentina::un país}}.", ""])
            ])

        try importPackage(package)

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
    func decksAndAnkiTagsBecomeTags(format: AnkiPackage.Format) throws {
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
        let preview = try engine.previewImport(of: file("Medicina.apkg", package))

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

    @Test(
        "a card whose side holds only a sound, and an Image Occlusion card, stay out with their reasons",
        arguments: schemas)
    func soundOnlySidesAndImageOcclusionStayOut(format: AnkiPackage.Format) throws {
        // A note type whose template names a field it lacks, for which Anki
        // shows an error.
        let broken = AnkiNoteType(
            name: "Rota", fields: ["Frente", "Dorso"],
            templates: [AnkiCardTemplate(name: "Tarjeta 1", question: "{{Frente}}", answer: "{{Reverso}}")])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["[sound:perro.mp3]", "dog"]),
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

        let preview = try engine.previewImport(of: file("Inglés.apkg", package))
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
    func imageOcclusionEnhancedStaysOut(format: AnkiPackage.Format) throws {
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

        let preview = try engine.previewImport(of: file("Huesos.apkg", package))
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
    func packagesWithoutMetaImport(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(format: format, notes: [AnkiNote(type: .basic, fields: ["perro", "dog"])])

        try importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"]])
    }

    @Test(
        "every card comes in new, the new ones first in Anki's order of new cards, then the rest by note and template",
        arguments: schemas)
    func everyCardComesInNewInAnkisOrder(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 10)),
                AnkiNote(type: .basic, fields: ["dos", "two"], progress: .newAt(position: 5)),
                AnkiNote(type: .basicAndReversed, fields: ["tres", "three"], progress: .newAt(position: 2)),
                AnkiNote(type: .basicAndReversed, fields: ["cuatro", "four"], progress: .review(due: 5, interval: 3)),
            ])

        try importPackage(package)

        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["tres", "three", "dos", "uno", "cuatro", "four"])
        #expect(try cards.allSatisfy { try engine.standing(of: $0.id, on: ReviewSettings.defaults.ladder) == .new })
    }

    @Test(
        "repeated cards are updated with the deck's back and tags, keeping their type and source, or skipped, as chosen",
        arguments: schemas, [ImportChoices.RepeatedCards.update, .skip])
    func repeatedCardsAreUpdatedOrSkipped(format: AnkiPackage.Format, choice: ImportChoices.RepeatedCards) throws {
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
        let preview = try engine.previewImport(of: file("Medicina.apkg", package))

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
    func aDeckWithMediaComesIn(format: AnkiPackage.Format) throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["perro <img src=\"perro.jpg\">", "dog [sound:dog.mp3]"]),
                AnkiNote(type: .basic, fields: ["gato", "cat"]),
            ],
            media: ["perro.jpg": Data("una foto".utf8), "dog.mp3": Data("un ladrido".utf8)])

        try importPackage(package)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["perro", "dog"], ["gato", "cat"]])
    }

    // Its collection decompresses to several times the buffer zstd hands
    // out at a time, 128 KB.
    @Test("a long card comes in whole from a package current Anki exports by default")
    func aLongCardComesInWhole() throws {
        let back = Array(repeating: "En un lugar de la Mancha, de cuyo nombre no quiero acordarme.", count: 8_000)
        let package = AnkiPackage(
            format: .current,
            notes: [AnkiNote(type: .basic, fields: ["El Quijote", back.joined(separator: "<br>")])])

        try importPackage(package)

        #expect(try engine.cards().map(\.back) == [back.joined(separator: "\n")])
    }

    @Test(
        "a package with a number beyond what Ficha counts with can't be read, and Ficha goes on",
        arguments: schemas, DamagedNumber.allCases)
    func aPackageWithANumberOutOfRangeCantBeRead(format: AnkiPackage.Format, number: DamagedNumber) throws {
        let damaged = try file("Dañado.apkg", number.package(format: format))

        #expect(throws: EngineError.unreadableFile("Dañado.apkg", .unreadableAnkiPackage)) {
            try engine.previewImport(of: damaged)
        }
    }

    // The placeholder holds a note asking to update Anki, which would come
    // in as a card of its own.
    @Test(
        "a package current Anki exports by default imports from its collection.anki21b, never the placeholder beside it"
    )
    func aCurrentPackageNeverReadsItsPlaceholder() throws {
        let package = AnkiPackage(format: .current, notes: [AnkiNote(type: .basic, fields: ["perro", "dog"])])

        try importPackage(package)

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
