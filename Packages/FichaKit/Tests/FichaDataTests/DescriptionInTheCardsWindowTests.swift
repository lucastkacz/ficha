import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a deck's description in the Cards window (ADR 0044, #557):
/// Description…, among a deck's actions, edits it in place, through the
/// window's state. They start at 9 in the morning in Buenos Aires, with an
/// engine in memory.
struct DescriptionInTheCardsWindowTests {
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)),
            ids: CountingIDSource(), calendar: calendar)
    }

    // The user's Pinturas has a card and no description, until Description…
    // gives it one, and Description… again takes it away.
    @Test(
        "Description… edits a deck's description in a field that starts with its own, whose Done sets it without the spaces around it, which the window then lists, and clears it when the field is blank",
        .bug(id: 557))
    func descriptionSetsAndClearsIt() throws {
        let text = "Pinturas argentinas del siglo XIX, que están en museos de Buenos Aires."
        try engine.create(
            card(nil, front: "Sin pan y sin trabajo", back: "Ernesto de la Cárcova, 1894."), deck: "Pinturas")
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        window.askForDescription(onDeck: "Pinturas")
        let asked = window.describedDeck
        window.chooseDescription("  \(text)\n")
        let afterDone = window.describedDeck
        let listed = window.deckInSidebar("Pinturas")
        window.askForDescription(onDeck: "Pinturas")
        let askedAgain = window.describedDeck
        window.chooseDescription(" \n ")

        #expect(asked?.name == "Pinturas")
        #expect(asked?.description == nil)
        #expect(afterDone == nil)
        #expect(listed?.description == text)
        #expect(askedAgain?.description == text)
        #expect(window.describedDeck == nil)
        #expect(window.deckInSidebar("Pinturas")?.name == "Pinturas")
        #expect(window.deckInSidebar("Pinturas")?.description == nil)
        #expect(try engine.decks().first { $0.name == "Pinturas" }?.description == nil)
        #expect(window.failure == nil)
    }
}

extension CardsWindowState {
    /// The deck `deck`, by its whole name, as the sidebar's Your Decks section
    /// lists it, as last read: nil while it doesn't.
    fileprivate func deckInSidebar(_ deck: String) -> Deck? {
        decks.first { $0.deck.name == deck }?.deck
    }
}
