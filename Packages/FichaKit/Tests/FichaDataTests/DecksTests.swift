import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on decks (ADR 0024): each card lives in exactly one, Default until
/// it's moved, a deck sits inside another by its whole name, `Arte::Pintura`,
/// and a parent holds the cards of every deck inside it, on the default
/// ladder. They start at 9 in the morning in Buenos Aires, when active hours
/// start.
struct DecksTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("every card starts in Default, which the decks list while it holds cards, buried ones too")
    func everyCardStartsInDefault() throws {
        #expect(try engine.decks().isEmpty)

        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try engine.bury(petricor.id)

        #expect(try engine.cards().map(\.deck) == [Deck.defaultName])
        #expect(try engine.decks() == [Deck(name: Deck.defaultName)])
        try engine.delete([petricor.id])
        #expect(try engine.decks().isEmpty)
    }

    // A deck inside another makes its parent exist, as a tag does (ADR
    // 0021), and one made twice is the same deck.
    @Test(
        "a deck made with no cards stays listed, its levels cleaned up, with the deck it sits inside; a blank name or Default's is refused"
    )
    func makingADeck() throws {
        #expect(try engine.makeDeck(named: " Arte :: Pintura ") == "Arte::Pintura")
        #expect(try engine.makeDeck(named: "Arte::::Pintura") == "Arte::Pintura")
        try engine.makeDeck(named: "Historia")

        #expect(try engine.decks().map(\.name) == ["Arte", "Arte::Pintura", "Historia"])
        #expect(throws: EngineError.blankDeckName) { try engine.makeDeck(named: " :: ") }
        #expect(throws: EngineError.defaultDeckName("default")) { try engine.makeDeck(named: "default") }
        #expect(throws: EngineError.defaultDeckName("Default")) { try engine.makeDeck(named: "Default::Arte") }
        #expect(try engine.makeDeck(named: "Arte::Default") == "Arte::Default")
    }

    @Test("Change Deck moves cards to a deck, each keeping its step, its review log and its tags, and back to Default")
    func changeDeckKeepsEverythingElse() throws {
        let ubuntu = try engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]))
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try engine.climb(ubuntu, to: 2, movingForward: time)
        let log = try engine.reviewLog()
        let standing = try engine.standing(of: ubuntu.id, on: ladder)

        try engine.changeDeck(of: [ubuntu.id, petricor.id], to: " Filosofía :: África ")

        #expect(try engine.cards().map(\.deck) == ["Filosofía::África", "Filosofía::África"])
        #expect(try engine.cards().map(\.tags) == [["filosofía"], []])
        #expect(try engine.reviewLog() == log)
        #expect(try engine.standing(of: ubuntu.id, on: ladder) == standing)
        #expect(try engine.decks().map(\.name) == ["Filosofía", "Filosofía::África"])

        try engine.changeDeck(of: [petricor.id], to: Deck.defaultName)

        #expect(try engine.cards().map(\.deck) == ["Filosofía::África", Deck.defaultName])
        #expect(try engine.decks().map(\.name) == [Deck.defaultName, "Filosofía", "Filosofía::África"])
    }

    @Test("Change Deck refuses a blank deck, Default's name and a card that isn't there, moving no card")
    func changeDeckRefuses() throws {
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))

        #expect(throws: EngineError.blankDeckName) { try engine.changeDeck(of: [petricor.id], to: "  ") }
        #expect(throws: EngineError.defaultDeckName("Default")) {
            try engine.changeDeck(of: [petricor.id], to: "Default")
        }
        #expect(throws: EngineError.cardNotFound(99)) { try engine.changeDeck(of: [petricor.id, 99], to: "Arte") }
        #expect(try engine.cards().map(\.deck) == [Deck.defaultName])
        #expect(try engine.decks().map(\.name) == [Deck.defaultName])
    }

    // Artes starts as Arte does, and sits inside no deck.
    @Test("a parent lists its cards and those of every deck inside it, but not the buried ones")
    func aParentListsTheCardsOfTheDecksInsideIt() throws {
        let gioconda = try engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."))
        let pieta = try engine.create(card(.concept, front: "La Piedad", back: "De Miguel Ángel."))
        let guernica = try engine.create(card(.concept, front: "Guernica", back: "De Picasso."))
        let fuga = try engine.create(card(.concept, front: "fuga", back: "Una forma musical."))
        try engine.changeDeck(of: [gioconda.id, guernica.id], to: "Arte::Pintura")
        try engine.changeDeck(of: [pieta.id], to: "Arte")
        try engine.changeDeck(of: [fuga.id], to: "Artes")
        try engine.bury(guernica.id)

        #expect(try engine.cardRows(in: .deck("Arte"), on: ladder).map(\.card.front) == ["La Gioconda", "La Piedad"])
        #expect(try engine.cardRows(in: .deck("Arte::Pintura"), on: ladder).map(\.card.front) == ["La Gioconda"])
        #expect(try engine.cardRows(in: .deck("Artes"), on: ladder).map(\.card.front) == ["fuga"])
    }

    // Arte::Escultura has no card; Default holds the one left there.
    @Test("the deck tree counts each deck's cards and those due, the decks inside it counted, Default first")
    func theDeckTreesCounts() throws {
        let gioconda = try engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."))
        let guernica = try engine.create(card(.concept, front: "Guernica", back: "De Picasso."))
        let pieta = try engine.create(card(.concept, front: "La Piedad", back: "De Miguel Ángel."))
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        let fuga = try engine.create(card(.concept, front: "fuga", back: "Una forma musical."))
        try engine.meet(gioconda)
        try engine.meet(pieta)
        try engine.meet(petricor)
        try engine.changeDeck(of: [gioconda.id, guernica.id], to: "Arte::Pintura")
        try engine.changeDeck(of: [pieta.id], to: "Arte")
        try engine.changeDeck(of: [fuga.id], to: "Música")
        try engine.makeDeck(named: "Arte::Escultura")
        time.advance(by: days(1))

        let counted = try engine.countedDecks(on: ladder)

        #expect(counted.map(\.deck.name) == [Deck.defaultName, "Arte", "Arte::Escultura", "Arte::Pintura", "Música"])
        #expect(
            counted.map(\.counts) == [
                DeckCounts(cards: 1, due: 1), DeckCounts(cards: 3, due: 2), DeckCounts(cards: 0, due: 0),
                DeckCounts(cards: 2, due: 1), DeckCounts(cards: 1, due: 0),
            ])
    }
}
