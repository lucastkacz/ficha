import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on renaming decks (ADR 0024), which moves them too, as a deck's
/// whole name carries the decks it sits inside, as Anki does: a deck renamed
/// takes the decks inside it and their cards along, each card keeping its
/// step, its review log and its tags, and a deck renamed onto one that
/// exists joins it. On the default ladder; they start at 9 in the morning in
/// Buenos Aires, when active hours start.
struct RenamingDecksTests {
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    // Arte::Escultura has no card, and Historia stays where it is.
    @Test(
        "renaming a deck moves it with the decks inside it and their cards, each card keeping its step, its review log and its tags"
    )
    func renamingADeck() throws {
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte::Pintura", tags: ["italia"], in: engine)
        try approveInDeck("La Piedad", deck: "Arte", in: engine)
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        try engine.makeDeck(named: "Arte::Escultura")
        try engine.climb(gioconda, to: 2, movingForward: time)
        let log = try engine.reviewLog()
        let standing = try engine.standing(of: gioconda.id, on: ladder)

        #expect(try engine.renameDeck("Arte", to: " Cultura :: Artes ") == "Cultura::Artes")

        #expect(
            try engine.decks().map(\.name) == [
                "Cultura", "Cultura::Artes", "Cultura::Artes::Escultura", "Cultura::Artes::Pintura", "Historia",
            ])
        #expect(
            try engine.cards().map { "\($0.front) \($0.deck)" } == [
                "La Gioconda Cultura::Artes::Pintura", "La Piedad Cultura::Artes", "Coliseo Historia",
            ])
        #expect(try engine.cards().map(\.tags) == [["italia"], [], []])
        #expect(try engine.reviewLog() == log)
        #expect(try engine.standing(of: gioconda.id, on: ladder) == standing)
    }

    // Arte and Pintura each have a color; Pintura::Óleo has none and moves
    // in, as Escultura did.
    @Test(
        "renaming a deck onto one that exists joins them, the deck there keeping what it has of its own, and so for each deck inside it"
    )
    func renamingADeckOntoOneThatExists() throws {
        try approveInDeck("La Gioconda", deck: "Pinturas::Óleo", in: engine)
        try approveInDeck("Guernica", deck: "Pinturas", in: engine)
        try approveInDeck("La Piedad", deck: "Arte::Escultura", in: engine)
        try engine.makeDeck(named: "Arte::Pintura")
        try engine.setColor(.purple, ofDeck: "Arte::Pintura")
        try engine.setColor(.orange, ofDeck: "Pinturas")
        try engine.setEmoji(Emoji("🖌️"), ofDeck: "Pinturas::Óleo")

        try engine.renameDeck("Pinturas", to: "Arte::Pintura")

        #expect(
            try engine.decks() == [
                Deck(name: "Arte"), Deck(name: "Arte::Escultura"), Deck(name: "Arte::Pintura", color: .purple),
                Deck(name: "Arte::Pintura::Óleo", emoji: "🖌️", inheritedColor: .purple),
            ])
        #expect(
            try engine.cards().map { "\($0.front) \($0.deck)" } == [
                "La Gioconda Arte::Pintura::Óleo", "Guernica Arte::Pintura", "La Piedad Arte::Escultura",
            ])
    }

    // Arte existed only through Arte::Pintura, so it goes once Pintura
    // leaves it, as a tag's parent does (ADR 0021).
    @Test(
        "a deck moves inside another, onto the deck it sits inside, and to the top, and one already there stays as it is"
    )
    func movingADeck() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura::Óleo", in: engine)
        try approveInDeck("Coliseo", deck: "Historia", in: engine)

        #expect(try engine.moveDeck("Arte::Pintura", into: "Historia") == "Historia::Pintura")
        #expect(try engine.moveDeck("Historia::Pintura", into: nil) == "Pintura")
        #expect(try engine.moveDeck("Pintura", into: nil) == "Pintura")
        #expect(try engine.renameDeck("Pintura::Óleo", to: "Pintura") == "Pintura")

        #expect(try engine.decks().map(\.name) == ["Historia", "Pintura"])
        #expect(try engine.cards().map(\.deck) == ["Pintura", "Historia"])
    }

    // Música isn't there; Arte::Pintura is.
    @Test(
        "a rename is refused for Default, a deck that isn't there, a blank name, Default's name, and the deck inside itself or a deck inside it"
    )
    func renamingRefuses() throws {
        try approveInDeck("petricor", in: engine)
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        let decks = try engine.decks()

        #expect(throws: EngineError.defaultDeckStays) { try engine.renameDeck(Deck.defaultName, to: "Varios") }
        #expect(throws: EngineError.deckNotFound("Música")) { try engine.renameDeck("Música", to: "Sonidos") }
        #expect(throws: EngineError.blankDeckName) { try engine.renameDeck("Arte", to: " :: ") }
        #expect(throws: EngineError.defaultDeckName("Default")) { try engine.renameDeck("Arte", to: "Default::Arte") }
        #expect(throws: EngineError.deckInsideItself("Arte")) {
            try engine.renameDeck("Arte", to: "Arte::Pintura::Arte")
        }
        #expect(throws: EngineError.deckInsideItself("Arte")) { try engine.moveDeck("Arte", into: "Arte") }
        #expect(throws: EngineError.defaultDeckName("Default")) {
            try engine.moveDeck("Arte::Pintura", into: Deck.defaultName)
        }
        #expect(try engine.decks() == decks)
        #expect(try engine.cards().map(\.deck) == [Deck.defaultName, "Arte::Pintura"])
    }
}
