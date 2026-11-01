import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on renaming, moving and deleting decks in the Cards window (ADR
/// 0024): Rename… and Delete… in a deck's menu, which the Actions menu above
/// the card list offers too, as the keyboard's way to them, and dropping
/// cards and decks on the sidebar's decks. On the default ladder; they start
/// at 9 in the morning in Buenos Aires, when active hours start.
struct CardsWindowDeckEditsTests {
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test(
        "a deck's menu offers Rename… and Delete…, in the sidebar and in the Actions menu, and Default's offers neither"
    )
    func aDecksMenuOffersRenameAndDelete() throws {
        try approveInDeck("petricor", in: engine)
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        var window = openWindow()

        let menus = [Deck.defaultName, "Arte", "Arte::Pintura"].map(window.menu(forDeck:))
        window.choose(.cards(.deck("Arte")))
        let onArte = window.chosenDeckMenu
        window.choose(.cards(.deck(Deck.defaultName)))
        let onDefault = window.chosenDeckMenu

        #expect(menus.map { $0?.offersRenameAndDelete } == [false, true, true])
        #expect(onArte?.offersRenameAndDelete == true)
        #expect(onDefault?.offersRenameAndDelete == false)
        #expect(window.deckRows.map(\.isDraggable) == [false, true])
        #expect(window.deckRows.last?.children.map(\.isDraggable) == [true])
    }

    // Arte is closed, and the sidebar chose Arte::Pintura.
    @Test(
        "Rename… asks for the deck's whole name, refuses a blank one, Default's or one inside itself, and OK renames it, with the sidebar following it"
    )
    func renameAsksForTheWholeName() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        var window = openWindow()
        window.choose(.cards(.deck("Arte::Pintura")))
        window.setDeckOpen(false, "Arte")

        window.askToRenameDeck("Arte")
        #expect(window.question == .renameDeck(Deck(name: "Arte")))
        #expect(window.renameEntry("Arte::Pintura::Arte") == .refused(.deckInsideItself("Arte")))
        #expect(window.renameEntry(" :: ") == .refused(.blankDeckName))
        #expect(window.renameEntry("Default") == .refused(.defaultDeckName("Default")))
        #expect(window.renameEntry(" Cultura :: Arte ") == .name("Cultura::Arte"))
        window.chooseNewName("Arte::otra")
        #expect(window.question == .renameDeck(Deck(name: "Arte")))
        window.chooseNewName("Cultura::Arte")

        #expect(window.question == nil)
        #expect(window.failure == nil)
        #expect(window.sidebarItem == .cards(.deck("Cultura::Arte::Pintura")))
        #expect(!window.isDeckOpen("Cultura::Arte"))
        #expect(window.deckRows.outline == ["Cultura 0", "  Arte 0", "    Pintura 0", "Historia 0"])
        #expect(try engine.cards().map(\.deck) == ["Cultura::Arte::Pintura", "Historia"])
    }

    // Another device renamed Arte meanwhile, as the window still lists it.
    @Test("Rename… on a deck renamed meanwhile is refused, and the window says so, going on asking")
    func renamingADeckRenamedMeanwhile() throws {
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        var window = openWindow()
        window.askToRenameDeck("Arte")
        try engine.renameDeck("Arte", to: "Artes")

        window.chooseNewName("Cultura")

        #expect(window.failure?.action == .renameDeck(deck: "Arte"))
        #expect(window.failure?.error == .deckNotFound("Arte"))
        #expect(window.question == .renameDeck(Deck(name: "Arte")))
        #expect(try engine.cards().map(\.deck) == ["Artes"])
    }

    // The sidebar chose Arte::Pintura, which goes with Arte.
    @Test(
        "Delete… asks first, counting the cards it deletes and the decks inside, and Delete deletes them, the sidebar going back to All cards"
    )
    func deleteAsksFirst() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        try approveInDeck("La Piedad", deck: "Arte", in: engine)
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        try engine.makeDeck(named: "Arte::Escultura")
        var window = openWindow()
        window.choose(.cards(.deck("Arte::Pintura")))

        window.askToDeleteDeck(Deck.defaultName)
        #expect(window.question == nil)
        window.askToDeleteDeck("Arte")
        guard case .deleteDeck(let deletion)? = window.question else {
            Issue.record("Delete… didn't ask")
            return
        }
        #expect(deletion.deck == "Arte")
        #expect(deletion.decksInside == ["Arte::Escultura", "Arte::Pintura"])
        #expect(deletion.cards == 2)
        #expect(try engine.cards().count == 3)
        window.deleteDeck(deletion)

        #expect(window.question == nil)
        #expect(window.failure == nil)
        #expect(window.sidebarItem == .cards(.all))
        #expect(window.deckRows.outline == ["Historia 0"])
        #expect(try engine.cards().map(\.front) == ["Coliseo"])
    }

    // The last card was added to Arte::Pintura, and the sidebar chose
    // Historia. The card form's Deck field holds Arte, and Coliseo's editor
    // Arte::Escultura, which New Deck… named.
    @Test(
        "after Delete…, the card form goes back to the deck a new card starts in, and the editor and the last deck added to go to Default, never naming a deck it deleted"
    )
    func deletingADeckTheFieldsHold() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        let coliseo = try approveInDeck("Coliseo", deck: "Historia", in: engine)
        var window = engine.openCardsWindow(with: scheduler, lastDeckAddedTo: "Arte::Pintura")
        window.read(with: scheduler)
        window.choose(.cards(.deck("Historia")))
        window.openNewCardForm()
        var draft = try #require(window.cardForm?.draft)
        draft.deck = "Arte"
        window.changeDraft(draft)
        window.select([coliseo.id])
        window.startEditing()
        window.setDeckInEditor("Arte::Escultura")

        window.askToDeleteDeck("Arte")
        guard case .deleteDeck(let deletion)? = window.question else {
            Issue.record("Delete… didn't ask")
            return
        }
        window.deleteDeck(deletion)

        #expect(window.failure == nil)
        #expect(window.cardForm?.draft.deck == "Historia")
        #expect(window.editedDeck == Deck.defaultName)
        #expect(window.lastDeckAddedTo == Deck.defaultName)
        #expect(window.deckFieldChoices(.form).map(\.name) == [Deck.defaultName, "Historia"])
    }

    // petricor and Coliseo are selected; Coliseo lives in Historia already,
    // and ojalá keeps Default in the sidebar.
    @Test(
        "dropping cards on a deck in the sidebar moves them there, as Change Deck does, Default too, and refuses a drop that moves none"
    )
    func droppingCardsOnADeck() throws {
        let petricor = try approveInDeck("petricor", in: engine)
        let coliseo = try approveInDeck("Coliseo", deck: "Historia", in: engine)
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        try approveInDeck("ojalá", in: engine)
        var window = openWindow()
        window.select([petricor.id, coliseo.id])

        let drops = [
            window.drop([.card(petricor.id), .card(coliseo.id)], onDeck: "Historia"),
            window.drop([.card(petricor.id), .card(coliseo.id)], onDeck: "Historia"),
            window.drop([.card(99)], onDeck: "Arte"),
        ]
        let moved = try engine.cards().map(\.deck)
        let toDefault = window.drop([.card(coliseo.id)], onDeck: Deck.defaultName)
        window.select([petricor.id])
        window.startEditing()
        let whileEditing = window.drop([.card(petricor.id)], onDeck: "Arte")
        window.cancelEditing()

        #expect(drops == [true, false, false])
        #expect(moved == ["Historia", "Historia", "Arte", Deck.defaultName])
        #expect(toDefault)
        #expect(!whileEditing)
        #expect(try engine.cards().map(\.deck) == ["Historia", Deck.defaultName, "Arte", Deck.defaultName])
        #expect(window.deckRows.outline == ["Default 0", "Arte 0", "Historia 0"])
        #expect(window.failure == nil)
    }

    // The sidebar chose Arte::Pintura, and Historia is closed.
    @Test(
        "dropping a deck on another moves it inside, with the sidebar following it and the deck it went into open, and on the Decks title to the top"
    )
    func droppingADeck() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        var window = openWindow()
        window.choose(.cards(.deck("Arte::Pintura")))
        window.setDeckOpen(false, "Historia")

        let inside = window.drop([.deck("Arte::Pintura")], onDeck: "Historia")
        #expect(inside)
        #expect(window.sidebarItem == .cards(.deck("Historia::Pintura")))
        #expect(window.isDeckOpen("Historia"))
        #expect(window.deckRows.outline == ["Historia 0", "  Pintura 0"])
        let toTheTop = window.dropOnDecksTitle([.deck("Historia::Pintura")])

        #expect(toTheTop)
        #expect(window.sidebarItem == .cards(.deck("Pintura")))
        #expect(window.deckRows.outline == ["Historia 0", "Pintura 0"])
        #expect(try engine.cards().map(\.deck) == ["Pintura", "Historia"])
        #expect(window.failure == nil)
    }

    @Test(
        "a deck dropped on itself, on a deck inside it or on Default, Default dropped, a deck dropped where it is already, and a drop of cards with a deck, of two decks, of nothing or of cards on the Decks title, are refused, saying nothing"
    )
    func refusedDeckDrops() throws {
        let petricor = try approveInDeck("petricor", in: engine)
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        try approveInDeck("fuga", deck: "Música", in: engine)
        var window = openWindow()
        let rows = window.deckRows

        let drops = [
            window.drop([.deck("Arte")], onDeck: "Arte"), window.drop([.deck("Arte")], onDeck: "Arte::Pintura"),
            window.drop([.deck("Arte")], onDeck: Deck.defaultName),
            window.drop([.deck(Deck.defaultName)], onDeck: "Historia"),
            window.drop([.deck("Arte::Pintura")], onDeck: "Arte"), window.dropOnDecksTitle([.deck("Historia")]),
            window.dropOnDecksTitle([.deck(Deck.defaultName)]),
            window.drop([.card(petricor.id), .deck("Arte")], onDeck: "Música"),
            window.drop([.deck("Arte"), .deck("Historia")], onDeck: "Música"), window.drop([], onDeck: "Música"),
            window.dropOnDecksTitle([.card(petricor.id)]),
        ]

        #expect(drops == Array(repeating: false, count: 11))
        #expect(window.deckRows == rows)
        #expect(try engine.cards().map(\.deck) == [Deck.defaultName, "Arte::Pintura", "Historia", "Música"])
        #expect(window.failure == nil)
    }

    /// The window as it opens, on All cards, with the cards read.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        return window
    }
}
