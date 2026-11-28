import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Deck field (ADR 0024), in the Cards window's card form and in
/// its editor: the deck a new card starts in, New Deck… in the field, and an
/// edit that moves a card.
struct DeckFieldTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        engine = try Engine(location: .inMemory, time: time)
    }

    @Test("a new card's form starts in the deck the sidebar chose, and Add puts the card there")
    func aNewCardStartsInTheChosenDeck() throws {
        try engine.makeDeck(named: "Arte::Pintura")
        var window = openWindow()
        window.choose(.cards(.deck("Arte::Pintura")))

        window.openNewCardForm()
        let starting = window.cardForm?.draft.deck
        window.type(front: "La Gioconda", back: "De Leonardo.")
        window.addCard()

        #expect(starting == "Arte::Pintura")
        #expect(window.failure == nil)
        #expect(try engine.cards().map(\.deck) == ["Arte::Pintura"])
    }

    // As Anki's Add window does, so that a series of cards needs no extra
    // step. Each device remembers that deck on its own, as a preference the
    // app keeps and opens the window with. The window opens on a deck, so
    // each shows one of Ficha's decks first, as the inbox did before #540.
    @Test(
        "with no deck chosen in the sidebar, as with one of Ficha's decks shown, a new card's form starts in the deck the last card was added to, kept for the next window, or in Default once that deck is gone",
        .bug(id: 540))
    func aNewCardStartsInTheLastDeckAddedTo() async throws {
        try engine.makeDeck(named: "Arte")
        try engine.makeDeck(named: "Música::Tango")
        let palabras = try await palabrasLindas()
        var window = openWindow(showing: palabras)
        let shownAtFirst = window.shownFichaDeck?.deck
        let rememberedAtFirst = window.lastDeckAddedTo

        window.openNewCardForm()
        let atFirst = window.cardForm?.draft.deck
        window.chooseDeck("Música::Tango")
        window.type(front: "La cumparsita", back: "De Gerardo Matos Rodríguez.")
        window.addCard()
        window.closeCardForm()
        window.openNewCardForm()
        let afterAdding = window.cardForm?.draft.deck
        var nextWindow = openWindow(lastDeckAddedTo: window.lastDeckAddedTo, showing: palabras)
        nextWindow.openNewCardForm()
        var windowAfterTheDeckWent = openWindow(lastDeckAddedTo: "Cine", showing: palabras)
        windowAfterTheDeckWent.openNewCardForm()

        #expect(shownAtFirst == .palabrasLindas)
        #expect(rememberedAtFirst == Deck.defaultName)
        #expect(atFirst == Deck.defaultName)
        #expect(window.lastDeckAddedTo == "Música::Tango")
        #expect(afterAdding == "Música::Tango")
        #expect(nextWindow.cardForm?.draft.deck == "Música::Tango")
        #expect(windowAfterTheDeckWent.cardForm?.draft.deck == Deck.defaultName)
    }

    // Default is a deck the sidebar chose like any other.
    @Test(
        "with Default chosen in the sidebar, a new card's form starts in Default, whatever the last card was added to")
    func aNewCardStartsInDefaultWhenTheSidebarChoseIt() throws {
        try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."), deck: "Arte")
        var window = openWindow(lastDeckAddedTo: "Arte")
        window.choose(.cards(.deck(Deck.defaultName)))

        window.openNewCardForm()

        #expect(window.sidebarItem == .cards(.deck(Deck.defaultName)))
        #expect(window.cardForm?.draft.deck == Deck.defaultName)
    }

    @Test(
        "the form's Deck field offers Default and every deck as a tree, and New Deck… there refuses Default's name, names a deck the field then holds and offers, and Add makes it"
    )
    func newDeckInTheForm() throws {
        try engine.makeDeck(named: "Arte")
        var window = openWindow()
        window.openNewCardForm()
        let choices = window.deckFieldChoices(.form).map(\.name)

        window.askForNewDeck(in: .form)
        let asked = window.question
        let refusal = window.newDeckEntry("default")
        window.chooseNewDeck("default")
        let afterRefusal = window.question
        window.chooseNewDeck(" Idiomas :: Inglés ")
        let named = window.cardForm?.draft.deck
        let choicesOnceNamed = window.deckFieldChoices(.form).map(\.name)
        let decksBeforeAdding = try engine.decks().map(\.name)
        window.type(front: "serendipity", back: "Un hallazgo por casualidad.")
        window.addCard()

        #expect(choices == [Deck.defaultName, "Arte"])
        #expect(asked == .newDeck(.form))
        #expect(refusal == .refused(.defaultDeckName("default")))
        #expect(afterRefusal == .newDeck(.form))
        #expect(window.question == nil)
        #expect(named == "Idiomas::Inglés")
        #expect(choicesOnceNamed == [Deck.defaultName, "Arte", "Idiomas", "Idiomas::Inglés"])
        #expect(decksBeforeAdding == ["Arte"])
        #expect(try engine.cards().map(\.deck) == ["Idiomas::Inglés"])
        #expect(try engine.decks().map(\.name) == ["Arte", "Idiomas", "Idiomas::Inglés"])
    }

    // As Change Deck does: the card keeps its progress, its review log and its
    // tags.
    @Test(
        "editing a card shows its deck in the Deck field, and Save moves it to the deck chosen there, or named with New Deck…, keeping its progress"
    )
    func anEditMovesTheCard() throws {
        let gioconda = try engine.create(
            card(.concept, front: "La Gioconda", back: "De Leonardo.", tags: ["renacimiento"]), deck: "Arte")
        try engine.makeDeck(named: "Arte::Pintura")
        try engine.meet(gioconda)
        let standing = try engine.standing(of: gioconda.id, with: scheduler)
        // The editor shows no tags (#538), and Save keeps the card's.
        let edited = try card(nil, front: "La Gioconda", back: "De Leonardo da Vinci.")
        var window = openWindow()
        window.select([gioconda.id])

        window.startEditing()
        let atFirst = window.editedDeck
        let choices = window.deckFieldChoices(.editor).map(\.name)
        window.setDeckInEditor("Arte::Pintura")
        window.saveCard(edited)
        let afterSaving = try engine.cards()
        window.startEditing()
        window.askForNewDeck(in: .editor)
        window.chooseNewDeck("Museos::Louvre")
        let named = window.editedDeck
        window.saveCard(edited)

        #expect(atFirst == "Arte")
        #expect(choices == [Deck.defaultName, "Arte", "Arte::Pintura"])
        #expect(afterSaving.map(\.deck) == ["Arte::Pintura"])
        #expect(afterSaving.map(\.back) == ["De Leonardo da Vinci."])
        #expect(afterSaving.map(\.tags) == [["renacimiento"]])
        #expect(named == "Museos::Louvre")
        #expect(window.editing == nil)
        #expect(window.failure == nil)
        #expect(try engine.cards().map(\.deck) == ["Museos::Louvre"])
        #expect(try engine.standing(of: gioconda.id, with: scheduler) == standing)
    }

    /// The window as it opens, on the first deck of the queue new cards come
    /// from that the sidebar lists, with the cards read, remembering
    /// `lastDeckAddedTo` as the deck the last card was added to.
    private func openWindow(lastDeckAddedTo: String = Deck.defaultName) -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler, lastDeckAddedTo: lastDeckAddedTo)
        window.read(with: scheduler)
        return window
    }

    /// The window as `openWindow(lastDeckAddedTo:)` opens it, offered
    /// `fichaDeck`, one of Ficha's decks, and showing it in the grid's place:
    /// the sidebar then chooses no deck of the user's.
    private func openWindow(lastDeckAddedTo: String = Deck.defaultName, showing fichaDeck: FichaDeckFile)
        -> CardsWindowState
    {
        var window = openWindow(lastDeckAddedTo: lastDeckAddedTo)
        window.offerFichaDecks([fichaDeck.deck: .success(fichaDeck)])
        window.choose(.fichaDeck(fichaDeck.deck))
        return window
    }

    /// Palabras lindas, one of Ficha's decks, as the app reads it from its
    /// bundle, from its file in the repo.
    private func palabrasLindas() async throws -> FichaDeckFile {
        try await engine.readFichaDeck(.palabrasLindas, at: try fichaDeckFileInTheRepo(of: .palabrasLindas))
    }
}

extension CardsWindowState {
    /// Picks `deck` in the form's Deck field.
    fileprivate mutating func chooseDeck(_ deck: String) {
        guard var draft = cardForm?.draft else { return }
        draft.deck = deck
        changeDraft(draft)
    }

    /// Types into the form's front and back, in place of what they held, as
    /// the user would.
    fileprivate mutating func type(front: String, back: String) {
        guard var draft = cardForm?.draft else { return }
        draft.front.text = front
        draft.back.text = back
        changeDraft(draft)
    }
}
