import FichaCore
import FichaData
import Foundation
import Testing
import ZIPFoundation

/// Tests on exporting a deck's cards to its `.ficha`, as Share Deck… does
/// (#557): what its text file holds, read back as another Ficha adds the
/// deck, from an engine in memory on a Mac in Buenos Aires, into files in a
/// folder of the test's own.
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

    /// Another Ficha, with no cards, once it adds the deck of `file`, a
    /// deck's `.ficha`, with every line read.
    private func anotherFicha(adding file: URL) async throws -> Engine {
        let other = try Engine(location: .inMemory, time: time, calendar: calendar)
        let deck = try await other.readDeckFile(at: file)
        #expect(deck.leftOut == [])
        try other.addDeck(deck)
        return other
    }

    // A tag inside another goes with `::` (ADR 0021).
    @Test(
        "a deck's exported cards come back as the same cards, with their types, tags and sources, a tag with a space and one inside another included",
        .bug(id: 542))
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
            try engine.create(content, deck: "Tarjetas")
        }
        let file = folder.appending(path: "Tarjetas.ficha")

        let count = try engine.export(.deck("Tarjetas"), to: file)

        #expect(count == 4)
        #expect(try await anotherFicha(adding: file).cards().map(content(of:)) == contents)
    }

    @Test("an export holds no progress, flag or burial, only what each card says", .bug(id: 542))
    func anExportHoldsNoProgressFlagOrBurial() async throws {
        let climbed = try newCard(
            card(.word, front: "serendipia", back: "Un hallazgo por casualidad.", tags: ["vocabulario"]), in: engine)
        let flagged = try newCard(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", source: "Desmond Tutu"), in: engine)
        let buried = try newCard(card(.word, front: "petricor", back: "El olor de la lluvia."), in: engine)
        try engine.changeDeck(of: [climbed.id, flagged.id, buried.id], to: "Tarjetas")
        try engine.climb(climbed, goods: 3, movingForward: time)
        try engine.meet(flagged)
        try engine.flag(flagged.id, note: note("Falta de qué idioma es."))
        try engine.bury(buried.id)
        let file = folder.appending(path: "Tarjetas.ficha")

        try engine.export(.deck("Tarjetas"), to: file)

        #expect(
            try textFile(in: file) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource\tDeck
                #tags column:3
                #deck column:6
                serendipia\tUn hallazgo por casualidad.\tvocabulario\tword\t\tTarjetas
                ubuntu\tSoy porque somos.\t\tconcept\tDesmond Tutu\tTarjetas
                petricor\tEl olor de la lluvia.\t\tword\t\tTarjetas

                """)
        let other = try await anotherFicha(adding: file)
        #expect(try other.cards().map(\.standing) == [.inReviews, .inReviews, .inReviews])
        #expect(try other.reviewLog() == [])
    }

    @Test(
        "an export writes a Both ways column, with y for each card that goes both ways, only when one of its cards does, and another Ficha reads it back",
        .bug(id: 542))
    func anExportWritesABothWaysColumnOnlyWhenACardGoesBothWays() async throws {
        let serendipia = try engine.create(
            card(.word, front: "serendipia", back: "Un hallazgo por casualidad.", tags: ["vocabulario"]),
            deck: "Vocabulario", bothWays: true)
        try engine.create(
            card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["vocabulario"]), deck: "Vocabulario")
        try engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]), deck: "Filosofía")
        let vocabulary = folder.appending(path: "Vocabulario.ficha")
        let philosophy = folder.appending(path: "Filosofía.ficha")

        try engine.export(.deck("Vocabulario"), to: vocabulary)
        try engine.export(.deck("Filosofía"), to: philosophy)

        #expect(
            try textFile(in: vocabulary) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource\tDeck\tBoth ways
                #tags column:3
                #deck column:6
                serendipia\tUn hallazgo por casualidad.\tvocabulario\tword\t\tVocabulario\ty
                petricor\tEl olor de la lluvia.\tvocabulario\tword\t\tVocabulario\t

                """)
        #expect(!(try textFile(in: philosophy).contains("Both ways")))
        let other = try await anotherFicha(adding: vocabulary)
        #expect(try other.cards().map(\.front) == [serendipia.front, "petricor"])
        #expect(try other.cards().map(\.bothWays) == [true, false])
    }

    @Test(
        "a deck's cards with an image that go both ways export to a .ficha whose text file says so, and another Ficha reads it back",
        .bug(id: 542))
    func cardsWithAnImageThatGoBothWaysExportAsAZip() async throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let contents = [
            try card(nil, front: "", back: "El hornero, que hace su nido de barro.", frontImage: bird),
            try card(.word, front: "tero", back: "Un pájaro que grita cuando alguien se acerca a su nido."),
        ]
        try engine.create(contents[0], deck: "Aves", bothWays: true)
        try engine.create(contents[1], deck: "Aves")
        let file = folder.appending(path: "Aves.ficha")

        try engine.export(.deck("Aves"), to: file)

        let other = try await anotherFicha(adding: file)
        #expect(try other.cards().map(content(of:)) == contents)
        #expect(try other.cards().map(\.bothWays) == [true, false])
    }

    // As the sidebar lists a parent deck's cards (ADR 0024).
    @Test("exporting a deck's cards holds those of the decks inside it, buried ones too")
    func exportingADecksCardsHoldsThoseOfTheDecksInsideIt() async throws {
        let inflation = try addCard("inflación", tags: [])
        let peso = try addCard("cepo", tags: [])
        let economist = try addCard("economista", tags: [])
        try addCard("petricor", tags: [])
        try engine.changeDeck(of: [inflation.id], to: "Economía")
        try engine.changeDeck(of: [peso.id], to: "Economía::Argentina")
        try engine.changeDeck(of: [economist.id], to: "EconomíaX")
        try engine.bury(peso.id)
        let economy = folder.appending(path: "Economía.ficha")

        let count = try engine.export(.deck("Economía"), to: economy)

        #expect(count == 2)
        #expect(
            try await anotherFicha(adding: economy).cards().map(\.deck) == ["Economía", "Economía::Argentina"])
    }

    /// Makes one word card with this front and `tags`, and returns the card.
    @discardableResult
    private func addCard(_ front: String, tags: [String]) throws -> Card {
        try newCard(card(.word, front: front, back: "Lo que hay que saber de «\(front)».", tags: tags), in: engine)
    }

    /// The text file of cards in `file`, a deck's `.ficha`, named after it.
    private func textFile(in file: URL) throws -> String {
        let archive = try Archive(url: file, accessMode: .read, pathEncoding: nil)
        let entry = try #require(archive[file.deletingPathExtension().lastPathComponent + ".txt"])
        var data = Data()
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return try #require(String(data: data, encoding: .utf8))
    }
}
