import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on how a deck's `.ficha` comes in (#542): how its text file of cards
/// reads, and which cards there are once its deck is added, from files the
/// tests write in a folder of their own, into an engine in memory on a Mac in
/// Buenos Aires.
final class ImportingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the decks' `.ficha`s it adds.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaImportingTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes a deck's `.ficha` named `name` in the test's folder, with
    /// `text` as its text file, and returns the file.
    private func file(_ name: String, _ text: String) throws -> URL {
        let file = folder.appending(path: name)
        try writeDeckFile(at: file, text: text)
        return file
    }

    @Test(
        "a deck's .ficha whose text file is tab-separated, comma-separated or semicolon-separated brings its cards, with quoted fields holding separators and line breaks",
        .bug(id: 542),
        arguments: ["\t", ",", ";"]
    )
    func separatedFilesImportTheirCards(separator: String) async throws {
        let lines = [
            "serendipia\(separator)Un hallazgo por casualidad.",
            "petricor\(separator)\"El olor de la lluvia\(separator) sobre la tierra seca.\"",
            "\"¿Quién dijo \"\"Pienso\(separator) luego existo\"\"?\"\(separator)\"Descartes.",
            "En el Discurso del método.\"",
        ]
        let file = try file("vocabulario.ficha", lines.joined(separator: "\n") + "\n")

        let outcome = try await engine.addDeck(at: file)

        #expect(outcome == ImportOutcome(added: 3, skipped: 0, copyBeforeImport: nil))
        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["serendipia", "Un hallazgo por casualidad."],
                ["petricor", "El olor de la lluvia\(separator) sobre la tierra seca."],
                ["¿Quién dijo \"Pienso\(separator) luego existo\"?", "Descartes.\nEn el Discurso del método."],
            ])
    }

    // A text file's lines are its writer's.
    @Test("a text file's runs of empty lines stay as they are, also in its HTML", .bug(id: 542))
    func aFilesRunsOfEmptyLinesStay() async throws {
        let file = try file(
            "Arroz.ficha",
            """
            #separator:tab
            #html:true
            sustantivo<br><br><br><br>Como arroz.\tarroz

            """)

        try await engine.addDeck(at: file)

        #expect(try engine.cards().map { [$0.front, $0.back] } == [["sustantivo\n\n\n\nComo arroz.", "arroz"]])
    }

    // The headers Share Deck… writes, for Ficha to read it back.
    @Test(
        "a text file with the headers Ficha writes reads every column by its name, and its tags by #tags column",
        .bug(id: 542))
    func aFileWithFichasHeadersReadsEveryColumn() async throws {
        let file = try file(
            "Exportadas.ficha",
            """
            #separator:tab
            #html:false
            #columns:Front\tBack\tTags\tType\tSource
            #tags column:3
            ubuntu\tSoy porque somos.\tfilosofía ética_africana\tconcept\tDesmond Tutu
            "Pienso, luego existo."\t"Descartes,
            en el Discurso del método."\t\tquote\t

            """)

        try await engine.addDeck(at: file)

        #expect(
            try engine.cards().map { [$0.front, $0.back, $0.tags.joined(separator: "|"), $0.source ?? "-"] } == [
                ["ubuntu", "Soy porque somos.", "filosofía|ética africana", "Desmond Tutu"],
                ["Pienso, luego existo.", "Descartes,\nen el Discurso del método.", "", "-"],
            ])
        #expect(try engine.cards().map(\.type) == [.concept, .quote])
    }

    @Test(
        "a text file with no headers reads front, back, tags, type and source in that order, and type and source can be missing",
        .bug(id: 542))
    func aFileWithNoHeadersReadsItsColumnsInOrder() async throws {
        let file = try file(
            "mezcla.ficha",
            """
            ubuntu,Soy porque somos.,filosofía ética_africana,concept,Desmond Tutu
            "¿Cuál es la capital de Mongolia?",Ulán Bator.,geografía Asia
            petricor,El olor de la lluvia.,,Word
            serendipia,Un hallazgo por casualidad.
            """)

        try await engine.addDeck(at: file)

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

    // Anything in it but spaces and line breaks makes the card go both ways.
    @Test(
        "a line whose Both ways column holds any text comes in going both ways; one whose column is blank or missing, one way",
        .bug(id: 542))
    func aLineWhoseBothWaysColumnHoldsAnyTextComesInGoingBothWays() async throws {
        let named = try file(
            "Palabras.ficha",
            """
            #separator:tab
            #columns:Front\tBack\tBoth ways
            serendipia\tUn hallazgo por casualidad.\ty
            petricor\tEl olor de la lluvia.\tno
            efímero\tQue dura poco.\t
            ubicuo\tQue está en todas partes.\t\u{20}\u{20}
            lacónico\tQue dice mucho en pocas palabras.

            """)
        // A text file without headers reads its columns by their place, of
        // which none is Both ways.
        let unnamed = try file("Más palabras.ficha", "inefable\tQue no se puede decir.\t\tword\t\tBoth ways\n")

        try await engine.addDeck(at: named)
        try await engine.addDeck(at: unnamed)

        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["serendipia", "petricor", "efímero", "ubicuo", "lacónico", "inefable"])
        #expect(cards.map(\.bothWays) == [true, true, false, false, false, false])
    }

    @Test("unreadable lines are listed with their numbers and reasons, and the rest come in", .bug(id: 542))
    func unreadableLinesAreListedAndTheRestComeIn() async throws {
        let file = try file(
            "vocabulario.ficha",
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

        let deck = try await engine.readDeckFile(at: file)
        try engine.addDeck(deck)

        #expect(
            deck.leftOut == [
                LeftOutLine(line: 3, reason: .oneColumn),
                LeftOutLine(line: 4, reason: .blankFront),
                LeftOutLine(line: 5, reason: .blankBack),
                LeftOutLine(line: 6, reason: .unknownType("adjective")),
                LeftOutLine(line: 7, reason: .strayQuote),
                LeftOutLine(line: 10, reason: .unclosedQuote),
            ])
        #expect(deck.cardCount == 3)
        #expect(
            try engine.cards().map { [$0.front, $0.back] } == [
                ["serendipia", "Un hallazgo por casualidad."],
                ["resiliencia", "La capacidad de reponerse.\nY de adaptarse."],
                ["inefable", "Que no se puede explicar con palabras."],
            ])
    }

    // As an AI's file, whose cards may carry a tag twice, written two ways
    // (#229).
    @Test(
        "a card's tags that differ only in case and accents come in as one, named as first written, but año and ano stay two",
        .bug(id: 542))
    func tagsThatDifferOnlyInCaseAndAccentsComeInAsOne() async throws {
        let file = try file(
            "Filosofía griega.ficha", "Sócrates\tSolo sé que no sé nada.\tfilosofia_griega año ano FILOSOFÍA_GRIEGA\n")

        try await engine.addDeck(at: file)

        #expect(try engine.cards().map(\.tags) == [["filosofia griega", "año", "ano"]])
    }

    @Test("a deck's .ficha's cards that repeat the user's are skipped, and theirs stay as they were", .bug(id: 542))
    func repeatedCardsAreSkippedWhenChosen() async throws {
        let serendipia = try newCard(
            card(.word, front: "serendipia", back: "Un hallazgo.", tags: ["palabras"]), in: engine)
        let file = try file("Palabras.ficha", "serendipia\tUn hallazgo valioso.\nefímero\tQue dura poco.\n")

        let outcome = try await engine.addDeck(at: file)

        #expect(outcome == ImportOutcome(added: 1, skipped: 1, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(cards.first == serendipia)
        #expect(cards.map(\.front) == ["serendipia", "efímero"])
    }

    // A deck made before Ficha read HTML's superscripts and subscripts has
    // them flat, and the same deck's .ficha brings them in Unicode.
    @Test(
        "a front in a deck's .ficha repeats a card's front that differs only in superscripts and subscripts",
        .bug(id: 542))
    func superscriptsAndSubscriptsDontKeepImportedFrontsApart() async throws {
        let calcium = try newCard(card(.word, front: "Ca2+", back: "Un ion."), in: engine)
        let file = try file("Química.ficha", "Ca²⁺\tEl ion del calcio.\nH₂O\tEl agua.\n")

        let outcome = try await engine.addDeck(at: file)

        #expect(outcome == ImportOutcome(added: 1, skipped: 1, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(cards.map(\.id).first == calcium.id)
        #expect(cards.map(\.back) == ["Un ion.", "El agua."])
    }

    // Once with each card's first review as new cards come up, a day apart.
    @Test("a deck's .ficha's new cards come up for their first review in its text file's order", .bug(id: 542))
    func importedNewCardsComeUpInTheFilesOrder() async throws {
        let file = try file("Orden.ficha", "zeta\tLa última letra.\nalfa\tLa primera letra.\nmu\tUna del medio.\n")
        try await engine.addDeck(at: file)

        var firstReviews: [String] = []
        for _ in 0..<3 {
            for case .new(let card, _) in try engine.reviewNow(.defaults) {
                firstReviews.append(card.front)
                try engine.meet(card)
            }
            time.advance(by: days(1))
        }

        #expect(firstReviews == ["zeta", "alfa", "mu"])
    }

    @Test(
        "a deck's .ficha whose text file isn't UTF-8, or whose headers say what Ficha can't follow, is a damaged deck's file, and one that isn't there can't be opened",
        .bug(id: 542))
    func aFileFichaCantFollowIsntRead() async throws {
        let latin1 = folder.appending(path: "Latin-1.ficha")
        try writeDeckFile(at: latin1, textFile: try #require("año\tyear\n".data(using: .isoLatin1)))
        let dashes = try file("Guiones.ficha", "#separator:dash\naño-year\n")
        let numberless = try file("Etiquetas.ficha", "#tags column:third\naño\tyear\tpalabras\n")
        let unnamed = try file("Columnas.ficha", "#separator:comma\n#columns:Pregunta,Respuesta\naño,year\n")
        let missing = folder.appending(path: "Nada.ficha")

        for file in [latin1, dashes, numberless, unnamed] {
            await #expect(throws: EngineError.unreadableFile(file.lastPathComponent, .damagedDeckFile)) {
                try await engine.readDeckFile(at: file)
            }
        }
        await #expect(throws: EngineError.unreadableFile("Nada.ficha", .cannotOpen)) {
            try await engine.readDeckFile(at: missing)
        }
    }

    @Test(
        "adding a deck's .ficha saves a copy before an import, and restoring it brings back the cards as they were",
        .bug(id: 542))
    func restoringTheCopyBeforeAnImportUndoesIt() async throws {
        let engine = try Engine(
            location: .folder(folder.appending(path: "Ficha", directoryHint: .isDirectory)), time: time,
            calendar: calendar)
        try newCard(card(.word, front: "serendipia", back: "Un hallazgo."), in: engine)
        let before = try engine.cards()
        let file = try file("Palabras.ficha", "serendipia\tUn hallazgo valioso.\nefímero\tQue dura poco.\n")

        let outcome = try await engine.addDeck(at: file)
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
