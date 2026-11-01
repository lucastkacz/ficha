import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on exporting cards to a text file: what the file holds, read back
/// as the import reads it, from an engine in memory on a Mac in Buenos Aires,
/// into files in a folder of the test's own.
final class ExportingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the files it exports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaExportingTests-\(UUID().uuidString)",
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

    /// Another Ficha, with no cards, once it imports `file`, with every line
    /// read and without the tag named after the file.
    private func anotherFicha(importing file: URL) async throws -> Engine {
        let other = try Engine(location: .inMemory, time: time, calendar: calendar)
        let preview = try await other.previewImport(of: file)
        #expect(preview.leftOut == [])
        try other.importCards(
            preview,
            choosing: ImportChoices(tagNames: Dictionary(uniqueKeysWithValues: preview.proposedTags.map { ($0, "") })))
        return other
    }

    // A tag inside another goes with `::`, as Anki writes it (ADR 0021).
    @Test(
        "exported cards import back as the same cards, with their types, tags and sources, a tag with a space and one inside another included"
    )
    func exportedCardsImportBackAsTheSameCards() async throws {
        let contents = [
            try card(
                .word, front: "serendipia", back: "Un hallazgo valioso que se da por casualidad.",
                tags: ["vocabulario", "filosofía::ética africana"], source: "Un libro de Horace Walpole"),
            try card(
                .quote, front: "\"Pienso, luego existo.\"", back: "Descartes,\nen el Discurso del método.",
                tags: ["filosofía"]),
            try card(nil, front: "#1 en ventas", back: "Un libro que se vende más que ningún otro.\tO casi."),
            try card(.question, front: "¿Cuál es la capital de Mongolia?", back: "Ulán Bator.", source: "Un mapa"),
        ]
        for content in contents {
            try engine.create(content)
        }
        let file = folder.appending(path: "Tarjetas.txt")

        let count = try engine.export(.all, to: file)

        #expect(count == 4)
        #expect(try await anotherFicha(importing: file).cards().map(content(of:)) == contents)
    }

    @Test("an export holds no progress, flag or burial, only what each card says")
    func anExportHoldsNoProgressFlagOrBurial() async throws {
        let climbed = try approve(
            card(.word, front: "serendipia", back: "Un hallazgo por casualidad.", tags: ["vocabulario"]), in: engine)
        let flagged = try approve(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", source: "Desmond Tutu"), in: engine)
        let buried = try approve(card(.word, front: "petricor", back: "El olor de la lluvia."), in: engine)
        try engine.climb(climbed, goods: 3, movingForward: time)
        try engine.meet(flagged)
        try engine.flag(flagged.id, note: note("Falta de qué idioma es."))
        try engine.bury(buried.id)
        let file = folder.appending(path: "Tarjetas.txt")

        try engine.export(.cards([climbed.id, flagged.id, buried.id]), to: file)

        #expect(
            try String(contentsOf: file, encoding: .utf8) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource
                #tags column:3
                serendipia\tUn hallazgo por casualidad.\tvocabulario\tword\t
                ubuntu\tSoy porque somos.\t\tconcept\tDesmond Tutu
                petricor\tEl olor de la lluvia.\t\tword\t

                """)
        let other = try await anotherFicha(importing: file)
        #expect(try other.cards().map(\.standing) == [.inReviews, .inReviews, .inReviews])
        #expect(try other.reviewLog() == [])
    }

    // Anki maps the column to its "Add Reverse" field.
    @Test(
        "an export writes a Both ways column, with y for each card that goes both ways, only when one of its cards does, and another Ficha reads it back"
    )
    func anExportWritesABothWaysColumnOnlyWhenACardGoesBothWays() async throws {
        let serendipia = try engine.create(
            card(.word, front: "serendipia", back: "Un hallazgo por casualidad.", tags: ["vocabulario"]),
            bothWays: true)
        try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["vocabulario"]))
        try engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]))
        let vocabulary = folder.appending(path: "vocabulario.txt")
        let philosophy = folder.appending(path: "filosofía.txt")

        try engine.export(.tag("vocabulario"), to: vocabulary)
        try engine.export(.tag("filosofía"), to: philosophy)

        #expect(
            try String(contentsOf: vocabulary, encoding: .utf8) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource\tBoth ways
                #tags column:3
                serendipia\tUn hallazgo por casualidad.\tvocabulario\tword\t\ty
                petricor\tEl olor de la lluvia.\tvocabulario\tword\t\t

                """)
        #expect(
            try String(contentsOf: philosophy, encoding: .utf8) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource
                #tags column:3
                ubuntu\tSoy porque somos.\tfilosofía\tconcept\t

                """)
        let other = try await anotherFicha(importing: vocabulary)
        #expect(try other.cards().map(\.front) == [serendipia.front, "petricor"])
        #expect(try other.cards().map(\.bothWays) == [true, false])
    }

    @Test(
        "cards with an image that go both ways export as a zip whose text file says so, and another Ficha reads it back"
    )
    func cardsWithAnImageThatGoBothWaysExportAsAZip() async throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let contents = [
            try card(nil, front: "", back: "El hornero, que hace su nido de barro.", frontImage: bird),
            try card(.word, front: "tero", back: "Un pájaro que grita cuando alguien se acerca a su nido."),
        ]
        try engine.create(contents[0], bothWays: true)
        try engine.create(contents[1])
        let file = folder.appending(path: "Aves.zip")

        try engine.export(.all, to: file)

        let other = try await anotherFicha(importing: file)
        #expect(try other.cards().map(content(of:)) == contents)
        #expect(try other.cards().map(\.bothWays) == [true, false])
    }

    // Flagged, set-aside and buried ones too: an export holds what cards say,
    // and a burial is where a card stands, which it leaves out.
    @Test("exporting a tag's cards holds every card with that tag, and all cards every card, buried ones too")
    func exportingATagsCardsHoldsEveryCardWithThatTag() async throws {
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try approveCard("Sócrates", tags: ["filosofía", "historia"])
        try approveCard("ubuntu", tags: ["filosofía"])
        let buried = try approveCard("Cabildo abierto", tags: ["historia"])
        let flagged = try approveCard("Independencia", tags: ["historia"])
        try engine.bury(buried.id)
        try engine.meet(flagged)
        try engine.flag(flagged.id, note: note("Falta el año."))
        try engine.setAside(deck: Deck.defaultName)
        let history = folder.appending(path: "historia.txt")
        let everything = folder.appending(path: "Todas.txt")

        let historyCount = try engine.export(.tag("historia"), to: history)
        let everythingCount = try engine.export(.all, to: everything)

        #expect(historyCount == 4)
        #expect(
            try await anotherFicha(importing: history).cards().map(\.front) == [
                "Revolución de Mayo", "Sócrates", "Cabildo abierto", "Independencia",
            ])
        #expect(everythingCount == 5)
        #expect(
            try await anotherFicha(importing: everything).cards().map(\.front) == [
                "Revolución de Mayo", "Sócrates", "ubuntu", "Cabildo abierto", "Independencia",
            ])
    }

    // Anki reads its decks from the same header, and takes a blank field as
    // the deck its Import window chooses.
    @Test(
        "an export writes a Deck column, with Anki's #deck column header, only when a card lives in a deck other than Default, whose cards have it blank, and another Ficha puts the cards back in their decks"
    )
    func anExportWritesADeckColumnWhenACardLivesInADeck() async throws {
        let serendipia = try approveCard("serendipia", tags: ["vocabulario"])
        try approveCard("petricor", tags: [])
        let ubuntu = try approveCard("ubuntu", tags: ["filosofía"])
        try engine.changeDeck(of: [serendipia.id], to: "Idiomas::Español")
        try engine.changeDeck(of: [ubuntu.id], to: "Filosofía")
        let all = folder.appending(path: "Todas.txt")
        let philosophy = folder.appending(path: "filosofía.txt")

        try engine.export(.all, to: all)
        try engine.export(.tag("filosofía"), to: philosophy)

        #expect(
            try String(contentsOf: all, encoding: .utf8) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource\tDeck
                #tags column:3
                #deck column:6
                serendipia\tLo que hay que saber de «serendipia».\tvocabulario\tword\t\tIdiomas::Español
                petricor\tLo que hay que saber de «petricor».\t\tword\t\t
                ubuntu\tLo que hay que saber de «ubuntu».\tfilosofía\tword\t\tFilosofía

                """)
        #expect(try await anotherFicha(importing: all).cards().map(\.deck) == ["Idiomas::Español", "", "Filosofía"])
        let other = try await anotherFicha(importing: philosophy)
        #expect(try other.cards().map(\.deck) == ["Filosofía"])
    }

    // As the sidebar lists a parent deck's cards (ADR 0024).
    @Test("exporting a deck's cards holds those of the decks inside it, buried ones too, and Default's its own")
    func exportingADecksCardsHoldsThoseOfTheDecksInsideIt() async throws {
        let inflation = try approveCard("inflación", tags: [])
        let peso = try approveCard("cepo", tags: [])
        let economist = try approveCard("economista", tags: [])
        try approveCard("petricor", tags: [])
        try engine.changeDeck(of: [inflation.id], to: "Economía")
        try engine.changeDeck(of: [peso.id], to: "Economía::Argentina")
        try engine.changeDeck(of: [economist.id], to: "EconomíaX")
        try engine.bury(peso.id)
        let economy = folder.appending(path: "Economía.txt")
        let defaultDeck = folder.appending(path: "Default.txt")

        let count = try engine.export(.deck("Economía"), to: economy)
        let defaultCount = try engine.export(.deck(Deck.defaultName), to: defaultDeck)

        #expect(count == 2)
        #expect(
            try await anotherFicha(importing: economy).cards().map(\.deck) == ["Economía", "Economía::Argentina"])
        #expect(defaultCount == 1)
        #expect(try await anotherFicha(importing: defaultDeck).cards().map(\.front) == ["petricor"])
    }

    // As the sidebar lists a parent's cards (ADR 0021).
    @Test("exporting a tag's cards holds those of the tags inside it, with their whole names")
    func exportingATagsCardsHoldsThoseOfTheTagsInsideIt() async throws {
        try approveCard("inflación", tags: ["economía"])
        try approveCard("cepo", tags: ["economía::Argentina"])
        try approveCard("economista", tags: ["economíaX"])
        let file = folder.appending(path: "economía.txt")

        let count = try engine.export(.tag("economía"), to: file)

        #expect(count == 2)
        #expect(try await anotherFicha(importing: file).cards().map(\.tags) == [["economía"], ["economía::Argentina"]])
    }

    /// Approves a capture into one word card with this front and `tags`, and
    /// returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que hay que saber de «\(front)».", tags: tags), in: engine)
    }
}
