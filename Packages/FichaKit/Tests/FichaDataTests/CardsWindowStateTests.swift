import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window while it's open: what it lists, shows and offers
/// as Lucas chooses, searches and selects, and as it reads his cards again,
/// on the default ladder.
struct CardsWindowStateTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    /// Opens the Cards window and reads Lucas's cards, as the window does
    /// once it listens for the reasons to read them again.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }

    @Test("a tag that loses its last card sends the sidebar back to All cards")
    func aTagThatLosesItsLastCardSendsTheSidebarBackToAllCards() throws {
        let mayo = try approve(
            card(.concept, front: "Revolución de Mayo", back: "1810.", tags: ["historia"]), in: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        var window = openWindow()
        window.choose(.cards(.tag("historia")))
        #expect(window.listedCardIDs == [mayo.id])

        try engine.bury(mayo.id)
        window.read(on: ladder)

        #expect(window.sidebarItem == .cards(.all))
        #expect(window.tags.isEmpty)
        #expect(window.listedCardIDs == [serendipia.id])
    }

    @Test("selected cards the table no longer lists are left out of the selected rows")
    func selectedCardsTheTableNoLongerListsAreLeftOut() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        var window = openWindow()
        window.select([serendipia.id, ubuntu.id])
        #expect(window.selectedRows.map(\.id) == [serendipia.id, ubuntu.id])

        window.search(for: "seren")

        #expect(window.selection == [serendipia.id, ubuntu.id])
        #expect(window.selectedRows.map(\.id) == [serendipia.id])
        #expect(window.shownCard?.row.id == serendipia.id)
    }

    @Test("selecting a flagged card in the inbox shows the card, with its review log, and offers what a card offers")
    func aFlaggedCardInTheInboxShowsAsTheCard() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.climb(ubuntu, to: 1, movingForward: time)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.newCapture("¿Por qué bostezamos?")
        var window = openWindow()
        window.choose(.inbox)

        window.selectInInbox(.card(ubuntu.id))

        let shown = try #require(window.shownCard)
        #expect(window.selectedRows.map(\.id) == [ubuntu.id])
        #expect(shown.row.id == ubuntu.id)
        #expect(try shown.reviewLog?.get().map(\.entry.kind) == [.firstView, .review(.good)])
        #expect(window.actions == [.edit, .bury, .delete])
    }

    @Test("selecting an expansion in the inbox shows it, with the card it expands, and offers Edit and Discard")
    func anExpansionInTheInboxOffersEditAndDiscard() throws {
        try approveCard("serendipia", in: engine)
        try engine.expand(text: "Serendipia", note: "También es una película", source: nil)
        let expansion = try #require(try engine.inbox().expansions.first)
        var window = openWindow()
        window.choose(.inbox)

        window.selectInInbox(.capture(expansion.capture.id))

        #expect(window.selectedRows.isEmpty)
        #expect(window.detail == .expansion(expansion))
        #expect(window.actions == [.edit, .discard])
    }

    // No group of the sidebar lists buried cards with others, so a selection
    // of both, which offers neither, can't be made here.
    @Test("Bury is offered while none of the selected cards is buried, and Unbury while all of them are")
    func buryAndUnburyAreOfferedForTheCardsTheyWorkOn() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        let acaso = try approveCard("acaso", in: engine)
        try engine.bury(ojala.id)
        try engine.bury(acaso.id)
        var window = openWindow()

        window.select([serendipia.id, ubuntu.id])
        let offeredInAllCards = window.actions
        window.choose(.cards(.buried))
        window.select([ojala.id, acaso.id])
        let offeredInBuried = window.actions

        #expect(offeredInAllCards == [.bury, .delete])
        #expect(offeredInBuried == [.unbury, .delete])
    }

    @Test("Flag is offered only for a single card in Lucas's reviews")
    func flagIsOfferedOnlyForASingleCardInReviews() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        let acaso = try approveCard("acaso", in: engine)
        try engine.flag(ojala.id, note: note("Falta un ejemplo"))
        try engine.bury(acaso.id)
        var window = openWindow()

        window.select([serendipia.id])
        let offeredForOne = window.actions.contains(.flag)
        window.select([serendipia.id, ubuntu.id])
        let offeredForTwo = window.actions.contains(.flag)
        window.select([ojala.id])
        let offeredForAFlaggedOne = window.actions.contains(.flag)
        window.choose(.cards(.buried))
        window.select([acaso.id])
        let offeredForABuriedOne = window.actions.contains(.flag)

        #expect(offeredForOne)
        #expect(!offeredForTwo)
        #expect(!offeredForAFlaggedOne)
        #expect(!offeredForABuriedOne)
    }

    @Test("Delete asks only about the selected cards the table lists")
    func deleteAsksOnlyAboutTheSelectedCardsTheTableLists() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        var window = openWindow()
        window.select([serendipia.id, ubuntu.id])
        window.search(for: "seren")

        window.askToDelete()
        let asked = try #require(window.cardsToDelete)
        window.delete(asked)
        window.search(for: "")

        #expect(asked.map(\.id) == [serendipia.id])
        #expect(window.question == nil)
        #expect(window.listedCardIDs == [ubuntu.id])
    }

    @Test("an action that fails records the action and how many cards it was on")
    func anActionThatFailsRecordsTheActionAndHowManyCards() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        var window = openWindow()
        window.select([serendipia.id, ubuntu.id])
        // Deleted outside the window, before it reads the cards again.
        try engine.delete([ubuntu.id])

        window.bury()

        #expect(window.failure?.action == .bury(cardCount: 2))
        #expect(window.failure?.error == .cardNotFound(ubuntu.id))
    }

    @Test("saving an edit ends it, and the detail shows the card as saved at once")
    func savingAnEditShowsTheCardAsSavedAtOnce() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var window = openWindow()
        window.select([serendipia.id])

        window.startEditing()
        let editing = window.editing
        window.saveCard(try card(.word, front: "serendipia", back: "Un hallazgo valioso que se da por accidente."))

        #expect(editing == .card(serendipia))
        #expect(window.editing == nil)
        #expect(window.shownCard?.row.card.back == "Un hallazgo valioso que se da por accidente.")
    }
}

extension CardsWindowState {
    /// The ids of the cards the table lists, in the order the engine read
    /// them, or nil when it lists the inbox or couldn't read them.
    fileprivate var listedCardIDs: [Int64]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.id)
    }

    /// The card the detail shows whole, with its review log, or nil when it
    /// shows something else.
    fileprivate var shownCard: (row: CardRow, reviewLog: Result<[ReviewLogRow], EngineError>?)? {
        guard case .card(let row, let reviewLog) = detail else {
            return nil
        }
        return (row, reviewLog)
    }

    /// The cards the window asks whether to delete, or nil when it asks
    /// nothing about deleting.
    fileprivate var cardsToDelete: [CardRow]? {
        guard case .delete(let rows) = question else {
            return nil
        }
        return rows
    }
}
