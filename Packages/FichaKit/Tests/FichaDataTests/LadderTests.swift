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

    // Hard keeps the card on the first step, so the review keeps its hour.
    @Test(
        "every first view and review goes into the review log, with its time, trigger, response time and rating, and a review with its interval"
    )
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
            try engine.reviewLog().map(\.withoutIDs) == [
                ReviewLogEntry(
                    cardID: serendipia.id, kind: .firstView, answeredAt: firstViewTime,
                    responseTime: .milliseconds(8_250),
                    trigger: .reviewNow),
                ReviewLogEntry(
                    cardID: serendipia.id, kind: .review(.hard), answeredAt: firstViewTime + hours(1),
                    responseTime: .milliseconds(2_500), trigger: .reviewNow, interval: .seconds(hours(1))),
            ]
        )
    }

    @Test("each way of a card that goes both ways climbs on its own, and the review log says which way each went")
    func eachWayClimbsOnItsOwn() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        time.advance(by: hours(1))

        try engine.review(serendipia, .good)
        try engine.review(serendipia, .again, way: .backFirst)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 1, due: time.now + hours(4)))
        #expect(
            try engine.standing(of: serendipia.id, way: .backFirst, on: ladder)
                == .onLadder(step: 0, due: time.now + hours(1)))
        #expect(try engine.reviewLog().map(\.way) == [.frontFirst, .backFirst, .frontFirst, .backFirst])
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

    @Test("the progress counts count each due way, and learned cards by their front-first way alone")
    func progressCountsDueWaysAndLearnedCardsByTheirFrontFirstWay() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id, serendipia.id])
        try engine.meet(ubuntu)
        // ubuntu gets to the 30-day step back first only.
        try engine.climb(ubuntu, to: 5, way: .backFirst, movingForward: time)
        try engine.meet(serendipia)
        try engine.meet(serendipia, way: .backFirst)

        time.advance(by: hours(1))

        let progress = try engine.progress(.defaults)
        #expect(progress.due == 3)
        #expect(progress.learned == 0)
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

    @Test("only a new way has a first view, and only a due way is reviewed, whatever the card's other way did")
    func eachWayIsCheckedOnItsOwn() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)

        #expect(throws: EngineError.cardStillNew(serendipia.id)) {
            try engine.review(serendipia, .good, way: .backFirst)
        }
        try engine.meet(serendipia, way: .backFirst)
        #expect(throws: EngineError.cardNotNew(serendipia.id)) {
            try engine.meet(serendipia, way: .backFirst)
        }
        time.advance(by: hours(1))
        try engine.review(serendipia, .good)
        #expect(throws: EngineError.cardNotDue(serendipia.id)) {
            try engine.review(serendipia, .good)
        }
        try engine.review(serendipia, .good, way: .backFirst)
        #expect(try engine.reviewLog().map(\.way) == [.frontFirst, .backFirst, .frontFirst, .backFirst])
    }

    // An import that brings a card's progress starts its review log with a
    // placement, which puts it on a step without a first view (ADR 0013).

    /// A placement an import gave the card with the id 1 at the test's
    /// time: on `step`, due at `due`.
    private func placement(on step: Int, dueAt due: Date) -> ReviewLogEntry {
        ReviewLogEntry(placing: 1, on: Placement(step: step, due: due), at: time.now, uuid: UUID())
    }

    /// A review of the card with the id 1 with `rating`, at `time`, from
    /// review now, a review ahead when `ahead` says so. It answered
    /// `answered`, or, when the test doesn't say, the entry before it, as a
    /// review from before Ficha kept which entry each answered.
    private func review(
        _ rating: Rating, at time: Date, answering answered: ReviewLogEntry? = nil, ahead: Bool = false
    ) -> ReviewLogEntry {
        ReviewLogEntry(
            cardID: 1, kind: .review(rating), answeredAt: time, responseTime: .seconds(3), trigger: .reviewNow,
            isAhead: ahead, uuid: UUID(), answeredEntry: answered?.uuid)
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

    // Once Ficha syncs, a card reviewed on the Mac and on the iPhone, each
    // without a connection, keeps both reviews: each device rated it for the
    // wait it knew of, the one its last entry started, which each review
    // names, and the card's step is worked out again from the log that joins
    // them (ADR 0017).

    /// The first view of the card with the id 1 at `time`, from review now.
    private func firstView(at time: Date) -> ReviewLogEntry {
        ReviewLogEntry(
            cardID: 1, kind: .firstView, answeredAt: time, responseTime: .seconds(8), trigger: .reviewNow, uuid: UUID())
    }

    @Test("two “Know it” ratings for one wait, one on each device, climb one step")
    func twoKnowItsForOneWaitClimbOneStep() throws {
        let firstViewed = firstView(at: time.now)
        let onTheMac = review(.good, at: time.now + hours(1), answering: firstViewed)
        let onTheIPhone = review(.good, at: time.now + hours(1) + minutes(30), answering: firstViewed)

        let standing = try ladder.standing(after: [firstViewed, onTheMac, onTheIPhone])

        #expect(standing == .onLadder(step: 1, due: time.now + hours(1) + hours(4)))
    }

    // However many hours apart the two devices rated it.
    @Test("the iPhone's “Know it” at 14:00 for the 4-hour wait the Mac's “Know it” answered at 9:00 climbs no further")
    func aKnowItHoursLaterForTheSameWaitDoesntClimb() throws {
        let nine = time.now
        let firstViewed = firstView(at: nine - hours(5))
        let climbed = review(.good, at: nine - hours(4), answering: firstViewed)
        let onTheMac = review(.good, at: nine, answering: climbed)
        let onTheIPhone = review(.good, at: nine + hours(5), answering: climbed)

        let standing = try ladder.standing(after: [firstViewed, climbed, onTheMac, onTheIPhone])

        #expect(standing == .onLadder(step: 2, due: nine + days(2)))
    }

    // Here each device met the card on its own, without a connection.
    @Test("“Know it” on one device and then “Don't know” on the other, for one wait, end where “Don't know” leaves it")
    func knowItThenDontKnowForOneWaitEndsOnTheFirstStep() throws {
        let metOnTheMac = firstView(at: time.now)
        let metOnTheIPhone = firstView(at: time.now + minutes(5))
        let onTheMac = review(.good, at: time.now + hours(1), answering: metOnTheMac)
        let onTheIPhone = review(.again, at: time.now + hours(1) + minutes(10), answering: metOnTheIPhone)

        let standing = try ladder.standing(after: [metOnTheMac, metOnTheIPhone, onTheMac, onTheIPhone])

        #expect(standing == .onLadder(step: 0, due: time.now + hours(1) + minutes(10) + hours(1)))
    }

    @Test("“Don't know” on one device and then “Know it” on the other, for one wait, both count")
    func dontKnowThenKnowItForOneWaitBothCount() throws {
        let metOnTheMac = firstView(at: time.now)
        let metOnTheIPhone = firstView(at: time.now + minutes(5))
        let onTheMac = review(.again, at: time.now + hours(1), answering: metOnTheMac)
        let onTheIPhone = review(.good, at: time.now + hours(1) + minutes(10), answering: metOnTheIPhone)

        let standing = try ladder.standing(after: [metOnTheMac, metOnTheIPhone, onTheMac, onTheIPhone])

        #expect(standing == .onLadder(step: 1, due: time.now + hours(1) + minutes(10) + hours(4)))
    }

    @Test("a “Know it” for a wait the card already climbed doesn't climb again after a “Don't know” since")
    func aKnowItForAClimbedWaitDoesntClimbAfterADontKnow() throws {
        let firstViewed = firstView(at: time.now)
        let knownOnTheMac = review(.good, at: time.now + hours(1), answering: firstViewed)
        let forgottenOnTheMac = review(.again, at: time.now + hours(2), answering: knownOnTheMac, ahead: true)
        let knownOnTheIPhone = review(.good, at: time.now + hours(3), answering: firstViewed)

        let standing = try ladder.standing(after: [firstViewed, knownOnTheMac, forgottenOnTheMac, knownOnTheIPhone])

        #expect(standing == .onLadder(step: 0, due: time.now + hours(2) + hours(1)))
    }

    // The iPhone rated it ahead, since it didn't know of the Mac's “Don't
    // know”, which had made the card due by then.
    @Test("a review ahead on one device counts once another device's “Don't know” had made the card due")
    func aReviewAheadCountsOnceAnotherDevicesDontKnowMadeTheCardDue() throws {
        let firstViewed = firstView(at: time.now)
        let known = review(.good, at: time.now + hours(1), answering: firstViewed)
        let forgottenOnTheMac = review(.again, at: time.now + hours(2), answering: known, ahead: true)
        let knownAheadOnTheIPhone = review(.good, at: time.now + hours(4), answering: known, ahead: true)

        let standing = try ladder.standing(after: [firstViewed, known, forgottenOnTheMac, knownAheadOnTheIPhone])

        #expect(standing == .onLadder(step: 1, due: time.now + hours(4) + hours(4)))
    }

    @Test("a first view on each device counts once: the second neither moves the card nor restarts its wait")
    func twoFirstViewsCountOnce() throws {
        let onTheMac = firstView(at: time.now)
        let onTheIPhone = firstView(at: time.now + minutes(5))
        let reviewedOnTheMac = review(.good, at: time.now + hours(1), answering: onTheMac)

        let afterFirstViews = try ladder.standing(after: [onTheMac, onTheIPhone])
        let afterReview = try ladder.standing(after: [onTheMac, onTheIPhone, reviewedOnTheMac])

        #expect(afterFirstViews == .onLadder(step: 0, due: time.now + hours(1)))
        #expect(afterReview == .onLadder(step: 1, due: time.now + hours(1) + hours(4)))
    }

    // A device can get a card before the placement its import gave it, and
    // show it new.
    @Test("an import's placement starts the card's log even when another device gave it a first view")
    func aPlacementStartsTheLogBeforeAnotherDevicesFirstView() throws {
        let due = time.now + days(8)
        let placed = placement(on: 4, dueAt: due)
        let firstViewedOnTheIPhone = firstView(at: time.now + hours(1))

        #expect(try ladder.standing(after: [firstViewedOnTheIPhone, placed]) == .onLadder(step: 4, due: due))
    }

    @Test("“Know it” and “Don't know” rated at the same moment on two devices end where “Don't know” leaves the card")
    func dontKnowHasTheLastWordAtTheSameMoment() throws {
        let firstViewed = firstView(at: time.now)
        let onTheMac = review(.good, at: time.now + hours(1), answering: firstViewed)
        let onTheIPhone = review(.again, at: time.now + hours(1), answering: firstViewed)

        let macFirst = try ladder.standing(after: [firstViewed, onTheMac, onTheIPhone])
        let iPhoneFirst = try ladder.standing(after: [firstViewed, onTheIPhone, onTheMac])

        #expect(macFirst == .onLadder(step: 0, due: time.now + hours(1) + hours(1)))
        #expect(iPhoneFirst == macFirst)
    }

    @Test("the order two devices' entries arrive in, ties included, doesn't change where the card stands")
    func theOrderEntriesArriveInDoesntMatter() throws {
        let metOnTheMac = firstView(at: time.now)
        let metOnTheIPhone = firstView(at: time.now + minutes(5))
        let forgottenOnTheIPhone = review(.again, at: time.now + hours(1), answering: metOnTheIPhone)
        let entries = [
            metOnTheMac,
            metOnTheIPhone,
            review(.good, at: time.now + hours(1), answering: metOnTheMac),
            forgottenOnTheIPhone,
            review(.good, at: time.now + hours(1) + minutes(10), answering: forgottenOnTheIPhone),
        ]

        let standings = try everyOrder(of: entries).map { order in try ladder.standing(after: order) }

        #expect(standings.count == 120)
        #expect(standings.allSatisfy { $0 == .onLadder(step: 1, due: time.now + hours(1) + minutes(10) + hours(4)) })
    }

    // On one device, each review answers the entry before it, so however
    // early the look-ahead lets an appearance bring a card along, the ladder
    // never takes its next “Know it” for another device's.
    @Test("on one device, a “Know it” an appearance brought along early climbs, however close the ladder's steps")
    func aKnowItTheLookAheadBroughtClimbs() throws {
        var settings = ReviewSettings.defaults
        settings.ladder = try #require(
            Ladder(waits: [.seconds(minutes(20)), .seconds(minutes(30)), .seconds(hours(1))]))
        settings.lookAhead = .seconds(minutes(60))
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.record(
            .firstView, of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, settings: settings)

        for _ in 1...2 {
            time.advance(by: 60)
            try engine.record(
                .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .appearance,
                settings: settings)
        }

        #expect(
            try engine.standing(of: serendipia.id, on: settings.ladder) == .onLadder(step: 2, due: time.now + hours(1)))
    }

    // A changed ladder re-times every card from its history, but keeps its
    // step: a wait Lucas lengthens doesn't make the “Know it” ratings he gave
    // on time look like another device's.
    @Test("a card climbed on one device keeps its step after Lucas lengthens a wait it climbed past")
    func aLengthenedWaitKeepsTheStep() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 3, movingForward: time)
        var waits = ladder.waits
        waits[1] = .seconds(hours(12))
        let lengthened = try #require(Ladder(waits: waits))

        #expect(try engine.standing(of: serendipia.id, on: lengthened) == .onLadder(step: 3, due: time.now + days(5)))
    }

    // A review answers the way's last entry as the ladder replays them, by
    // when they were answered, not the last one written.
    @Test("on one device, a “Know it” climbs after a review ahead the Mac's clock, set back, timed before the last")
    func aReviewAnswersTheLatestEntryAfterTheClockWentBack() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 1, movingForward: time)
        time.advance(by: -minutes(30))
        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults,
            reviewingAhead: true)

        try engine.reviewWhenDue(serendipia, .good, movingForward: time)

        #expect(try engine.standing(of: serendipia.id, on: ladder) == .onLadder(step: 2, due: time.now + days(2)))
    }

    /// Every order of `entries`.
    private func everyOrder(of entries: [ReviewLogEntry]) -> [[ReviewLogEntry]] {
        guard let first = entries.first else {
            return [[]]
        }
        return everyOrder(of: Array(entries.dropFirst())).flatMap { rest in
            rest.indices.map { index in
                var order = rest
                order.insert(first, at: index)
                return order
            } + [rest + [first]]
        }
    }
}
