import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on how Lucas's answers space his cards, as FSRS spaces them with
/// Anki's learning steps (#404), with the default settings: learning steps
/// of 1 hour and 4 hours, one relearning step of 1 hour, and 90% desired
/// retention. The scheduler's own rules have their tests in FichaCore; these
/// check what the engine records and reads.
struct SchedulingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test(
        "a new card's first review takes any rating, keeps the interval its preview gave, and the card waits it from then",
        arguments: Rating.allCases)
    func aNewCardsFirstReviewKeepsItsPreviewsInterval(rating: Rating) throws {
        let serendipia = try approveCard("serendipia", in: engine)
        #expect(try engine.standing(of: serendipia.id, with: scheduler) == .new)
        time.advance(by: 60)
        let preview = try scheduler.preview(
            of: CardWay(cardID: serendipia.id, way: .frontFirst), after: [], at: time.now)

        try engine.record(
            .review(rating), of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, settings: .defaults)

        let entry = try #require(try engine.reviewLog().last)
        #expect(entry.interval == preview[rating])
        #expect(entry.answeredEntry == nil)
        let standing = try engine.standing(of: serendipia.id, with: scheduler)
        #expect(standing.due == time.now.adding(preview[rating]))
        switch rating {
        case .again, .hard: #expect(standing.stage == .learning(step: 0))
        case .good: #expect(standing.stage == .learning(step: 1))
        case .easy: #expect(standing.stage == .graduated)
        }
    }

    @Test("a new card's first review rated again waits the first learning step, an hour, and good the second, 4 hours")
    func theFirstReviewWaitsTheLearningSteps() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)

        try engine.meet(serendipia)
        try engine.review(ubuntu, .good)

        #expect(
            try engine.standing(of: serendipia.id, with: scheduler).stageAndDue
                == learning(step: 0, due: time.now + hours(1)))
        #expect(
            try engine.standing(of: ubuntu.id, with: scheduler).stageAndDue
                == learning(step: 1, due: time.now + hours(4)))
    }

    @Test("taking back a new card's first review leaves it new, with nothing in its review log")
    func takingBackTheFirstReviewLeavesTheCardNew() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.review(serendipia, .good)

        try engine.takeBackAnswer(of: serendipia.id, way: .frontFirst)

        #expect(try engine.standing(of: serendipia.id, with: scheduler) == .new)
        #expect(try engine.reviewLog().isEmpty)
    }

    // Hard on the first of two learning steps waits halfway to the second,
    // as Anki's does.
    @Test(
        "every review goes into the review log, with its time, trigger, response time, rating and interval, answering the entry before it"
    )
    func reviewsGoIntoTheReviewLog() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let metAt = time.now
        try engine.record(
            .review(.again), of: serendipia.id, responseTime: .milliseconds(8_250), trigger: .reviewNow,
            settings: .defaults)
        time.advance(by: hours(1))

        try engine.record(
            .review(.hard), of: serendipia.id, responseTime: .milliseconds(2_500), trigger: .appearance,
            settings: .defaults)

        let log = try engine.reviewLog()
        #expect(
            log.map(\.withoutIDs) == [
                ReviewLogEntry(
                    cardID: serendipia.id, kind: .review(.again), answeredAt: metAt,
                    responseTime: .milliseconds(8_250), trigger: .reviewNow, interval: .seconds(hours(1))),
                ReviewLogEntry(
                    cardID: serendipia.id, kind: .review(.hard), answeredAt: metAt + hours(1),
                    responseTime: .milliseconds(2_500), trigger: .appearance,
                    interval: .seconds(hours(2) + minutes(30))),
            ])
        #expect(log.map(\.answeredEntry) == [nil, log[0].uuid])
    }

    @Test("good on the last learning step graduates a card, to wait whole days, and again then relearns it, an hour")
    func goodGraduatesAndAgainRelearns() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 2, movingForward: time)

        let graduated = try engine.standing(of: serendipia.id, with: scheduler)
        #expect(graduated.stage == .graduated)
        let interval = try #require(graduated.interval)
        #expect(interval >= .seconds(days(1)))
        #expect(interval.components.seconds.isMultiple(of: Int64(days(1))))

        try engine.reviewWhenDue(serendipia, .again, movingForward: time)

        #expect(
            try engine.standing(of: serendipia.id, with: scheduler).stageAndDue
                == relearning(step: 0, due: time.now + hours(1)))
    }

    @Test("each way of a card that goes both ways is spaced on its own, and the review log says which way each went")
    func eachWayIsSpacedOnItsOwn() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        time.advance(by: hours(1))

        try engine.review(serendipia, .good)
        try engine.review(serendipia, .again, way: .backFirst)

        #expect(
            try engine.standing(of: serendipia.id, with: scheduler).stageAndDue
                == learning(step: 1, due: time.now + hours(4)))
        #expect(
            try engine.standing(of: serendipia.id, way: .backFirst, with: scheduler).stageAndDue
                == learning(step: 0, due: time.now + hours(1)))
        #expect(try engine.reviewLog().map(\.way) == [.frontFirst, .backFirst, .frontFirst, .backFirst])
    }

    @Test(
        "the progress counts say how many cards are due, how many are learned, graduated for 21 days or more, and how many captures wait"
    )
    func progressCountsDueAndLearnedCardsAndTheInbox() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try approveCard("Schadenfreude", in: engine)
        try engine.newCapture("algo para refinar")
        // serendipia gets an interval of 21 days, from which a card is
        // learned, and ubuntu graduates with a shorter one.
        try engine.climbUntilLearned(serendipia, movingForward: time)
        try engine.climb(ubuntu, goods: 2, movingForward: time)
        try engine.meet(petricor)

        time.advance(by: hours(1))

        let progress = try engine.progress(.defaults)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
        #expect(progress.inInbox == 1)
    }

    @Test("the progress counts count each due way, and learned cards by their front-first way alone")
    func progressCountsDueWaysAndLearnedCardsByTheirFrontFirstWay() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id, serendipia.id])
        try engine.meet(ubuntu)
        // ubuntu is learned back first only.
        try engine.climbUntilLearned(ubuntu, way: .backFirst, movingForward: time)
        try engine.meet(serendipia)
        try engine.meet(serendipia, way: .backFirst)

        time.advance(by: hours(1))

        let progress = try engine.progress(.defaults)
        #expect(progress.due == 3)
        #expect(progress.learned == 0)
    }

    // The review panel shows a review only for a new or a due card, unless
    // Lucas asks for more, which reviews it ahead.
    @Test("a card that isn't due takes no answer, but for a review ahead Lucas asked for, and a placement is no answer")
    func onlyNewAndDueCardsAreReviewed() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(serendipia)

        #expect(throws: EngineError.cardNotDue(serendipia.id)) {
            try engine.review(serendipia, .good)
        }
        #expect(throws: EngineError.placementIsNotAnAnswer(ubuntu.id)) {
            try engine.record(
                .placement(Placement(interval: .seconds(days(3)), due: time.now, ease: 2.5)), of: ubuntu.id,
                responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.record(
                .review(.good), of: 99, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.standing(of: 99, with: scheduler)
        }
        #expect(try engine.reviewLog().map(\.cardID) == [serendipia.id])
    }

    @Test("a new way takes its first review, and only a due way a review, whatever the card's other way did")
    func eachWayIsCheckedOnItsOwn() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)

        try engine.review(serendipia, .good, way: .backFirst)
        #expect(throws: EngineError.cardNotDue(serendipia.id)) {
            try engine.review(serendipia, .good, way: .backFirst)
        }
        time.advance(by: hours(1))
        try engine.review(serendipia, .good)
        #expect(throws: EngineError.cardNotDue(serendipia.id)) {
            try engine.review(serendipia, .good)
        }
        #expect(try engine.reviewLog().map(\.way) == [.frontFirst, .backFirst, .frontFirst])
    }

    @Test(
        "a review ahead counts as any review, keeps the interval its preview gave then, and is marked ahead",
        arguments: [Rating.hard, .good])
    func aReviewAheadCounts(rating: Rating) throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 2, movingForward: time)
        time.advance(by: hours(3))
        let log = try engine.reviewLog()
        let preview = try scheduler.preview(
            of: CardWay(cardID: serendipia.id, way: .frontFirst), after: log, at: time.now)

        try engine.record(
            .review(rating), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults,
            reviewingAhead: true)

        let ahead = try #require(try engine.reviewLog().last)
        #expect(ahead.isAhead)
        #expect(ahead.interval == preview[rating])
        #expect(ahead.answeredEntry == log.last?.uuid)
        #expect(try engine.standing(of: serendipia.id, with: scheduler).due == time.now.adding(preview[rating]))
    }

    // A review answers the way's last entry as the scheduler replays them, by
    // when they were answered, not the last one written: the Mac's clock,
    // set back half an hour, times a review ahead before the good given
    // last, which the next review answers, so it keeps its interval when
    // the settings change.
    @Test("a review answers the entry the scheduler replays last, not the last one written, once the clock went back")
    func aReviewAnswersTheEntryReplayedLast() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 1, movingForward: time)
        let good = try #require(try engine.reviewLog().last?.uuid)
        time.advance(by: -minutes(30))
        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults,
            reviewingAhead: true)

        try engine.reviewWhenDue(serendipia, .good, movingForward: time)

        let last = try #require(try engine.reviewLog().last)
        #expect(last.answeredEntry == good)
        let lowerRetention = try #require(scheduler.replacing(desiredRetention: 0.7))
        #expect(
            try engine.standing(of: serendipia.id, with: lowerRetention).due
                == last.answeredAt.adding(try #require(last.interval)))
    }

    @Test("a change to the scheduling settings leaves each card due as it was, until its next review")
    func aChangeToTheSettingsKeepsTheDueTimes() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.climb(serendipia, goods: 3, movingForward: time)
        try engine.review(ubuntu, .hard)
        let longerSteps = try #require(
            Scheduler(
                learningSteps: [.seconds(hours(2)), .seconds(hours(8))], relearningSteps: [.seconds(hours(3))],
                desiredRetention: 0.8, longestIntervalInDays: 36_500, parameters: []))

        for card in [serendipia, ubuntu] {
            #expect(
                try engine.standing(of: card.id, with: longerSteps).due
                    == engine.standing(of: card.id, with: scheduler).due)
        }
    }
}
