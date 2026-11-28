import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window while it's open: what it lists, shows and offers
/// as Lucas chooses, searches and selects, and as it reads his cards again,
/// and what it asks and does as he acts, on the default scheduler.
struct CardsWindowStateTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    /// Opens the Cards window and reads Lucas's cards, as the window does
    /// once it listens for the reasons to read them again.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        return window
    }

    @Test(
        "the window offers New Card and Import… while there are no cards, no search, and the sidebar chose nothing, and not once it chose the inbox",
        .bug(id: 536))
    func theWindowOffersTheFirstCardsWhileThereAreNone() throws {
        var window = openWindow()
        #expect(window.sidebarItem == nil)
        #expect(window.offersFirstCards)

        window.search(for: "serendipia")
        #expect(!window.offersFirstCards)
        window.search(for: "  ")
        #expect(window.offersFirstCards)

        var inTheInbox = window
        inTheInbox.choose(.inbox)
        #expect(!inTheInbox.offersFirstCards)

        try approveCard("serendipia", in: engine)
        window.read(with: scheduler)
        #expect(window.sidebarItem == .cards(.deck(Deck.defaultName)))
        #expect(!window.offersFirstCards)
    }

    // Default lists the card, dimmed, as a deck lists every card of its own
    // (#539), and the user has cards: the buttons are for someone who has
    // none yet.
    @Test("the window offers no first cards while every card is set aside", .bug(id: 539))
    func theWindowOffersNoFirstCardsWhileEveryCardIsSetAside() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.bury(serendipia.id)

        let window = openWindow()

        #expect(window.listedCardIDs == [serendipia.id])
        #expect(!window.offersFirstCards)
    }

    // So that Lucas can undo it, and a card that moves in later is set aside
    // too.
    @Test("a set-aside deck stays listed without cards, and choosing it lists no cards rather than another deck's")
    func aSetAsideDeckStaysListedWithoutCards() throws {
        let mayo = try approveInDeck("Revolución de Mayo", deck: "Historia", in: engine)
        try approveCard("serendipia", in: engine)
        var window = openWindow()
        window.chooseSetAside(onDeck: "Historia")
        window.choose(.cards(.deck("Historia")))

        try engine.delete([mayo.id])
        window.read(with: scheduler)

        #expect(window.deckRows.map(\.id) == [Deck.defaultName, "Historia"])
        #expect(window.menu(forDeck: "Historia")?.isSetAsideTicked == true)
        #expect(window.sidebarItem == .cards(.deck("Historia")))
        #expect(window.listedCardIDs == [])
    }

    // A set-aside card won't show up, so its tile's dot never says it's due.
    @Test(
        "a set-aside deck's group holds its set-aside cards, whose tiles say they're met or new, never due",
        .bug(id: 536), .bug(id: 538))
    func aSetAsideDecksCardsStayListed() throws {
        // eudaimonía gets learned, graduated to wait 21 days or more, and
        // comes due; ataraxia is new.
        let eudaimonia = try approveInDeck("eudaimonía", deck: "Filosofía", in: engine)
        let ataraxia = try approveInDeck("ataraxia", deck: "Filosofía", in: engine)
        try engine.climbUntilLearned(eudaimonia, movingForward: time)
        time.move(to: try #require(try engine.standing(of: eudaimonia.id, with: .standard).due))
        var window = openWindow()
        window.chooseSetAside(onDeck: "Filosofía")

        window.choose(.cards(.deck("Filosofía")))

        #expect(window.listedCardIDs == [eudaimonia.id, ataraxia.id])
        #expect(window.tiles.map(\.mark) == [.met, .new])
    }

    @Test("the detail's Due row says a set-aside card is set aside, where its due time goes")
    func theDueRowSaysASetAsideCardIsSetAside() throws {
        let eudaimonia = try approveInDeck("eudaimonía", deck: "Filosofía", in: engine)
        try engine.meet(eudaimonia)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        var window = openWindow()

        window.chooseSetAside(onDeck: "Filosofía")
        let inDefault = try #require(window.listedCardRows)
        window.choose(.cards(.deck("Filosofía")))
        let setAside = try #require(window.listedCardRows)

        #expect(inDefault.map(\.id) == [serendipia.id])
        #expect(inDefault.map(\.frontFirst.dueWording) == [.due(time.now + hours(1))])
        #expect(setAside.map(\.id) == [eudaimonia.id])
        #expect(setAside.map(\.frontFirst.dueWording) == [.setAside])
    }

    @Test("selected cards the grid no longer lists are left out of the selected rows")
    func selectedCardsTheGridNoLongerListsAreLeftOut() throws {
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
        try engine.climb(ubuntu, goods: 1, movingForward: time)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.newCapture("¿Por qué bostezamos?")
        var window = openWindow()
        window.choose(.inbox)

        window.selectInInbox(.card(ubuntu.id))

        let shown = try #require(window.shownCard)
        #expect(window.selectedRows.map(\.id) == [ubuntu.id])
        #expect(shown.row.id == ubuntu.id)
        #expect(try shown.reviewLog?.get().map(\.entry.kind) == [.review(.again), .review(.good)])
        #expect(window.actions == [.edit, .setAside, .changeDeck, .delete])
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

    @Test(
        "the inbox lists a follow-up with its card, among the rest by when it was added, and a search finds it by its text"
    )
    func theInboxListsAFollowUpWithItsCard() throws {
        let poderes = try approve(
            card(
                .concept, front: "La división de poderes en la Argentina",
                back: "Ejecutivo, Legislativo y Judicial.", tags: ["política", "argentina"]),
            in: engine)
        time.advance(by: hours(1))
        let navaja = try engine.newCapture("Navaja de Ockham")
        time.advance(by: hours(1))
        try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        time.advance(by: hours(1))
        let bostezo = try engine.newCapture("¿Por qué bostezamos?")
        let followUp = try #require(try engine.inbox().followUps.first)
        var window = openWindow()

        window.choose(.inbox)
        let listed = window.listedInboxRows
        window.search(for: "JUECES")

        #expect(followUp.card == poderes)
        #expect(listed?.map(\.item) == [.capture(bostezo), .followUp(followUp), .capture(navaja)])
        #expect(listed?.map(\.text) == ["¿Por qué bostezamos?", "¿Cómo se eligen los jueces?", "Navaja de Ockham"])
        #expect(window.listedInboxRows?.map(\.item) == [.followUp(followUp)])
    }

    @Test(
        "selecting a follow-up in the inbox shows it, with its card, and offers Edit, Convert to Card and Discard")
    func aFollowUpInTheInboxShowsItsCard() throws {
        let poderes = try approve(
            card(
                .concept, front: "La división de poderes en la Argentina",
                back: "Ejecutivo, Legislativo y Judicial.", tags: ["política", "argentina"]),
            in: engine)
        let saved = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        var window = openWindow()
        window.choose(.inbox)

        window.selectInInbox(.capture(saved.id))

        let followUp = try #require(window.shownFollowUp)
        #expect(window.selectedRows.isEmpty)
        #expect(followUp.capture == saved)
        #expect(followUp.card == poderes)
        #expect(window.actions == [.edit, .convertToCard, .discard])
    }

    @Test("editing a follow-up keeps its card, and discarding it takes it out of the inbox")
    func editingAFollowUpKeepsItsCard() throws {
        let poderes = try approveCard("La división de poderes", in: engine)
        let followUp = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        var window = openWindow()
        window.choose(.inbox)
        window.selectInInbox(.capture(followUp.id))

        window.startEditing()
        let editing = window.editing
        window.saveCapture(
            text: "¿Cómo se eligen los jueces de la Corte?", note: "Y quién los puede remover", source: "")
        let edited = window.shownFollowUp
        window.askToDiscard()
        let asked = window.question
        let toDiscard = try #require(edited?.capture)
        window.discard(toDiscard)
        // As the window does once the engine says the inbox changed.
        window.read(with: scheduler)

        #expect(editing == .capture(followUp))
        #expect(edited?.capture.text == "¿Cómo se eligen los jueces de la Corte?")
        #expect(edited?.capture.note == "Y quién los puede remover")
        #expect(edited?.capture.followsUpCardID == poderes.id)
        #expect(edited?.card == poderes)
        #expect(asked == .discard(toDiscard))
        #expect(window.failure == nil)
        #expect(window.listedInboxRows == [])
        #expect(try engine.inbox().followUps.isEmpty)
        #expect(try engine.cards() == [poderes])
    }

    @Test("a follow-up whose card was deleted shows as a plain capture")
    func aFollowUpWhoseCardWasDeletedShowsAsACapture() throws {
        let poderes = try approveCard("La división de poderes", in: engine)
        let followUp = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        var window = openWindow()
        window.select([poderes.id])
        window.askToDelete()
        window.delete(try #require(window.cardsToDelete))

        window.choose(.inbox)
        window.selectInInbox(.capture(followUp.id))

        let capture = try #require(try engine.inbox().captures.first)
        #expect(capture.text == "¿Cómo se eligen los jueces?")
        #expect(capture.followsUpCardID == nil)
        #expect(window.listedInboxRows?.map(\.item) == [.capture(capture)])
        #expect(window.detail == .capture(capture))
        #expect(window.actions == [.edit, .convertToCard, .discard])
    }

    // A deck lists the cards set aside on their own too, dimmed (#539), so
    // the grid's selection can hold one: Set Aside is offered while none of
    // the selected cards is, Put Back once they all are, and neither for a
    // mix, so that one action never does half its job.
    @Test(
        "Set Aside is offered for cards none of them set aside, Put Back for cards all set aside, a deck listing both",
        .bug(id: 539))
    func setAsideOrPutBackIsOfferedForTheSelectedCards() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.bury(ojala.id)
        var window = openWindow()

        window.select([serendipia.id, ubuntu.id])
        let offeredForNoneSetAside = window.actions
        window.select([ojala.id])
        let offeredForOneSetAside = window.actions
        window.select([ubuntu.id, ojala.id])

        #expect(offeredForNoneSetAside == [.setAside, .turnOnBothWays, .changeDeck, .delete])
        #expect(offeredForOneSetAside == [.edit, .putBack, .changeDeck, .delete])
        #expect(window.actions == [.turnOnBothWays, .changeDeck, .delete])
        #expect(window.listedCardIDs == [serendipia.id, ubuntu.id, ojala.id])
    }

    // So that a whole subject goes both ways from its tag, ⌘A and one click.
    @Test("several selected cards offer Turn On Both Ways while any goes one way, and Turn Off once all go both ways")
    func theSelectionTurnsBothWaysOnOrOff() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id])
        var window = openWindow()

        window.select([ubuntu.id])
        let offeredForOne = window.actions
        window.select([serendipia.id, petricor.id])
        let offeredForOneWay = window.actions
        window.select([serendipia.id, ubuntu.id, petricor.id])
        let offeredForAMix = window.actions
        window.turnOnBothWays()
        let turnedOn = try engine.cards().map(\.bothWays)
        let offeredForBothWays = window.actions
        window.turnOffBothWays()

        #expect(offeredForOne == [.edit, .flag, .setAside, .changeDeck, .delete])
        #expect(offeredForOneWay == [.setAside, .turnOnBothWays, .changeDeck, .delete])
        #expect(offeredForAMix == [.setAside, .turnOnBothWays, .changeDeck, .delete])
        #expect(turnedOn == [true, true, true])
        #expect(offeredForBothWays == [.setAside, .turnOffBothWays, .changeDeck, .delete])
        #expect(try engine.cards().map(\.bothWays) == [false, false, false])
        #expect(window.actions == [.setAside, .turnOnBothWays, .changeDeck, .delete])
    }

    // The detail's Back-first interval and Back-first due rows show
    // `backFirst`.
    @Test(
        "turning Both ways on gives the selected cards a back-first way, new, and turning it off takes it from the window, keeping its progress"
    )
    func turningBothWaysOnAndOffGivesAndTakesTheBackFirstWay() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("petricor", in: engine)
        try engine.meet(serendipia)
        var window = openWindow()
        let before = try #require(window.listedCardRows).map(\.backFirst)

        window.select([serendipia.id, ubuntu.id])
        window.turnOnBothWays()
        let turnedOn = try #require(window.listedCardRows).map(\.backFirst?.standing)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        let metBackFirstAt = time.now
        window.read(with: scheduler)
        let metBackFirst = try #require(window.listedCardRows).map(\.backFirst?.standing)
        window.turnOffBothWays()
        let turnedOff = try #require(window.listedCardRows).map(\.backFirst)
        window.turnOnBothWays()

        #expect(before == [nil, nil, nil])
        #expect(turnedOn == [.new, .new, nil])
        #expect(metBackFirst.map { $0?.stageAndDue } == [learning(step: 0, due: metBackFirstAt + hours(1)), nil, nil])
        #expect(metBackFirst.map { $0 == .new } == [false, true, false])
        #expect(turnedOff == [nil, nil, nil])
        #expect(
            try #require(window.listedCardRows).map(\.backFirst?.due) == [metBackFirstAt + hours(1), nil, nil])
    }

    @Test(
        "the detail shows a card's front-first and back-first ways, and its review log says which way each entry went")
    func theDetailShowsEachWayAndItsReviewLogsWays() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        var window = openWindow()

        window.select([serendipia.id])
        let shownBothWays = try #require(window.shownCard)
        window.select([ubuntu.id])
        let shownOneWay = try #require(window.shownCard)

        #expect(shownBothWays.row.frontFirst.standing.stageAndDue == learning(step: 1, due: time.now + hours(4)))
        #expect(shownBothWays.row.backFirst?.dueWording == .due(time.now + minutes(10)))
        #expect(shownBothWays.row.backFirst?.interval == .seconds(hours(1)))
        #expect(try shownBothWays.reviewLog?.get().map(\.entry.way) == [.frontFirst, .backFirst, .frontFirst])
        #expect(shownOneWay.row.backFirst == nil)
        #expect(try shownOneWay.reviewLog?.get().map(\.entry.way) == [.frontFirst])
    }

    // From FSRS-6's default parameters, fsrs-rs 6.6.2's `DEFAULT_PARAMETERS`
    // (`src/inference.rs`), as Anki's Card Info shows them: a new way's first
    // review rated good starts its stability at w[2], 2.3065 days, and its
    // difficulty at w[4] − e^(w[5] × 2) + 1 = 6.4133 − e^1.6668 + 1 = 2.1181,
    // which Anki shows as (2.1181 − 1) / 9, 12.4%; and once its stability's
    // days have gone by, the chance of remembering it is 90%, as FSRS
    // defines stability.
    @Test("a reviewed way's detail has its stability, difficulty and retrievability, and a new way's has none")
    func aReviewedWaysDetailHasItsMemoryAndANewWaysHasNone() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.review(serendipia, .good)
        time.advance(by: 2.3065 * days(1))
        var window = openWindow()

        window.select([serendipia.id])
        let shown = try #require(window.shownCard).row
        let frontFirst = try #require(shown.frontFirst.memory)

        #expect(abs(frontFirst.stabilityInDays - 2.3065) < 0.0001)
        #expect(abs(frontFirst.difficulty - 0.1242) < 0.0001)
        #expect(abs(frontFirst.retrievability - 0.9) < 0.0001)
        #expect(shown.backFirst?.standing == .new)
        #expect(shown.backFirst?.memory == nil)
    }

    @Test("Flag is offered only for a single card in Lucas's reviews")
    func flagIsOfferedOnlyForASingleCardInReviews() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.flag(ojala.id, note: note("Falta un ejemplo"))
        var window = openWindow()

        window.select([serendipia.id])
        let offeredForOne = window.actions.contains(.flag)
        window.select([serendipia.id, ubuntu.id])
        let offeredForTwo = window.actions.contains(.flag)
        window.select([ojala.id])
        let offeredForAFlaggedOne = window.actions.contains(.flag)

        #expect(offeredForOne)
        #expect(!offeredForTwo)
        #expect(!offeredForAFlaggedOne)
    }

    @Test("Delete asks only about the selected cards the grid lists")
    func deleteAsksOnlyAboutTheSelectedCardsTheGridLists() throws {
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

        window.setAside()

        #expect(window.failure?.action == .setCardsAside(cardCount: 2))
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

    // The editor shows neither, and the database keeps both, unread (ADR
    // 0041): whatever the content Save gets, the card keeps its own.
    @Test("saving an edit keeps the card's tags and type, which the editor doesn't show", .bug(id: 538))
    func savingAnEditKeepsTheCardsTagsAndType() throws {
        let mayo = try approve(
            card(.concept, front: "Revolución de Mayo", back: "1810.", tags: ["historia::Argentina", "política"]),
            in: engine)
        var window = openWindow()
        window.select([mayo.id])

        window.startEditing()
        window.saveCard(try card(nil, front: "Revolución de Mayo", back: "El 25 de mayo de 1810."))

        let saved = try #require(try engine.cards().first { $0.id == mayo.id })
        #expect(saved.back == "El 25 de mayo de 1810.")
        #expect(saved.type == .concept)
        #expect(saved.tags == ["historia::Argentina", "política"])
        #expect(window.failure == nil)
    }

    @Test("editing a card starts with its Both ways, and saving turns it on or off as the editor says")
    func editingACardKeepsOrSwitchesBothWays() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id])
        var window = openWindow()

        window.select([serendipia.id])
        window.startEditing()
        let startedForSerendipia = window.editedBothWays
        window.setBothWaysInEditor(true)
        window.saveCard(try card(.word, front: serendipia.front, back: serendipia.back))
        window.select([ubuntu.id])
        window.startEditing()
        let startedForUbuntu = window.editedBothWays
        window.saveCard(try card(.word, front: ubuntu.front, back: "Soy porque somos."))

        #expect(!startedForSerendipia)
        #expect(startedForUbuntu)
        #expect(try engine.cards().map(\.bothWays) == [true, true])
        #expect(window.shownCard?.row.card.bothWays == true)
    }

    @Test("the window lists a card with when its front or back last changed, and one never edited with none")
    func theWindowListsWhenACardWasEdited() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("petricor", in: engine)
        var window = openWindow()
        time.advance(by: hours(1))
        window.select([serendipia.id])
        window.startEditing()
        window.saveCard(try card(.word, front: "serendipia", back: "Un hallazgo valioso que se da por accidente."))
        let serendipiaEditedAt = time.now
        time.advance(by: hours(1))

        window.select([ubuntu.id])
        window.startEditing()
        window.saveCard(try card(.word, front: "ubuntu", back: "Soy porque somos."))
        window.select([serendipia.id])
        window.startEditing()
        window.saveCard(
            try card(
                .word, front: "serendipia", back: "Un hallazgo valioso que se da por accidente.",
                source: "Un ensayo de Borges"))

        let rows = try #require(window.listedCardRows)
        #expect(rows.map(\.card.front) == ["serendipia", "ubuntu", "petricor"])
        #expect(rows.map(\.card.source) == ["Un ensayo de Borges", nil, nil])
        #expect(rows.map(\.card.editedAt) == [serendipiaEditedAt, time.now, nil])
    }

    // serendipia gets learned, graduated to wait 21 days or more, and comes
    // due. Set aside, it stays in its deck, Default, where Put back is.
    @Test(
        "setting a card aside in the Cards window takes it out of the reviews, still listed in its deck, and putting it back leaves it where it stood, as unburying does",
        .bug(id: 539))
    func settingACardAsideAndPuttingItBack() throws {
        let settings = ReviewSettings.defaults
        let serendipia = try engine.create(card(nil, front: "serendipia", back: "Un hallazgo por accidente."))
        try engine.climbUntilLearned(serendipia, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: scheduler)
        time.move(to: try #require(standing.due))
        var window = openWindow()
        window.select([serendipia.id])

        window.setAside()
        // As the window does once the engine says the cards changed.
        window.read(with: scheduler)
        let inTheReviews = try engine.reviewNow(settings).map(\.card.id)
        let listed = window.listedCardIDs
        window.putBack()
        window.read(with: scheduler)

        #expect(inTheReviews == [])
        #expect(listed == [serendipia.id])
        #expect(try engine.standing(of: serendipia.id, with: scheduler) == standing)
        #expect(try engine.reviewNow(settings).map(\.card.id) == [serendipia.id])
        #expect(window.failure == nil)
    }

    // ubuntu, met at 9:00 and rated good at 10:00, is due at 14:00. Flagged,
    // it waits out of the reviews, listed in its deck with its flag, until
    // an edit fixes it, as saving a flagged card's edit does.
    @Test(
        "flagging a card in the Cards window takes it out of the reviews and lists it in its deck with its note, and fixing it brings it back as it stood",
        .bug(id: 540))
    func aFlaggedCardIsListedInItsDeckUntilItsFixed() throws {
        let settings = ReviewSettings.defaults
        let ubuntu = try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."), deck: "Lenguaje")
        try engine.climb(ubuntu, goods: 1, movingForward: time)
        let standing = try engine.standing(of: ubuntu.id, with: scheduler)
        var window = openWindow()
        window.choose(.cards(.deck("Lenguaje")))
        window.select([ubuntu.id])

        window.askToFlag()
        let flaggedAt = time.now
        window.flag(note: try note("Falta un ejemplo"))
        // As the window does once the engine says the cards changed.
        window.read(with: scheduler)
        time.move(to: try #require(standing.due))
        let inTheReviews = try engine.reviewNow(settings).map(\.card.id)
        let listed = window.listedCardRows
        window.startEditing()
        window.saveCard(
            try card(nil, front: "ubuntu", back: "Soy porque somos: una persona es persona a través de las otras."))
        window.read(with: scheduler)

        #expect(inTheReviews == [])
        #expect(listed?.map(\.id) == [ubuntu.id])
        #expect(listed?.map(\.card.flag) == [Flag(note: "Falta un ejemplo", flaggedAt: flaggedAt)])
        #expect(try engine.reviewNow(settings).map(\.card.id) == [ubuntu.id])
        #expect(try engine.standing(of: ubuntu.id, with: scheduler) == standing)
        #expect(window.listedCardRows?.map(\.card.flag) == [nil])
        #expect(window.failure == nil)
    }
}

extension CardsWindowState {
    /// The ids of the cards the grid lists, in the order the engine read
    /// them, or nil when the window lists the inbox or couldn't read them.
    fileprivate var listedCardIDs: [Int64]? {
        listedCardRows?.map(\.id)
    }

    /// The cards the grid lists, in the order the engine read them, or nil
    /// when the window lists the inbox or couldn't read them.
    fileprivate var listedCardRows: [CardRow]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows
    }

    /// What the window lists in the inbox, in the order the engine read it,
    /// or nil when it lists cards or couldn't read the inbox.
    fileprivate var listedInboxRows: [InboxRow]? {
        guard case .success(.inbox(let rows)) = listing else {
            return nil
        }
        return rows
    }

    /// The follow-up the detail shows, with its card, or nil when it shows
    /// something else.
    fileprivate var shownFollowUp: FollowUp? {
        guard case .followUp(let followUp) = detail else {
            return nil
        }
        return followUp
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
