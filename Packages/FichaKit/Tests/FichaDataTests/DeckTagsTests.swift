import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a deck's tags (ADR 0024): the tags its cards carry, those of the
/// decks inside it too, each with how many of them carry it, which the Cards
/// window shows above the card list while the deck is chosen, so that Lucas
/// narrows a big deck to one of them.
struct DeckTagsTests {
    let engine: Engine

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    // A tag inside another counts for its parent too (ADR 0021), as All
    // Tags counts it, and a tie keeps the order a tree lists them.
    @Test(
        "a deck's tags count its cards and those of the decks inside it that carry each, or a tag inside it, most first, buried cards left out"
    )
    func aDecksTagsCountItsCards() throws {
        try approveInDeck("Revolución de Mayo", deck: "Historia", tags: ["argentina::Mayo", "política"], in: engine)
        try approveInDeck("Independencia", deck: "Historia", tags: ["argentina::Independencia"], in: engine)
        try approveInDeck("Coliseo", deck: "Historia::Roma", tags: ["arquitectura", "política"], in: engine)
        try approveInDeck("Senado", deck: "Historia::Roma", tags: ["política"], in: engine)
        let buried = try approveInDeck("Cónsul", deck: "Historia::Roma", tags: ["política", "roma"], in: engine)
        try engine.bury(buried.id)
        try approveInDeck("Gioconda", deck: "Arte", tags: ["arquitectura", "renacimiento"], in: engine)

        #expect(
            try engine.tags(inDeck: "Historia").map { "\($0.tag.name) \($0.cards)" } == [
                "política 3", "argentina 2", "argentina::Independencia 1", "argentina::Mayo 1", "arquitectura 1",
            ])
        #expect(
            try engine.tags(inDeck: "Historia::Roma").map { "\($0.tag.name) \($0.cards)" } == [
                "política 2", "arquitectura 1",
            ])
    }

    @Test(
        "a deck's tags carry each tag's color and emoji, Default's are its own cards' alone, and a deck with no tags has none"
    )
    func aDecksTagsCarryTheirLooks() throws {
        try approveInDeck("petricor", tags: ["lenguaje::palabras"], in: engine)
        try approveInDeck("Coliseo", deck: "Historia", tags: ["arquitectura"], in: engine)
        try approveInDeck("Gioconda", deck: "Arte", in: engine)
        try engine.setColor(.green, of: "lenguaje")
        try engine.setEmoji(Emoji("🔤"), of: "lenguaje::palabras")

        #expect(
            try engine.tags(inDeck: Deck.defaultName) == [
                DeckTag(tag: CardTag(name: "lenguaje", color: .green), cards: 1),
                DeckTag(tag: CardTag(name: "lenguaje::palabras", emoji: "🔤", inheritedColor: .green), cards: 1),
            ])
        #expect(try engine.tags(inDeck: "Arte").isEmpty)
    }
}
