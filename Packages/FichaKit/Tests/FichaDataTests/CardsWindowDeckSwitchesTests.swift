import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a deck's menu in the Cards window (ADR 0011, ADR 0024): Set Aside
/// and Prioritize, for Default too, the same menu in the sidebar and in the
/// Actions menu above the card list, which is its keyboard path, and a
/// set-aside deck grayed in the sidebar, on the default scheduler. They start at
/// 9 in the morning in Buenos Aires, when active hours start.
struct CardsWindowDeckSwitchesTests {
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // Arte is set aside, so Arte::Pintura sits inside a set-aside deck, and
    // Historia is a priority deck.
    @Test(
        "a deck's menu, Default's too, ticks Set Aside and Prioritize while the deck has them, with Prioritize off on a set-aside deck and on a deck inside one"
    )
    func aDecksMenu() throws {
        try approveInDeck("petricor", deck: Deck.defaultName, in: engine)
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        try approveInDeck("Revolución de Mayo", deck: "Historia", in: engine)
        try engine.setAside(deck: "Arte")
        try engine.togglePriority(ofDeck: "Historia")

        let window = openWindow()
        let menus = [Deck.defaultName, "Arte", "Arte::Pintura", "Historia"].map(window.menu(forDeck:))

        #expect(menus.map { $0?.deck.name } == [Deck.defaultName, "Arte", "Arte::Pintura", "Historia"])
        #expect(menus.map { $0?.isSetAsideTicked } == [false, true, false, false])
        #expect(menus.map { $0?.isPriorityTicked } == [false, false, false, true])
        #expect(menus.map { $0?.canPrioritize } == [true, false, false, true])
        #expect(window.menu(forDeck: "Música") == nil)
    }

    // Each card met the day before is due.
    @Test(
        "Set Aside in a deck's menu grays it and the decks inside it in the sidebar, and takes their cards out of the due counts, until Lucas chooses it again"
    )
    func settingADeckAsideFromItsMenu() throws {
        let cards = [
            try approveInDeck("petricor", deck: Deck.defaultName, in: engine),
            try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine),
            try approveInDeck("La Piedad", deck: "Arte", in: engine),
            try approveInDeck("Revolución de Mayo", deck: "Historia", in: engine),
        ]
        for card in cards {
            try engine.meet(card)
        }
        time.advance(by: days(1))
        var window = openWindow()

        window.chooseSetAside(onDeck: "Arte")
        let setAside = window.deckRows.outline
        window.chooseSetAside(onDeck: Deck.defaultName)
        let defaultSetAside = window.deckRows.outline
        window.chooseSetAside(onDeck: "Arte")
        window.chooseSetAside(onDeck: Deck.defaultName)

        #expect(setAside == ["Default 1", "Arte 0 grayed", "  Pintura 0 grayed", "Historia 1"])
        #expect(defaultSetAside == ["Default 0 grayed", "Arte 0 grayed", "  Pintura 0 grayed", "Historia 1"])
        #expect(window.deckRows.outline == ["Default 1", "Arte 2", "  Pintura 1", "Historia 1"])
        #expect(try engine.decks().map(\.switchedOn) == [nil, nil, nil, nil])
        #expect(window.failure == nil)
    }

    // Default is listed only while it holds cards or has a switch on, and its
    // one card moved out after it was set aside.
    @Test(
        "Default stays in the sidebar, grayed, while it's set aside with no card, so its menu can untick Set Aside, and leaves it then"
    )
    func aSetAsideDefaultWithNoCardStaysInTheSidebar() throws {
        let petricor = try approveInDeck("petricor", in: engine)
        var window = openWindow()
        window.chooseSetAside(onDeck: Deck.defaultName)
        try engine.changeDeck(of: [petricor.id], to: "Arte")
        window.read(with: scheduler)

        let setAside = window.deckRows.outline
        let menu = window.menu(forDeck: Deck.defaultName)
        window.chooseSetAside(onDeck: Deck.defaultName)

        #expect(setAside == ["Default 0 grayed", "Arte 0"])
        #expect(menu?.isSetAsideTicked == true)
        #expect(window.deckRows.outline == ["Arte 0"])
        #expect(window.menu(forDeck: Deck.defaultName) == nil)
        #expect(window.failure == nil)
    }

    @Test(
        "Prioritize in a deck's menu makes it a priority deck, or no longer one, and does nothing on a set-aside deck or one inside it"
    )
    func prioritizingADeckFromItsMenu() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        try approveInDeck("Revolución de Mayo", deck: "Historia", in: engine)
        var window = openWindow()

        window.choosePriority(onDeck: "Historia")
        let prioritized = try engine.prioritizeMenu().priorityDeckNames
        let ticked = window.menu(forDeck: "Historia")?.isPriorityTicked
        window.choosePriority(onDeck: "Historia")
        window.chooseSetAside(onDeck: "Arte")
        window.choosePriority(onDeck: "Arte")
        window.choosePriority(onDeck: "Arte::Pintura")

        #expect(prioritized == ["Historia"])
        #expect(ticked == true)
        #expect(try engine.prioritizeMenu().priorityDeckNames.isEmpty)
        #expect(window.menu(forDeck: "Historia")?.isPriorityTicked == false)
        #expect(window.failure == nil)
    }

    // Another device set Arte aside after the window read it, so its menu
    // still offers Prioritize.
    @Test("Prioritize on a deck set aside meanwhile is refused, and the window says so, naming the set-aside deck")
    func prioritizingADeckSetAsideMeanwhile() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        var window = openWindow()
        try engine.setAside(deck: "Arte")

        window.choosePriority(onDeck: "Arte::Pintura")

        #expect(window.failure?.action == .prioritize(deck: "Arte::Pintura"))
        #expect(window.failure?.error == .deckSetAside("Arte"))
        #expect(try engine.prioritizeMenu().priorityDeckNames.isEmpty)
    }

    @Test(
        "the Actions menu above the card list is the chosen deck's menu, the keyboard's way to it, while the sidebar chose a deck"
    )
    func theActionsMenuIsTheChosenDecksMenu() throws {
        let petricor = try approveInDeck("petricor", deck: Deck.defaultName, in: engine)
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        var window = openWindow()

        let onAllCards = window.chosenDeckMenu
        window.choose(.cards(.deck("Arte")))
        let onArte = window.chosenDeckMenu
        window.chooseSetAside(onDeck: "Arte")
        let onArteSetAside = window.chosenDeckMenu
        window.choose(.cards(.deck(Deck.defaultName)))
        let onDefault = window.chosenDeckMenu
        window.select([petricor.id])
        window.startEditing()
        let whileEditing = window.chosenDeckMenu
        window.cancelEditing()
        window.choose(.inbox)

        #expect(onAllCards == nil)
        #expect(onArte?.deck.name == "Arte" && onArte?.isSetAsideTicked == false)
        #expect(onArteSetAside?.isSetAsideTicked == true && onArteSetAside?.canPrioritize == false)
        #expect(onDefault?.deck.name == Deck.defaultName)
        #expect(whileEditing?.deck.name == Deck.defaultName)
        #expect(window.chosenDeckMenu == nil)
    }

    /// The window as it opens, on All cards, with the cards read.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        return window
    }
}
