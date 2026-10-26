import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on ⌘Z in the review panel, which undoes what Lucas did with its
/// cards, one at a time, while the panel is open.
struct UndoTests {
    let calendar: Calendar
    let time: ManualTimeSource
    /// The steady clock the panel times Lucas on.
    let clock = ManualClock()
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("undoing a rating puts the card back where it stood, and the panel shows it again")
    func undoingARatingPutsTheCardBack() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        let standing = try engine.standing(of: ubuntu.id, on: settings.ladder)
        let log = try engine.reviewLog()
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        try panel.answer(.review(.good), responseTime: .seconds(3))

        try panel.undo()

        #expect(panel.current == .review(ubuntu))
        #expect(try engine.standing(of: ubuntu.id, on: settings.ladder) == standing)
        #expect(try engine.reviewLog() == log)
    }

    @Test("undoing a flag takes the card out of the inbox, back to the reviews, and the panel shows it again")
    func undoingAFlagTakesTheCardOutOfTheInbox() throws {
        let cards = try dueCards("ubuntu", "petricor")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        try panel.flag(note: note("Falta un ejemplo"))

        try panel.undo()

        #expect(panel.current == .review(cards[0]))
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.reviewNow(settings) == cards.map { PanelCard.review($0) })
    }

    @Test("undoing a bury brings the card back to the reviews, and the panel shows it again")
    func undoingABuryBringsTheCardBack() throws {
        let cards = try dueCards("ubuntu", "petricor")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        try panel.bury()

        try panel.undo()

        #expect(panel.current == .review(cards[0]))
        #expect(try engine.cards().map(\.buriedAt) == [nil, nil])
        #expect(try engine.reviewNow(settings) == cards.map { PanelCard.review($0) })
    }

    @Test("⌘Z goes back one card at a time, and no further than the first one")
    func undoGoesBackOneCardAtATime() throws {
        let cards = try dueCards("ubuntu", "petricor", "serendipia")
        let standing = try engine.standing(of: cards[0].id, on: settings.ladder)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        #expect(!panel.canUndo)
        try panel.answer(.review(.good), responseTime: .seconds(3))
        try panel.bury()
        #expect(panel.canUndo)

        try panel.undo()
        #expect(panel.current == .review(cards[1]))
        try panel.undo()
        #expect(panel.current == .review(cards[0]))
        #expect(!panel.canUndo)
        try panel.undo()

        #expect(panel.current == .review(cards[0]))
        #expect(try engine.standing(of: cards[0].id, on: settings.ladder) == standing)
        #expect(try engine.reviewNow(settings) == cards.map { PanelCard.review($0) })
    }

    @Test("⌘Z shows the last card again as Lucas left it, its back showing or not, with its time going on")
    func undoShowsTheCardAsLucasLeftIt() throws {
        let cards = try dueCards("ubuntu", "petricor", "serendipia")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings, clock: clock)
        clock.advance(by: .seconds(4))
        panel.flip()
        panel.rate(.good)
        clock.advance(by: .seconds(2))
        panel.buryCard()

        panel.undoLastCard()
        #expect(panel.content == .upperSide(cards[1]))
        panel.undoLastCard()
        #expect(panel.content == .bothSides(cards[0]))
        clock.advance(by: .seconds(1))
        panel.rate(.good)

        #expect(try engine.reviewLog().last?.responseTime == .seconds(5))
    }

    // Another review now can answer the card's other way while the panel is
    // open.
    @Test("undoing a back-first rating takes back only that way's answer, and shows the card back first, flipped")
    func undoingABackFirstRatingTakesBackOnlyThatWay() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        try engine.meet(serendipia, way: .backFirst)
        time.advance(by: hours(1))
        let backFirst = try engine.standing(of: serendipia.id, way: .backFirst, on: settings.ladder)
        var panel = try engine.openPanel(.reviewNow, with: [.review(bothWays[0], .backFirst)], settings: settings)
        panel.flip()
        panel.rate(.again)
        try engine.review(serendipia, .good)

        panel.undoLastCard()

        #expect(panel.content == .bothSides(bothWays[0], .backFirst))
        #expect(try engine.standing(of: serendipia.id, way: .backFirst, on: settings.ladder) == backFirst)
        #expect(try engine.reviewLog().map(\.way) == [.frontFirst, .backFirst, .frontFirst])
    }

    @Test("undoing a back-first first view leaves that way new, and shows the card back first, whole")
    func undoingABackFirstFirstViewLeavesThatWayNew() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        var panel = try engine.openPanel(.reviewNow, with: [.firstView(bothWays[0], .backFirst)], settings: settings)
        panel.flip()
        panel.endFirstView()

        panel.undoLastCard()

        #expect(panel.content == .firstView(bothWays[0], .backFirst))
        #expect(try engine.standing(of: serendipia.id, way: .backFirst, on: settings.ladder) == .new)
        #expect(try engine.reviewLog().map(\.way) == [.frontFirst])
    }

    // Closing the panel writes it into the appearance log, as finished or
    // snoozed, by the cards Lucas went through.
    @Test("once the panel closed, nothing is left to undo")
    func nothingIsLeftToUndoOnceThePanelClosed() throws {
        let cards = try dueCards("ubuntu", "petricor")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.close(.byLucas)

        try panel.undo()

        #expect(!panel.canUndo)
        #expect(
            try engine.standing(of: cards[0].id, on: settings.ladder) == .onLadder(step: 1, due: time.now + hours(4)))
    }

    // A refine session can fix or unbury a card while the panel is open.
    @Test("⌘Z doesn't undo a flag or a bury that changed outside the panel, and says so")
    func undoRefusesWhatChangedOutsideThePanel() throws {
        let cards = try dueCards("ubuntu", "petricor", "serendipia")
        var flagging = try engine.openPanel(
            .reviewNow, with: [.review(cards[0]), .review(cards[2])], settings: settings)
        try flagging.flag(note: note("Falta un ejemplo"))
        try engine.fix(cards[0].id, with: card(.word, front: "ubuntu", back: "Soy porque somos."))
        var burying = try engine.openPanel(
            .reviewNow, with: [.review(cards[1]), .review(cards[2])], settings: settings)
        try burying.bury()
        try engine.unbury(cards[1].id)

        #expect(throws: EngineError.cannotUndo(cards[0].id)) {
            try flagging.undo()
        }
        #expect(throws: EngineError.cannotUndo(cards[1].id)) {
            try burying.undo()
        }
        #expect(flagging.current == .review(cards[2]))
        #expect(burying.current == .review(cards[2]))
    }

    // A refine session can bury a flagged card instead of fixing it.
    @Test("⌘Z doesn't undo a flag once the card was buried outside the panel, and says so")
    func undoRefusesAFlaggedCardBuriedOutsideThePanel() throws {
        let cards = try dueCards("ubuntu", "petricor")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        try panel.flag(note: note("Falta un ejemplo"))
        let buried = try engine.bury(cards[0].id)

        #expect(throws: EngineError.cannotUndo(cards[0].id)) {
            try panel.undo()
        }
        #expect(panel.current == .review(cards[1]))
        #expect(try engine.cards()[0] == buried)
    }

    @Test(
        "⌘Z deletes the follow-ups asked on the card Lucas is on, the last first, before going back to the card before, and leaves nothing in the inbox"
    )
    func undoDeletesTheFollowUpsOnTheCurrentCardFirst() throws {
        let cards = try dueCards("ubuntu", "petricor")
        let standing = try engine.standing(of: cards[0].id, on: settings.ladder)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        panel.flip()
        panel.rate(.good)
        ask("¿Quién inventó la palabra?", in: &panel)
        ask("¿Hay una palabra para el olor de la tierra seca?", in: &panel)

        panel.undoLastCard()
        #expect(try engine.inbox().followUps.map(\.capture.text) == ["¿Quién inventó la palabra?"])
        #expect(panel.content == .upperSide(cards[1]))
        panel.undoLastCard()
        #expect(try engine.inbox().followUps.isEmpty)
        #expect(try engine.inbox().captures.isEmpty)
        #expect(try engine.progress(settings).inInbox == 0)
        #expect(panel.content == .upperSide(cards[1]))
        panel.undoLastCard()

        #expect(panel.content == .bothSides(cards[0]))
        #expect(try engine.standing(of: cards[0].id, on: settings.ladder) == standing)
        #expect(!panel.canUndo)
        #expect(panel.failure == nil)
    }

    @Test(
        "after a card was flagged or buried, ⌘Z goes back to it first, and the next ⌘Z deletes its last follow-up"
    )
    func undoGoesBackToTheCardBeforeItsFollowUps() throws {
        let cards = try dueCards("ubuntu", "petricor", "serendipia")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        ask("¿De qué idioma viene?", in: &panel)
        #expect(panel.canUndo)
        panel.startFlagging()
        panel.write(note: "Falta un ejemplo")
        panel.finishFlagging()
        ask("¿Quién inventó la palabra?", in: &panel)
        panel.buryCard()

        panel.undoLastCard()
        #expect(panel.content == .upperSide(cards[1]))
        #expect(try engine.cards().map(\.buriedAt) == [nil, nil, nil])
        #expect(try engine.inbox().followUps.map(\.card.id) == [cards[0].id, cards[1].id])
        panel.undoLastCard()
        #expect(panel.content == .upperSide(cards[1]))
        #expect(try engine.inbox().followUps.map(\.card.id) == [cards[0].id])
        panel.undoLastCard()
        #expect(panel.content == .upperSide(cards[0]))
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.inbox().followUps.map(\.card.id) == [cards[0].id])
        panel.undoLastCard()

        #expect(panel.content == .upperSide(cards[0]))
        #expect(try engine.inbox().followUps.isEmpty)
        #expect(!panel.canUndo)
        #expect(try engine.reviewNow(settings) == cards.map { PanelCard.review($0) })
    }

    // A refine session can approve or discard a follow-up while the panel is
    // open.
    @Test("⌘Z doesn't undo a follow-up approved or discarded outside the panel, and says so")
    func undoRefusesAFollowUpRefinedOutsideThePanel() throws {
        let cards = try dueCards("ubuntu", "petricor")
        var approving = try engine.openPanel(.reviewNow, with: [.review(cards[0])], settings: settings)
        ask("¿De qué idioma viene?", in: &approving)
        var discarding = try engine.openPanel(.reviewNow, with: [.review(cards[1])], settings: settings)
        ask("¿Quién inventó la palabra?", in: &discarding)
        let followUps = try engine.inbox().followUps.map(\.capture)
        let approved = try engine.approve(
            followUps[0].id, into: [card(.word, front: "zulú", back: "Una lengua de Sudáfrica.")])
        try engine.discard(followUps[1].id)

        #expect(throws: EngineError.cannotUndoFollowUp(cards[0].id)) {
            try approving.undo()
        }
        #expect(throws: EngineError.cannotUndoFollowUp(cards[1].id)) {
            try discarding.undo()
        }
        #expect(try engine.cards() == cards + approved)
        #expect(approving.content == .upperSide(cards[0]))
        #expect(discarding.content == .upperSide(cards[1]))
    }

    /// Asks `question` about the card the panel is on, as Lucas does with A,
    /// and saves it as a follow-up.
    private func ask(_ question: String, in panel: inout ReviewPanelState) {
        panel.startAsking()
        panel.write(question: question)
        panel.finishAsking()
    }

    /// Approves a word card for each front, in order, and meets them all now,
    /// so that they come due together an hour later, when this moves the
    /// time. Review now brings them in the order given.
    private func dueCards(_ fronts: String...) throws -> [Card] {
        let cards = try fronts.map { try approveCard($0, in: engine) }
        for card in cards {
            try engine.meet(card)
        }
        time.advance(by: hours(1))
        return cards
    }
}
