import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a deck's color and emoji in the Cards window (ADR 0024): Color
/// and Emoji… in a deck's menu, Default's too, the same in the sidebar and in
/// the Actions menu above the card list, and the sidebar's decks showing
/// them, their own or the nearest parent's, on the default ladder.
struct CardsWindowDeckLooksTests {
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    @Test(
        "a deck's Color submenu, Default's too, offers None and Finder's seven colors, ticks the deck's own, and gives it to the deck, whose decks inside take it"
    )
    func aDecksColorSubmenu() throws {
        try approveInDeck("petricor", in: engine)
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        var window = openWindow()
        let colors: [TagColor?] = [nil, .red, .orange, .yellow, .green, .blue, .purple, .gray]
        #expect(window.menu(forDeck: "Arte")?.colorItems.map(\.color) == colors)
        #expect(window.menu(forDeck: "Arte")?.colorItems.filter(\.isTicked).map(\.color) == [nil])

        window.chooseColor(.orange, onDeck: "Arte")
        window.chooseColor(.gray, onDeck: Deck.defaultName)

        #expect(window.menu(forDeck: "Arte")?.colorItems.filter(\.isTicked).map(\.color) == [.orange])
        #expect(window.menu(forDeck: Deck.defaultName)?.colorItems.filter(\.isTicked).map(\.color) == [.gray])
        // Its parent's color isn't its own, so None stays ticked.
        #expect(window.menu(forDeck: "Arte::Pintura")?.colorItems.filter(\.isTicked).map(\.color) == [nil])
        #expect(window.deckRows.everyRow.map(\.deck.shownColor) == [.gray, .orange, .orange])

        window.chooseColor(nil, onDeck: "Arte")
        #expect(window.deckRows.everyRow.map(\.deck.shownColor) == [.gray, nil, nil])
        #expect(window.failure == nil)
    }

    // The sheet says why while OK refuses, so nothing fails.
    @Test(
        "Emoji… on a deck asks in the emoji sheet, which starts with the deck's own, refuses what isn't one emoji, and takes an empty field as none"
    )
    func emojiOnADeck() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        var window = openWindow()
        window.askForEmoji(onDeck: "Arte")
        #expect(window.question == .deckEmoji(Deck(name: "Arte")))

        window.chooseEmoji("arte")
        #expect(window.question == .deckEmoji(Deck(name: "Arte")))
        #expect(window.emojiEntry("arte") == .refused(.notOneEmoji))
        window.chooseEmoji("🎨")
        #expect(window.question == nil)
        #expect(window.deckRows.everyRow.map(\.deck.shownEmoji) == ["🎨", "🎨"])

        window.askForEmoji(onDeck: "Arte")
        #expect(window.question == .deckEmoji(Deck(name: "Arte", emoji: "🎨")))
        window.chooseEmoji("")
        #expect(window.deckRows.everyRow.map(\.deck.shownEmoji) == [nil, nil])
        window.askForEmoji(onDeck: "Música")
        #expect(window.question == nil)
        #expect(window.failure == nil)
    }

    // The Actions menu above the card list is the keyboard's way to a deck's
    // menu, so it offers the same Color submenu.
    @Test("the deck the sidebar chose offers the same menu above the card list, with its color ticked")
    func theChosenDecksMenuHasItsColor() throws {
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        try engine.setColor(.purple, ofDeck: "Arte")
        var window = openWindow()

        window.choose(.cards(.deck("Arte")))

        #expect(window.chosenDeckMenu == window.menu(forDeck: "Arte"))
        #expect(window.chosenDeckMenu?.colorItems.filter(\.isTicked).map(\.color) == [.purple])
    }

    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }
}

extension [CardsWindowState.DeckRow] {
    /// Every row of the tree, in the order a tree lists them.
    fileprivate var everyRow: [CardsWindowState.DeckRow] {
        lines.map(\.node)
    }
}
