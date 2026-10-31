import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a deck's color and emoji (ADR 0024), which Lucas picks so that
/// subjects stand apart at a glance, as a tag's (#206), each optional, and
/// which a deck without its own takes from the nearest deck it sits inside.
struct DeckColorAndEmojiTests {
    let engine: Engine

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    @Test("a deck's color and emoji are stored and read back, and the decks inside it take them while they have none")
    func aDecksColorAndEmojiAreReadBackAndInherited() throws {
        try approveInDeck("Gioconda", deck: "Arte::Pintura::Renacimiento", in: engine)
        try approveInDeck("Coliseo", deck: "Historia", in: engine)

        try engine.setColor(.orange, ofDeck: "Arte")
        try engine.setEmoji(Emoji("🎨"), ofDeck: "Arte")
        try engine.setEmoji(Emoji("🖼️"), ofDeck: "Arte::Pintura")
        try engine.setColor(.blue, ofDeck: "Historia")

        #expect(
            try engine.decks() == [
                Deck(name: "Arte", color: .orange, emoji: "🎨"),
                Deck(name: "Arte::Pintura", emoji: "🖼️", inheritedColor: .orange, inheritedEmoji: "🎨"),
                Deck(name: "Arte::Pintura::Renacimiento", inheritedColor: .orange, inheritedEmoji: "🖼️"),
                Deck(name: "Historia", color: .blue),
            ])
        #expect(
            try engine.decks().map { [$0.shownEmoji ?? "-", $0.shownColor?.rawValue ?? "-"] } == [
                ["🎨", "orange"], ["🖼️", "orange"], ["🖼️", "orange"], ["-", "blue"],
            ])
    }

    @Test("taking a deck's color and emoji away shows its parent's again, and leaves the deck where it was")
    func takingThemAwayShowsTheParentsAgain() throws {
        try approveInDeck("Gioconda", deck: "Arte::Pintura", in: engine)
        try engine.setColor(.orange, ofDeck: "Arte")
        try engine.setColor(.purple, ofDeck: "Arte::Pintura")
        try engine.setEmoji(Emoji("🖼️"), ofDeck: "Arte::Pintura")

        try engine.setColor(nil, ofDeck: "Arte::Pintura")
        try engine.setEmoji(nil, ofDeck: "Arte::Pintura")

        #expect(
            try engine.decks() == [
                Deck(name: "Arte", color: .orange), Deck(name: "Arte::Pintura", inheritedColor: .orange),
            ])
    }

    @Test("Default takes a color and an emoji too, which it keeps while its cards come and go")
    func defaultTakesAColorAndAnEmoji() throws {
        let petricor = try approveInDeck("petricor", in: engine)

        try engine.setColor(.gray, ofDeck: Deck.defaultName)
        try engine.setEmoji(Emoji("📥"), ofDeck: Deck.defaultName)
        try engine.changeDeck(of: [petricor.id], to: "Palabras")
        try engine.changeDeck(of: [petricor.id], to: Deck.defaultName)

        #expect(
            try engine.decks() == [
                Deck(name: Deck.defaultName, color: .gray, emoji: "📥"), Deck(name: "Palabras"),
            ])
    }

    @Test("an emoji that isn't one emoji, and a deck's name the engine refuses, are refused, changing nothing")
    func whatIsRefused() throws {
        try approveInDeck("Gioconda", deck: "Arte", in: engine)
        try engine.setEmoji(Emoji("🎨"), ofDeck: "Arte")

        #expect(throws: EngineError.notOneEmoji) { try engine.setEmoji(Emoji("arte"), ofDeck: "Arte") }
        #expect(throws: EngineError.blankDeckName) { try engine.setColor(.red, ofDeck: " :: ") }
        #expect(throws: EngineError.defaultDeckName("Default")) { try engine.setColor(.red, ofDeck: "Default") }
        #expect(try engine.decks() == [Deck(name: "Arte", emoji: "🎨")])
    }

    // The menu bar's Prioritize submenu puts each deck's emoji before its
    // name, as it put each tag's before decks (#383 took that test from
    // `TagColorAndEmojiTests`).
    @Test(
        "the Prioritize submenu's read carries each deck's emoji and color, its own or its parent's, a priority deck's too"
    )
    func thePrioritizeSubmenusReadCarriesEachDecksEmoji() throws {
        try approveInDeck("Revolución de Mayo", deck: "Historia::Argentina", in: engine)
        try approveInDeck("petricor", in: engine)
        try engine.setEmoji(Emoji("📜"), ofDeck: "Historia")
        try engine.setColor(.blue, ofDeck: "Historia")
        try engine.setEmoji(Emoji("🇦🇷"), ofDeck: "Historia::Argentina")
        try engine.togglePriority(ofDeck: "Historia::Argentina")

        let menu = try engine.prioritizeMenu()
        let historia = try #require(menu.decks.last)
        let argentina = try #require(historia.children.first)
        #expect(menu.decks.map(\.deck.name) == [Deck.defaultName, "Historia"])
        #expect(menu.decks.map(\.deck.shownEmoji) == [nil, "📜"])
        #expect([historia, argentina].map(\.deck.shownColor) == [.blue, .blue])
        #expect(argentina.deck.shownEmoji == "🇦🇷")
        #expect(argentina.isTicked)
    }
}
