import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on how first views and ratings move cards on the ladder (ADR 0002),
/// with the default ladder: 1 hour, 4 hours, 2 days, 5 days, 12 days, 30 days
/// and 75 days. Steps count from 0, the first step.
struct LadderTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("a card is new until its first view, which puts it on the first step, an hour")
    func firstViewPutsTheCardOnTheFirstStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        #expect(try engine.standing(of: serendipia.id, on: ladder) == .new)
        time.advance(by: 60)

        try engine.record(
            .firstView, of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, settings: .defaults)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 0, due: time.now + hours(1)))
    }

    @Test("good moves a card up one step")
    func goodMovesTheCardUpOneStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.record(
            .firstView, of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, settings: .defaults)
        time.advance(by: hours(1))

        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 1, due: time.now + hours(4)))
    }

    @Test("hard keeps a card on its step, to wait that step's wait again")
    func hardKeepsTheCardOnItsStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 1, movingForward: time)

        try engine.reviewWhenDue(serendipia, .hard, movingForward: time)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 1, due: time.now + hours(4)))
    }

    @Test("again sends a card back to the first step")
    func againSendsTheCardBackToTheFirstStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 3, movingForward: time)

        try engine.reviewWhenDue(serendipia, .again, movingForward: time)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 0, due: time.now + hours(1)))
    }

    @Test("good on the last step keeps a card there, to come back every 75 days")
    func theLastStepRepeats() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 6, movingForward: time)
        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 6, due: time.now + days(75)))

        try engine.reviewWhenDue(serendipia, .good, movingForward: time)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 6, due: time.now + days(75)))
    }

    @Test("every first view and review goes into the review log, with its time, trigger, response time and rating")
    func firstViewsAndReviewsGoIntoTheReviewLog() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let firstViewTime = time.now
        try engine.record(
            .firstView, of: serendipia.id, responseTime: .milliseconds(8_250), trigger: .reviewNow, settings: .defaults)
        time.advance(by: hours(1))

        try engine.record(
            .review(.hard), of: serendipia.id, responseTime: .milliseconds(2_500), trigger: .reviewNow,
            settings: .defaults)

        #expect(
            try engine.reviewLog() == [
                ReviewLogEntry(
                    cardID: serendipia.id, kind: .firstView, answeredAt: firstViewTime,
                    responseTime: .milliseconds(8_250),
                    trigger: .reviewNow),
                ReviewLogEntry(
                    cardID: serendipia.id, kind: .review(.hard), answeredAt: firstViewTime + hours(1),
                    responseTime: .milliseconds(2_500), trigger: .reviewNow),
            ]
        )
    }

    @Test("the progress counts say how many cards are due, how many are learned and how many captures wait")
    func progressCountsDueAndLearnedCardsAndTheInbox() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try approveCard("Schadenfreude", in: engine)
        try engine.newCapture("algo para refinar")
        // serendipia gets to the 30-day step, from which a card is learned,
        // and ubuntu to the step below it, 12 days.
        try engine.climb(serendipia, to: 5, movingForward: time)
        try engine.climb(ubuntu, to: 4, movingForward: time)
        try engine.meet(petricor)

        time.advance(by: hours(1))

        let progress = try engine.progress(.defaults)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
        #expect(progress.inInbox == 1)
    }

    // The review panel shows a first view only for a new card, and a review
    // only for a due one. Anything else would move a card where it shouldn't
    // go, like a review ahead counting as one on time (ADR 0002).
    @Test("only a new card has a first view, and only a due card is reviewed")
    func onlyNewCardsAreMetAndOnlyDueCardsAreReviewed() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(serendipia)

        #expect(throws: EngineError.cardNotNew(serendipia.id)) {
            try engine.meet(serendipia)
        }
        #expect(throws: EngineError.cardStillNew(ubuntu.id)) {
            try engine.review(ubuntu, .good)
        }
        #expect(throws: EngineError.cardNotDue(serendipia.id)) {
            try engine.review(serendipia, .good)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.record(.firstView, of: 99, responseTime: .seconds(8), trigger: .reviewNow, settings: .defaults)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.record(
                .review(.good), of: 99, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.standing(of: 99, on: ladder)
        }
        #expect(try engine.reviewLog().map(\.cardID) == [serendipia.id])
    }

    // An import that brings a card's progress starts its review log with a
    // placement, which puts it on a step without a first view (ADR 0013).

    /// A placement an import gave the card with the id 1 at the test's
    /// time: on `step`, due at `due`.
    private func placement(on step: Int, dueAt due: Date) -> ReviewLogEntry {
        ReviewLogEntry(placing: 1, on: step, dueAt: due, at: time.now)
    }

    /// A review of the card with the id 1 with `rating`, at `time`, from
    /// review now.
    private func review(_ rating: Rating, at time: Date) -> ReviewLogEntry {
        ReviewLogEntry(
            cardID: 1, kind: .review(rating), answeredAt: time, responseTime: .seconds(3), trigger: .reviewNow)
    }

    @Test("a log that starts with a placement stands on its step until the due time it was given")
    func aPlacementPutsTheCardOnItsStep() throws {
        let due = time.now + days(8)

        let standing = try ladder.standing(after: [placement(on: 4, dueAt: due)])

        #expect(standing == .onLadder(step: 4, due: due))
        #expect(!standing.isDue(at: due - 1))
        #expect(standing.isDue(at: due))
    }

    @Test("good after a placement climbs one step from it, and again sends the card to the first step")
    func reviewsClimbFromAPlacement() throws {
        let due = time.now + days(8)
        let placed = placement(on: 4, dueAt: due)

        let afterGood = try ladder.standing(after: [placed, review(.good, at: due)])
        let afterAgain = try ladder.standing(after: [placed, review(.again, at: due)])
        let afterHard = try ladder.standing(after: [placed, review(.hard, at: due)])

        #expect(afterGood == .onLadder(step: 5, due: due + days(30)))
        #expect(afterAgain == .onLadder(step: 0, due: due + hours(1)))
        #expect(afterHard == .onLadder(step: 4, due: due + days(12)))
    }

    @Test("a placement anywhere but first in a log is unexpected")
    func aPlacementOnlyStartsALog() throws {
        let firstView = ReviewLogEntry(
            cardID: 1, kind: .firstView, answeredAt: time.now, responseTime: .seconds(8), trigger: .reviewNow)
        let placed = placement(on: 2, dueAt: time.now + days(2))

        #expect(throws: UnexpectedReviewLog.self) {
            try ladder.standing(after: [firstView, placed])
        }
        #expect(throws: UnexpectedReviewLog.self) {
            try ladder.standing(after: [placed, review(.good, at: time.now + days(2)), placed])
        }
    }

    // The ladder in Settings can lose steps after an import placed cards on
    // them.
    @Test("a placement on a step the ladder no longer has stands on its last step, due when it was given")
    func aPlacementBeyondTheLadderStandsOnItsLastStep() throws {
        let shortLadder = try #require(Ladder(waits: [.seconds(3_600), .seconds(86_400)]))
        let due = time.now + days(8)

        #expect(try shortLadder.standing(after: [placement(on: 4, dueAt: due)]) == .onLadder(step: 1, due: due))
    }
}
