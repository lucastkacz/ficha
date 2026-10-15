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

        try engine.record(.firstView, of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, ladder: ladder)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 0, due: time.now + hours(1)))
    }

    @Test("good moves a card up one step")
    func goodMovesTheCardUpOneStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.record(.firstView, of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, ladder: ladder)
        time.advance(by: hours(1))

        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, ladder: ladder)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 1, due: time.now + hours(4)))
    }

    @Test("hard keeps a card on its step, to wait that step's wait again")
    func hardKeepsTheCardOnItsStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try climb(serendipia, to: 1)

        try reviewWhenDue(serendipia, .hard)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 1, due: time.now + hours(4)))
    }

    @Test("again sends a card back to the first step")
    func againSendsTheCardBackToTheFirstStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try climb(serendipia, to: 3)

        try reviewWhenDue(serendipia, .again)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 0, due: time.now + hours(1)))
    }

    @Test("good on the last step keeps a card there, to come back every 75 days")
    func theLastStepRepeats() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try climb(serendipia, to: 6)
        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 6, due: time.now + days(75)))

        try reviewWhenDue(serendipia, .good)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 6, due: time.now + days(75)))
    }

    @Test("every first view and review goes into the review log, with its time, trigger, response time and rating")
    func firstViewsAndReviewsGoIntoTheReviewLog() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let firstViewTime = time.now
        try engine.record(
            .firstView, of: serendipia.id, responseTime: .milliseconds(8_250), trigger: .reviewNow, ladder: ladder)
        time.advance(by: hours(1))

        try engine.record(
            .review(.hard), of: serendipia.id, responseTime: .milliseconds(2_500), trigger: .reviewNow, ladder: ladder)

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
        try engine.capture(text: "algo para refinar", note: nil, source: nil)
        // serendipia gets to the 30-day step, from which a card is learned,
        // and ubuntu to the step below it, 12 days.
        try climb(serendipia, to: 5)
        try climb(ubuntu, to: 4)
        try engine.meet(petricor)

        time.advance(by: hours(1))

        let progress = try engine.progress(.defaults)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
        #expect(progress.capturesInInbox == 1)
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
            try engine.record(.firstView, of: 99, responseTime: .seconds(8), trigger: .reviewNow, ladder: ladder)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.record(.review(.good), of: 99, responseTime: .seconds(3), trigger: .reviewNow, ladder: ladder)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.standing(of: 99, on: ladder)
        }
        #expect(try engine.reviewLog().map(\.cardID) == [serendipia.id])
    }

    /// Puts a new card on `step`: its first view now, and then good each time
    /// it's due.
    private func climb(_ card: Card, to step: Int) throws {
        try engine.meet(card)
        for _ in 0..<step {
            try reviewWhenDue(card, .good)
        }
    }

    /// Waits until a card on the ladder is due, and reviews it with `rating`.
    private func reviewWhenDue(_ card: Card, _ rating: Rating) throws {
        time.move(to: try #require(try engine.standing(of: card.id, on: ladder).due))
        try engine.review(card, rating)
    }
}
