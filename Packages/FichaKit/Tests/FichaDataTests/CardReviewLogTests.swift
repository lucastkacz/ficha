import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a card's review log as the Cards window shows it under the card,
/// in its chart and its list: each first view and review, oldest first, with
/// the step the card stood on after it (ADR 0002), on the default ladder: 1
/// hour, 4 hours, 2 days, 5 days, 12 days, 30 days and 75 days. Steps count
/// from 0, the first step.
struct CardReviewLogTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test(
        "a card's review log has its entries, oldest first, each with the step after it: good climbs, hard stays, again falls"
    )
    func eachEntryHasTheStepTheCardStoodOnAfterIt() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let metAt = time.now
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        try engine.reviewWhenDue(serendipia, .hard, movingForward: time)
        try engine.reviewWhenDue(serendipia, .again, movingForward: time)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)

        let log = try engine.reviewLogRows(of: serendipia.id, on: ladder)

        #expect(
            log.map(\.entry.kind) == [
                .firstView, .review(.good), .review(.good), .review(.hard), .review(.again), .review(.good),
            ])
        #expect(log.map(\.step) == [0, 1, 2, 2, 0, 1])
        #expect(
            log.first?.entry.withoutIDs
                == ReviewLogEntry(
                    cardID: serendipia.id, kind: .firstView, answeredAt: metAt, responseTime: .seconds(8),
                    trigger: .reviewNow))
        #expect(log.last?.entry.answeredAt == time.now)
    }

    @Test("on the last step, a good review leaves the card there in its review log")
    func theLastStepRepeatsInTheReviewLog() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 6, movingForward: time)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)

        let log = try engine.reviewLogRows(of: serendipia.id, on: ladder)

        #expect(log.map(\.step) == [0, 1, 2, 3, 4, 5, 6, 6])
    }

    @Test("a review ahead's good or hard leaves the card on its step in its review log, and its again sends it back")
    func onlyAReviewAheadsAgainMovesTheCardInTheReviewLog() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        // Due in 2 days: these are reviews ahead.
        for rating in [Rating.good, .hard, .again] {
            time.advance(by: hours(1))
            try engine.record(
                .review(rating), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow,
                settings: .defaults, reviewingAhead: true)
        }

        let log = try engine.reviewLogRows(of: serendipia.id, on: ladder)

        #expect(log.map(\.entry.isAhead) == [false, false, false, true, true, true])
        #expect(log.map(\.step) == [0, 1, 2, 2, 2, 0])
    }

    @Test("the last step in a card's review log is the card's own, as the Step column says it, on the ladder Lucas set")
    func theReviewLogEndsOnTheCardsStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 3, movingForward: time)
        try engine.reviewWhenDue(serendipia, .again, movingForward: time)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.climb(ubuntu, to: 6, movingForward: time)
        try engine.reviewWhenDue(ubuntu, .good, movingForward: time)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.meet(ojala)
        time.advance(by: minutes(10))
        try engine.record(
            .review(.good), of: ojala.id, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults,
            reviewingAhead: true)
        try approveCard("acaso", in: engine)
        // A ladder of 10 minutes, 1 day and 3 days: Lucas shortened the one
        // the cards climbed, in Settings.
        let shortLadder = try #require(Ladder(waits: [.seconds(minutes(10)), .seconds(days(1)), .seconds(days(3))]))

        for (settingsLadder, steps) in [(ladder, [1, 6, 0, nil]), (shortLadder, [1, 2, 0, nil])] {
            let rows = try engine.cardRows(in: .all, on: settingsLadder)
            #expect(rows.map(\.frontFirst.step) == steps)
            #expect(try rows.map { try engine.reviewLogRows(of: $0.id, on: settingsLadder).last?.step } == steps)
        }
    }

    @Test(
        "a card that goes both ways has both ways' entries in its review log, each saying its way, with the step that way stood on after it"
    )
    func eachEntrySaysItsWayAndHasItsWaysStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        try engine.reviewWhenDue(serendipia, .again, way: .backFirst, movingForward: time)
        try engine.reviewWhenDue(serendipia, .good, way: .backFirst, movingForward: time)

        let log = try engine.reviewLogRows(of: serendipia.id, on: ladder)

        #expect(log.map(\.entry.way) == [.frontFirst, .backFirst, .frontFirst, .backFirst, .backFirst])
        #expect(log.map(\.entry.kind) == [.firstView, .firstView, .review(.good), .review(.again), .review(.good)])
        #expect(log.map(\.step) == [0, 0, 1, 0, 1])
        let row = try #require(try engine.cardRows(in: .all, on: ladder).first)
        #expect(row.frontFirst.step == 1)
        #expect(row.backFirst?.step == 1)
    }

    @Test("a new card's review log is empty, and a card that doesn't exist isn't found")
    func aNewCardsReviewLogIsEmpty() throws {
        let serendipia = try approveCard("serendipia", in: engine)

        #expect(try engine.reviewLogRows(of: serendipia.id, on: ladder).isEmpty)
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.reviewLogRows(of: 99, on: ladder)
        }
    }
}
