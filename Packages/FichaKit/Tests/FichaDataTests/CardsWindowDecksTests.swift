import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's decks (ADR 0024): the sidebar's Decks section,
/// choosing a deck, and Change Deck… with its sheet and New Deck…, on the
/// default ladder. They start at 9 in the morning in Buenos Aires, when
/// active hours start.
struct CardsWindowDecksTests {
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    // Each card met the day before is due, and guernica, buried, counts in
    // no deck: Música::Tango has no card.
    @Test(
        "the Decks section, after Inbox and before Tags, lists every deck as a tree, Default first while it holds cards, each with its due cards, those inside it counted"
    )
    func theDecksSection() throws {
        let gioconda = try engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."))
        let guernica = try engine.create(card(.concept, front: "Guernica", back: "De Picasso."))
        let pieta = try engine.create(card(.concept, front: "La Piedad", back: "De Miguel Ángel."))
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        for met in [gioconda, guernica, pieta, petricor] {
            try engine.meet(met)
        }
        try engine.changeDeck(of: [gioconda.id, guernica.id], to: "Arte::Pintura")
        try engine.changeDeck(of: [pieta.id], to: "Arte")
        try engine.makeDeck(named: "Música::Tango")
        try engine.bury(guernica.id)
        time.advance(by: days(1))

        let window = openWindow()

        #expect(
            window.sidebarSections.map(\.id) == [.cardGroups, .inbox, .decks, .tags, .types])
        #expect(window.deckRows.outline == ["Default 1", "Arte 2", "  Pintura 1", "Música 0", "  Tango 0"])
        #expect(
            window.sidebarSections[2].items
                == [Deck.defaultName, "Arte", "Arte::Pintura", "Música", "Música::Tango"].map {
                    .cards(.deck($0))
                })
    }

    @Test(
        "choosing a deck lists its cards and those of the decks inside it; once Default holds none, the sidebar goes back to All cards"
    )
    func choosingADeck() throws {
        let gioconda = try engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."))
        let pieta = try engine.create(card(.concept, front: "La Piedad", back: "De Miguel Ángel."))
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try engine.changeDeck(of: [gioconda.id], to: "Arte::Pintura")
        try engine.changeDeck(of: [pieta.id], to: "Arte")
        var window = openWindow()

        window.choose(.cards(.deck("Arte")))
        let arte = window.listedCardIDs
        window.choose(.cards(.deck(Deck.defaultName)))
        let defaults = window.listedCardIDs
        try engine.changeDeck(of: [petricor.id], to: "Lenguaje")
        window.read(on: ladder)

        #expect(arte == [gioconda.id, pieta.id])
        #expect(defaults == [petricor.id])
        #expect(window.sidebarItem == .cards(.all))
        #expect(window.deckRows.map(\.id) == ["Arte", "Lenguaje"])
    }

    @Test("each parent in the sidebar starts open, and stays closed once Lucas closes it, until he opens it")
    func parentsOpenAndClose() throws {
        try engine.makeDeck(named: "Arte::Pintura")
        var window = openWindow()
        let atFirst = window.isDeckOpen("Arte")

        window.setDeckOpen(false, "Arte")
        window.read(on: ladder)
        let closed = window.isDeckOpen("Arte")
        window.setDeckOpen(true, "Arte")

        #expect(atFirst)
        #expect(!closed)
        #expect(window.isDeckOpen("Arte"))
    }

    @Test("Change Deck… is offered with one card or several selected, and not with none")
    func changeDeckIsOffered() throws {
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        let ubuntu = try engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try engine.bury(ubuntu.id)
        var window = openWindow()
        let withNone = window.actions

        window.select([petricor.id])
        let withOne = window.actions
        window.choose(.cards(.buried))
        window.select([ubuntu.id])
        let withABuriedOne = window.actions
        window.choose(.cards(.all))
        try engine.unbury(ubuntu.id)
        window.read(on: ladder)
        window.select([petricor.id, ubuntu.id])

        #expect(!withNone.contains(.changeDeck))
        #expect(withOne.contains(.changeDeck))
        #expect(withABuriedOne.contains(.changeDeck))
        #expect(window.actions.contains(.changeDeck))
    }

    @Test(
        "Change Deck… asks with the deck tree, Default in it, on the deck the cards all live in, and Move moves them, keeping their step"
    )
    func changeDeckMovesTheCards() throws {
        let gioconda = try engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."))
        let pieta = try engine.create(card(.concept, front: "La Piedad", back: "De Miguel Ángel."))
        try engine.meet(gioconda)
        try engine.meet(pieta)
        try engine.changeDeck(of: [gioconda.id, pieta.id], to: "Arte")
        try engine.makeDeck(named: "Arte::Escultura")
        time.advance(by: days(1))
        let standing = try engine.standing(of: gioconda.id, on: ladder)
        var window = openWindow()
        window.select([gioconda.id, pieta.id])

        window.askToChangeDeck()
        let asked = window.deckChangeAsked
        let choices = window.deckChoices.outline
        window.chooseInDeckChange("Arte::Escultura")
        window.changeDeck()

        #expect(asked == DeckChangeAsked(cardIDs: [gioconda.id, pieta.id], chosen: "Arte"))
        #expect(choices == ["Default 0", "Arte 2", "  Escultura 0"])
        #expect(window.question == nil)
        #expect(window.failure == nil)
        #expect(try engine.cards().map(\.deck) == ["Arte::Escultura", "Arte::Escultura"])
        #expect(try engine.standing(of: gioconda.id, on: ladder) == standing)
        #expect(window.deckRows.outline == ["Arte 2", "  Escultura 2"])
    }

    @Test("Change Deck… starts on no deck for cards that live in several, and Move does nothing until Lucas picks one")
    func changeDeckWithCardsInSeveralDecks() throws {
        let gioconda = try engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."))
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try engine.changeDeck(of: [gioconda.id], to: "Arte")
        var window = openWindow()
        window.select([gioconda.id, petricor.id])

        window.askToChangeDeck()
        window.changeDeck()
        let afterMove = window.deckChangeAsked
        window.chooseInDeckChange("Música")
        window.chooseInDeckChange(Deck.defaultName)
        window.changeDeck()

        #expect(afterMove == DeckChangeAsked(cardIDs: [gioconda.id, petricor.id], chosen: nil))
        #expect(window.question == nil)
        #expect(try engine.cards().map(\.deck) == [Deck.defaultName, Deck.defaultName])
    }

    @Test(
        "New Deck… in Change Deck refuses Default's name, lists the deck it names, with its parent, chosen, and Move makes it; Cancel makes none"
    )
    func newDeckInChangeDeck() throws {
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try engine.makeDeck(named: "Arte")
        var window = openWindow()
        window.select([petricor.id])

        window.askToChangeDeck()
        window.askForNewDeck()
        let blank = window.newDeckEntry(" :: ")
        let defaultsName = window.newDeckEntry("default")
        window.chooseNewDeck("Default")
        let afterRefusal = window.deckChangeAsked
        window.chooseNewDeck(" Idiomas :: Inglés ")
        let choices = window.deckChoices.outline
        let asked = window.deckChangeAsked
        window.cancelQuestion()
        let afterCancel = try engine.decks().map(\.name)
        window.askToChangeDeck()
        window.askForNewDeck()
        window.cancelNewDeck()
        let afterCancellingTheName = window.deckChangeAsked
        window.askForNewDeck()
        window.chooseNewDeck("Idiomas::Inglés")
        window.changeDeck()

        #expect(blank == .blankName)
        #expect(defaultsName == .refused(.defaultDeckName("default")))
        #expect(afterRefusal == DeckChangeAsked(cardIDs: [petricor.id], chosen: "", isNamingNewDeck: true))
        #expect(choices == ["Default 0", "Arte 0", "Idiomas 0", "  Inglés 0"])
        #expect(
            asked
                == DeckChangeAsked(cardIDs: [petricor.id], chosen: "Idiomas::Inglés", newDecks: ["Idiomas::Inglés"]))
        #expect(afterCancel == [Deck.defaultName, "Arte"])
        #expect(afterCancellingTheName == DeckChangeAsked(cardIDs: [petricor.id], chosen: ""))
        #expect(window.question == nil)
        #expect(try engine.cards().map(\.deck) == ["Idiomas::Inglés"])
        #expect(try engine.decks().map(\.name) == ["Arte", "Idiomas", "Idiomas::Inglés"])
    }

    /// The window as it opens, on All cards, with the cards read.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }
}

extension CardsWindowState {
    /// The ids of the cards the table lists, or nil when it lists the inbox
    /// or couldn't read them.
    fileprivate var listedCardIDs: [Int64]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.id)
    }

    /// What Change Deck… asks, while it asks.
    fileprivate var deckChangeAsked: DeckChangeAsked? {
        guard case .changeDeck(let change) = question else {
            return nil
        }
        return DeckChangeAsked(
            cardIDs: change.cards.map(\.id), chosen: change.chosenDeck, newDecks: change.newDecks,
            isNamingNewDeck: change.isNamingNewDeck)
    }
}

/// What Change Deck… asks, by the ids of the cards it moves.
private struct DeckChangeAsked: Equatable {
    let cardIDs: [Int64]
    let chosen: String?
    var newDecks: [String] = []
    var isNamingNewDeck = false
}

extension [CardsWindowState.DeckRow] {
    /// The tree, a row per deck in its order, each its title, or Default's
    /// name, and its due count, indented two spaces per level.
    fileprivate var outline: [String] {
        func lines(_ rows: [CardsWindowState.DeckRow], depth: Int) -> [String] {
            rows.flatMap { row in
                let title = row.deck.isDefault ? "Default" : row.title
                return ["\(String(repeating: "  ", count: depth))\(title) \(row.counts.due)"]
                    + lines(row.children, depth: depth + 1)
            }
        }
        return lines(self, depth: 0)
    }
}
