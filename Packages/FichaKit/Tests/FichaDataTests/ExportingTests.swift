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

    @Test(
        "exported cards import back as the same cards, with their types, tags and sources, a tag with a space included")
    func exportedCardsImportBackAsTheSameCards() throws {
        let contents = [
            try card(
                .word, front: "serendipia", back: "Un hallazgo valioso que se da por casualidad.",
                tags: ["vocabulario", "ética africana"], source: "Un libro de Horace Walpole"),
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
        #expect(try anotherFicha(importing: file).cards().map(content(of:)) == contents)
    }

    @Test("an export holds no progress, flag or burial, only what each card says")
    func anExportHoldsNoProgressFlagOrBurial() throws {
        let climbed = try approve(
            card(.word, front: "serendipia", back: "Un hallazgo por casualidad.", tags: ["vocabulario"]), in: engine)
        let flagged = try approve(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", source: "Desmond Tutu"), in: engine)
        let buried = try approve(card(.word, front: "petricor", back: "El olor de la lluvia."), in: engine)
        try engine.climb(climbed, to: 3, movingForward: time)
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
        let other = try anotherFicha(importing: file)
        #expect(try other.cards().map(\.standing) == [.inReviews, .inReviews, .inReviews])
        #expect(try other.reviewLog() == [])
    }

    // As the sidebar lists a tag's cards and All cards: flagged and set-aside
    // ones too, and buried ones only in Buried.
    @Test(
        "exporting a tag's cards holds exactly the cards with that tag, and all cards every card, but the buried ones")
    func exportingATagsCardsHoldsExactlyTheCardsWithThatTag() throws {
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try approveCard("Sócrates", tags: ["filosofía", "historia"])
        try approveCard("ubuntu", tags: ["filosofía"])
        let buried = try approveCard("Cabildo abierto", tags: ["historia"])
        let flagged = try approveCard("Independencia", tags: ["historia"])
        try engine.bury(buried.id)
        try engine.meet(flagged)
        try engine.flag(flagged.id, note: note("Falta el año."))
        try engine.setAside("filosofía")
        let history = folder.appending(path: "historia.txt")
        let everything = folder.appending(path: "Todas.txt")

        let historyCount = try engine.export(.tag("historia"), to: history)
        let everythingCount = try engine.export(.all, to: everything)

        #expect(historyCount == 3)
        #expect(
            try anotherFicha(importing: history).cards().map(\.front) == [
                "Revolución de Mayo", "Sócrates", "Independencia",
            ])
        #expect(everythingCount == 4)
        #expect(
            try anotherFicha(importing: everything).cards().map(\.front) == [
                "Revolución de Mayo", "Sócrates", "ubuntu", "Independencia",
            ])
    }

    /// Approves a capture into one word card with this front and `tags`, and
    /// returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que hay que saber de «\(front)».", tags: tags), in: engine)
    }
}

/// What `card` holds, as a card is made from it.
private func content(of card: Card) -> CardContent? {
    CardContent(type: card.type, front: card.front, back: card.back, tags: card.tags, source: card.source)
}
