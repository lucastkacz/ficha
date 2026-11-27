import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a deck's description (ADR 0044): one or two lines on what the
/// deck holds, any deck's, Default's too, kept in its row, at most 160
/// characters, and its own alone, which the decks inside it don't take. They
/// start at 9 in the morning in Buenos Aires, with an engine in memory.
struct DeckDescriptionTests {
    let engine: Engine

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    // Arte exists through Arte::Pintura alone, with no row of its own, until
    // it gets its description.
    @Test(
        "a deck's description is stored and read back with the deck, Default's too, without the spaces around it, and the decks inside it don't take it",
        .bug(id: 556))
    func aDecksDescriptionIsReadBack() throws {
        try approveInDeck("petricor", in: engine)
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        let before = try engine.decks()
        let arte = "50 pinturas de 15 artistas argentinos, de 1839 a 1930, que están en museos de Buenos Aires."
        let leftOver = "Las tarjetas que no están en otro mazo."

        try engine.setDescription("  \(arte)\n", ofDeck: "Arte")
        try engine.setDescription(leftOver, ofDeck: Deck.defaultName)

        #expect(before.map(\.description) == [nil, nil, nil])
        #expect(
            try engine.decks() == [
                Deck(name: Deck.defaultName, description: leftOver), Deck(name: "Arte", description: arte),
                Deck(name: "Arte::Pintura"),
            ])
    }

    @Test(
        "giving a deck no description, or a blank one, takes its own away, and leaves its emoji",
        .bug(id: 556), arguments: [nil, "", " \n "])
    func givingNoneTakesItAway(none: String?) throws {
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        try engine.setEmoji(Emoji("🎨"), ofDeck: "Arte")
        try engine.setDescription("Pinturas argentinas.", ofDeck: "Arte")

        try engine.setDescription(none, ofDeck: "Arte")

        #expect(try engine.decks() == [Deck(name: "Arte", emoji: "🎨")])
    }

    // A flag is one character, as the user sees it, though it's two scalars.
    @Test(
        "a description of 160 characters is kept, and one over 160 is refused, naming the limit and changing nothing",
        .bug(id: 556))
    func aDescriptionOver160IsRefused() throws {
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        let longest = String(repeating: "a", count: 159) + "🇦🇷"
        try engine.setDescription(longest, ofDeck: "Arte")

        #expect(throws: EngineError.descriptionTooLong) { try engine.setDescription(longest + "!", ofDeck: "Arte") }
        #expect(try engine.decks() == [Deck(name: "Arte", description: longest)])
        #expect(EngineError.descriptionTooLong.localizedDescription.contains("160 characters"))
    }

    @Test("a renamed deck keeps its description, and a deck inside it its own", .bug(id: 556))
    func aRenamedDeckKeepsItsDescription() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        try engine.setDescription("Lo que está en los museos.", ofDeck: "Arte")
        try engine.setDescription("Cuadros.", ofDeck: "Arte::Pintura")

        try engine.renameDeck("Arte", to: "Cultura")

        #expect(
            try engine.decks() == [
                Deck(name: "Cultura", description: "Lo que está en los museos."),
                Deck(name: "Cultura::Pintura", description: "Cuadros."),
            ])
    }
}
