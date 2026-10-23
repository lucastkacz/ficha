import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on importing a text file of cards: what the preview reports, and
/// which cards there are once the import is done, from files the tests write
/// in a folder of their own, into an engine in memory on a Mac in Buenos
/// Aires.
final class ImportingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the files it imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaImportingTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes `text` as UTF-8 to a file named `name` in the test's folder,
    /// and returns the file.
    private func file(_ name: String, _ text: String) throws -> URL {
        let file = folder.appending(path: name)
        try Data(text.utf8).write(to: file)
        return file
    }

    /// Previews the file and imports it with `choices`, and returns what the
    /// import did.
    @discardableResult
    private func importFile(_ file: URL, choosing choices: ImportChoices = ImportChoices()) throws -> ImportOutcome {
        try engine.importCards(engine.previewImport(of: file), choosing: choices)
    }

    @Test(
        "a tab-separated, a comma-separated and a semicolon-separated file each import their cards, with quoted fields holding separators and line breaks",
        arguments: ["\t", ",", ";"]
    )
    func separatedFilesImportTheirCards(separator: String) throws {
        let lines = [
            "serendipia\(separator)Un hallazgo por casualidad.",
            "petricor\(separator)\"El olor de la lluvia\(separator) sobre la tierra seca.\"",
            "\"¿Quién dijo \"\"Pienso\(separator) luego existo\"\"?\"\(separator)\"Descartes.",
            "En el Discurso del método.\"",
        ]
        let file = try file("vocabulario.txt", lines.joined(separator: "\n") + "\n")

        let outcome = try importFile(file)

        #expect(outcome == ImportOutcome(added: 3, updated: 0, skipped: 0, copyBeforeImport: nil))
        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["serendipia", "Un hallazgo por casualidad."],
                ["petricor", "El olor de la lluvia\(separator) sobre la tierra seca."],
                ["¿Quién dijo \"Pienso\(separator) luego existo\"?", "Descartes.\nEn el Discurso del método."],
            ])
    }

    // As Anki 2.1.55 and later write it, with the deck and the note type
    // included: Anki's tags hold no spaces, and its own subdecks are `::`.
    @Test(
        "a file exported by Anki as Notes in Plain Text, with its headers and HTML, imports its fronts, backs and tags as plain text"
    )
    func anAnkiExportImportsAsPlainText() throws {
        let file = try file(
            "Biología.txt",
            """
            #separator:tab
            #html:true
            #notetype column:1
            #deck column:2
            #tags column:5
            Basic\tBiología::Células\t<b>mitocondria</b>\tLa parte de la célula<br>que produce su energía.\tbiología célula_eucariota
            Basic\tBiología\t&iquest;Qu&eacute; es el ADN?\t<div>El ácido desoxirribonucleico.</div><div><br></div><div>Lleva la&nbsp;información genética.</div>\tbiología
            Basic\tBiología\tósmosis\t"El paso del agua por una membrana <i>semipermeable</i>; ""&lt;de menos a más&gt;"" &amp; sin energía."\t

            """)

        try importFile(file)

        let cards = try engine.cards()
        #expect(
            cards.map { [$0.front, $0.back] } == [
                ["mitocondria", "La parte de la célula\nque produce su energía."],
                [
                    "¿Qué es el ADN?",
                    "El ácido desoxirribonucleico.\n\nLleva la información genética.",
                ],
                ["ósmosis", "El paso del agua por una membrana semipermeable; \"<de menos a más>\" & sin energía."],
            ])
        #expect(
            cards.map(\.tags) == [
                ["biología", "célula eucariota", "Biología"], ["biología", "Biología"], ["Biología"],
            ])
    }

    // The headers an export writes, for Ficha and Anki to read it back.
    @Test("a file with the headers Ficha writes reads every column by its name, and its tags by #tags column")
    func aFileWithFichasHeadersReadsEveryColumn() throws {
        let file = try file(
            "Exportadas.txt",
            """
            #separator:tab
            #html:false
            #columns:Front\tBack\tTags\tType\tSource
            #tags column:3
            ubuntu\tSoy porque somos.\tfilosofía ética_africana\tconcept\tDesmond Tutu
            "Pienso, luego existo."\t"Descartes,
            en el Discurso del método."\t\tquote\t

            """)

        try importFile(file, choosing: ImportChoices(tagNames: ["Exportadas": ""]))

        #expect(
            try engine.cards().map { [$0.front, $0.back, $0.tags.joined(separator: "|"), $0.source ?? "-"] } == [
                ["ubuntu", "Soy porque somos.", "filosofía|ética africana", "Desmond Tutu"],
                ["Pienso, luego existo.", "Descartes,\nen el Discurso del método.", "", "-"],
            ])
        #expect(try engine.cards().map(\.type) == [.concept, .quote])
    }

    @Test(
        "a file with no headers reads front, back, tags, type and source in that order, and type and source can be missing"
    )
    func aFileWithNoHeadersReadsItsColumnsInOrder() throws {
        let file = try file(
            "mezcla.csv",
            """
            ubuntu,Soy porque somos.,filosofía ética_africana,concept,Desmond Tutu
            "¿Cuál es la capital de Mongolia?",Ulán Bator.,geografía Asia
            petricor,El olor de la lluvia.,,Word
            serendipia,Un hallazgo por casualidad.
            """)

        try importFile(file, choosing: ImportChoices(tagNames: ["mezcla": ""]))

        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["ubuntu", "¿Cuál es la capital de Mongolia?", "petricor", "serendipia"])
        #expect(
            cards.map(\.back) == [
                "Soy porque somos.", "Ulán Bator.", "El olor de la lluvia.", "Un hallazgo por casualidad.",
            ])
        #expect(cards.map(\.tags) == [["filosofía", "ética africana"], ["geografía", "Asia"], [], []])
        #expect(cards.map(\.type) == [.concept, nil, .word, nil])
        #expect(cards.map(\.source) == ["Desmond Tutu", nil, nil, nil])
    }

    @Test("unreadable lines are listed with their numbers and reasons, and the rest come in")
    func unreadableLinesAreListedAndTheRestComeIn() throws {
        let file = try file(
            "vocabulario.txt",
            """
            # Palabras de la semana
            serendipia\tUn hallazgo por casualidad.
            petricor
            \tUna palabra sin frente.
            efímero\t""
            ubicuo\tQue está en todas partes.\t\tadjective
            "lacónico" breve\tQue dice mucho en pocas palabras.
            resiliencia\t"La capacidad de reponerse.
            Y de adaptarse."
            quimera\t"Un sueño imposible.
            inefable\tQue no se puede explicar con palabras.
            """)

        let preview = try engine.previewImport(of: file)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(
            preview.leftOut == [
                LeftOutLine(line: 3, reason: .oneColumn),
                LeftOutLine(line: 4, reason: .blankFront),
                LeftOutLine(line: 5, reason: .blankBack),
                LeftOutLine(line: 6, reason: .unknownType("adjective")),
                LeftOutLine(line: 7, reason: .strayQuote),
                LeftOutLine(line: 10, reason: .unclosedQuote),
            ])
        #expect(preview.cardCount == 3)
        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["serendipia", "Un hallazgo por casualidad."],
                ["resiliencia", "La capacidad de reponerse.\nY de adaptarse."],
                ["inefable", "Que no se puede explicar con palabras."],
            ])
    }

    @Test("the proposed tag goes on every imported card, a renamed one too, and none when removed")
    func theProposedTagGoesOnEveryImportedCard() throws {
        let capitals = try file("Capitales.txt", "Mongolia\tUlán Bator.\ttema_1\nKenia\tNairobi.\n")
        let rivers = try file("Ríos.tsv", "Nilo\tEl río más largo de África.\n")
        let lakes = try file("Lagos.csv", "Titicaca,El lago navegable más alto del mundo.\n")

        let preview = try engine.previewImport(of: capitals)
        try engine.importCards(preview, choosing: ImportChoices())
        try importFile(rivers, choosing: ImportChoices(tagNames: ["Ríos": " geografía "]))
        try importFile(lakes, choosing: ImportChoices(tagNames: ["Lagos": ""]))

        #expect(preview.proposedTags == ["Capitales"])
        #expect(try engine.cards().map(\.tags) == [["tema 1", "Capitales"], ["Capitales"], ["geografía"], []])
    }

    @Test(
        "repeated cards are updated with everything the file gives them but their front, keeping their step and review log"
    )
    func repeatedCardsAreUpdatedKeepingTheirStepAndReviewLog() throws {
        let serendipia = try approve(
            card(.word, front: "serendipia", back: "Un hallazgo.", tags: ["palabras"], source: "Un libro"), in: engine)
        let petricor = try approve(
            card(.concept, front: "petricor", back: "Un olor.", tags: ["lenguaje"], source: "Wikipedia"), in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        try engine.meet(petricor)
        let ladder = ReviewSettings.defaults.ladder
        let standings = try [serendipia, petricor].map { try engine.standing(of: $0.id, on: ladder) }
        let reviewLog = try engine.reviewLog()
        let file = try file(
            "Palabras.txt",
            """
            SERENDÍPIA\tUn hallazgo valioso, por casualidad.\tvocabulario\tquestion\t
            petricor\tEl olor de la tierra mojada.
            efímero\tQue dura poco.
            """)

        let preview = try engine.previewImport(of: file)
        let outcome = try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.repeatedCount == 2)
        #expect(preview.newCount == 1)
        #expect(outcome == ImportOutcome(added: 1, updated: 2, skipped: 0, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["serendipia", "petricor", "efímero"])
        #expect(
            cards.map(\.back) == [
                "Un hallazgo valioso, por casualidad.", "El olor de la tierra mojada.", "Que dura poco.",
            ])
        #expect(cards.map(\.type) == [.question, .concept, nil])
        #expect(cards.map(\.tags) == [["vocabulario", "Palabras"], ["lenguaje", "Palabras"], ["Palabras"]])
        #expect(cards.map(\.source) == [nil, "Wikipedia", nil])
        #expect(try [serendipia, petricor].map { try engine.standing(of: $0.id, on: ladder) } == standings)
        #expect(try engine.reviewLog() == reviewLog)
    }

    @Test("repeated cards are skipped when chosen, and stay as they were")
    func repeatedCardsAreSkippedWhenChosen() throws {
        let serendipia = try approve(
            card(.word, front: "serendipia", back: "Un hallazgo.", tags: ["palabras"]), in: engine)
        let file = try file("Palabras.txt", "serendipia\tUn hallazgo valioso.\nefímero\tQue dura poco.\n")

        let outcome = try importFile(file, choosing: ImportChoices(repeatedCards: .skip))

        #expect(outcome == ImportOutcome(added: 1, updated: 0, skipped: 1, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(cards.first == serendipia)
        #expect(cards.map(\.front) == ["serendipia", "efímero"])
    }

    // Once with each card's first view as new cards come up, a day apart.
    @Test("imported new cards come up for their first view in the file's order")
    func importedNewCardsComeUpInTheFilesOrder() throws {
        let file = try file("Orden.txt", "zeta\tLa última letra.\nalfa\tLa primera letra.\nmu\tUna del medio.\n")
        try importFile(file)

        var firstViews: [String] = []
        for _ in 0..<3 {
            for case .firstView(let card) in try engine.reviewNow(.defaults) {
                firstViews.append(card.front)
                try engine.meet(card)
            }
            time.advance(by: days(1))
        }

        #expect(firstViews == ["zeta", "alfa", "mu"])
    }

    @Test("a file that isn't UTF-8 text, or whose headers say what Ficha can't follow, isn't read at all")
    func aFileFichaCantFollowIsntRead() throws {
        let latin1 = folder.appending(path: "Latin-1.txt")
        try #require("año\tyear\n".data(using: .isoLatin1)).write(to: latin1)
        let dashes = try file("Guiones.txt", "#separator:dash\naño-year\n")
        let numberless = try file("Etiquetas.txt", "#tags column:third\naño\tyear\tpalabras\n")
        let unnamed = try file("Columnas.txt", "#separator:comma\n#columns:Pregunta,Respuesta\naño,year\n")
        let missing = folder.appending(path: "Nada.txt")

        #expect(throws: EngineError.unreadableFile("Latin-1.txt", .notUTF8)) { try engine.previewImport(of: latin1) }
        #expect(throws: EngineError.unreadableFile("Guiones.txt", .unknownSeparator("dash"))) {
            try engine.previewImport(of: dashes)
        }
        #expect(
            throws: EngineError.unreadableFile(
                "Etiquetas.txt", .unknownColumnNumber(header: "tags column", value: "third"))
        ) {
            try engine.previewImport(of: numberless)
        }
        #expect(throws: EngineError.unreadableFile("Columnas.txt", .missingColumn(.front))) {
            try engine.previewImport(of: unnamed)
        }
        #expect(throws: EngineError.unreadableFile("Nada.txt", .cannotOpen)) { try engine.previewImport(of: missing) }
    }

    @Test("the import saves a copy before an import, and restoring it brings back the cards as they were")
    func restoringTheCopyBeforeAnImportUndoesIt() throws {
        let engine = try Engine(
            location: .folder(folder.appending(path: "Ficha", directoryHint: .isDirectory)), time: time,
            calendar: calendar)
        try approve(card(.word, front: "serendipia", back: "Un hallazgo."), in: engine)
        let before = try engine.cards()
        let file = try file("Palabras.txt", "serendipia\tUn hallazgo valioso.\nefímero\tQue dura poco.\n")

        let outcome = try engine.importCards(engine.previewImport(of: file), choosing: ImportChoices())
        let imported = try engine.cards()
        time.advance(by: minutes(1))
        let copy = try #require(outcome.copyBeforeImport)
        try engine.restore(copy.name)

        #expect(copy.kind == .beforeImport)
        #expect(try engine.copies().contains(copy))
        #expect(imported.count == 2)
        #expect(try engine.cards() == before)
    }
}
