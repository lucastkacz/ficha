import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on "See more" and reviews ahead, with the default settings: 5 cards
/// per appearance, and the default ladder, whose third step waits 2 days.
struct SeeMoreTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("review now with nothing due offers to review ahead, and \"Don't know\" there sends the card back")
    func againAheadSendsTheCardBack() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        time.advance(by: days(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        #expect(panel.cards.isEmpty)
        #expect(panel.moreCards == [.reviewAhead(serendipia)])

        panel.seeMore()
        try panel.answer(.review(.again), responseTime: .seconds(4))

        #expect(
            try engine.standing(of: serendipia.id, on: settings.ladder) == .onLadder(step: 0, due: time.now + hours(1)))
        #expect(try engine.reviewLog().last?.isAhead == true)
    }

    @Test(
        "in a review ahead, \"Sort of\" and \"Know it\" leave the card's step and due time as they were",
        arguments: [Rating.hard, .good])
    func hardAndGoodAheadLeaveTheCard(rating: Rating) throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, on: settings.ladder)
        time.advance(by: days(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        panel.seeMore()
        try panel.answer(.review(rating), responseTime: .seconds(4))

        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == standing)
        #expect(try engine.reviewLog().last?.isAhead == true)
        #expect(try engine.reviewLog().last?.kind == .review(rating))
    }

    @Test("a card's back-first way comes to review ahead as its front-first way does, and \"Don't know\" moves only it")
    func backFirstWaysComeToReviewAhead() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])
        try engine.climb(serendipia, to: 2, movingForward: time)
        try engine.meet(serendipia, way: .backFirst)
        time.advance(by: hours(1))
        try engine.review(serendipia, .good, way: .backFirst)
        let frontFirst = try engine.standing(of: serendipia.id, on: settings.ladder)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        #expect(panel.cards.isEmpty)
        #expect(panel.moreCards == [.reviewAhead(bothWays[0], .backFirst), .reviewAhead(bothWays[0])])

        panel.seeMore()
        try panel.answer(.review(.again), responseTime: .seconds(4))

        #expect(
            try engine.standing(of: serendipia.id, way: .backFirst, on: settings.ladder)
                == .onLadder(step: 0, due: time.now + hours(1)))
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == frontFirst)
        #expect(try engine.reviewLog().last?.isAhead == true)
    }

    @Test("\"See more\" brings the due cards that didn't fit first, then the closest to being due, and no new card")
    func seeMoreBringsTheLeftoversFirst() throws {
        let due = try ["uno", "dos", "tres", "cuatro", "cinco", "seis", "siete"].map { try approveCard($0, in: engine) }
        // Approved in the opposite order to when they come due.
        let muchLater = try approveCard("mucho más tarde", in: engine)
        let later = try approveCard("más tarde", in: engine)
        try approveCard("nueva", in: engine)
        for card in due {
            try engine.meet(card)
        }
        time.advance(by: hours(1))
        for card in due.prefix(5) {
            try engine.review(card, .good)
        }
        time.advance(by: minutes(210))
        try engine.meet(later)
        time.advance(by: minutes(30))
        try engine.meet(muchLater)
        // Now seven cards are due: the first five on the second step, and the
        // last two on the first step, for four hours. Five fit, the cards on
        // the lowest step first, so two are left over. "más tarde" is due in
        // half an hour and "mucho más tarde" in an hour, and "nueva" is new.
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        #expect(panel.cards == [due[5], due[6], due[0], due[1], due[2]].map { PanelCard.review($0) })
        for _ in panel.cards {
            try panel.answer(.review(.hard), responseTime: .seconds(3))
        }

        #expect(
            panel.moreCards == [.review(due[3]), .review(due[4]), .reviewAhead(later), .reviewAhead(muchLater)])
        panel.seeMore()
        #expect(panel.current == .review(due[3]))
    }

    @Test("in an appearance, \"See more\" counts a card due within the look-ahead as due, not ahead")
    func anAppearanceLooksAhead() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: minutes(50))
        try engine.meet(petricor)
        time.advance(by: minutes(10))
        // "petricor" is due in 50 minutes, beyond the 20-minute look-ahead.
        var panel = try engine.openPanel(.appearance, with: [.review(ubuntu)], settings: settings)
        try panel.answer(.review(.good), responseTime: .seconds(3))
        #expect(panel.moreCards == [.reviewAhead(petricor)])
        panel.close(.byLucas)
        time.advance(by: minutes(35))

        var later = try engine.openPanel(.appearance, with: [], settings: settings)

        #expect(later.moreCards == [.review(petricor), .reviewAhead(ubuntu)])
        later.seeMore()
        try later.answer(.review(.good), responseTime: .seconds(3))
        #expect(try engine.reviewLog().last?.isAhead == false)
    }

    @Test("with no other card on the ladder, there's nothing more to see")
    func nothingMoreWithoutOtherCards() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("ubuntu", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        #expect(panel.cards == [.firstView(serendipia)])

        try panel.answer(.firstView, responseTime: .seconds(8))

        #expect(panel.current == nil)
        #expect(panel.moreCards.isEmpty)
    }

    @Test("\"See more\" leaves out a flagged card and a buried card that are due")
    func seeMoreLeavesOutFlaggedAndBuriedCards() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        for card in [ubuntu, petricor, serendipia] {
            try engine.meet(card)
        }
        try engine.flag(petricor.id, note: note("Falta decir de dónde viene"))
        try engine.bury(serendipia.id)
        time.advance(by: hours(1))

        let panel = try engine.openPanel(.reviewNow, with: [], settings: settings)

        #expect(panel.moreCards == [.review(ubuntu)])
    }

    // Lucas, in #14: once "See more?" keeps the panel open, a slip on the
    // last card can be undone.
    @Test("⌘Z at the end undoes what Lucas did with the last card, a first view too, and goes back to it")
    func undoAtTheEndGoesBackToTheLastCard() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: minutes(30))
        try engine.meet(petricor)
        time.advance(by: minutes(30))
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        #expect(panel.cards == [.review(ubuntu), .firstView(serendipia)])
        try panel.answer(.review(.good), responseTime: .seconds(3))
        try panel.answer(.firstView, responseTime: .seconds(8))
        #expect(panel.moreCards == [.reviewAhead(petricor)])
        #expect(panel.canUndo)

        try panel.undo()

        #expect(panel.current == .firstView(serendipia))
        #expect(panel.moreCards.isEmpty)
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == .new)
        try panel.undo()
        #expect(panel.current == .review(ubuntu))
        #expect(try engine.standing(of: ubuntu.id, on: settings.ladder).isDue(at: time.now))
    }

    // Lucas asked for it, and it's due by the time he answers.
    @Test("a card brought as a review ahead that comes due before Lucas answers is reviewed on time")
    func aCardThatCameDueIsOnTime() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        time.advance(by: minutes(30))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        panel.seeMore()
        #expect(panel.current == .reviewAhead(serendipia))
        time.advance(by: minutes(30))

        try panel.answer(.review(.good), responseTime: .seconds(1_800))

        #expect(try engine.reviewLog().last?.isAhead == false)
        #expect(
            try engine.standing(of: serendipia.id, on: settings.ladder) == .onLadder(step: 1, due: time.now + hours(4)))
    }

    // A snooze leaves cards due, and the cards "See more" adds aren't due,
    // or were left over.
    @Test("closing the panel partway through the cards \"See more\" added still finishes it")
    func stoppingPartwayThroughMoreFinishes() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: minutes(30))
        try engine.meet(petricor)
        try engine.meet(serendipia)
        time.advance(by: minutes(30))
        var panel = try engine.openPanel(.appearance, with: [.review(ubuntu)], settings: settings)
        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.seeMore()
        try panel.answer(.review(.again), responseTime: .seconds(3))
        #expect(panel.current == .reviewAhead(serendipia))

        panel.close(.byLucas)

        #expect(panel.outcome == .finished)
        #expect(try engine.appearanceLog().map(\.outcome) == [.finished])
    }
}
