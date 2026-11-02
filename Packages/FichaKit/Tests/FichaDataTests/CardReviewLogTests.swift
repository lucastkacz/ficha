import FichaCore
import Foundation
import Testing

@testable import FichaData

/// Tests on a card's review log as the Cards window shows it under the card,
/// in its chart and its list: each review and placement, oldest first, with
/// the interval it left the way waiting (ADR 0002), with the default
/// scheduling settings: learning steps of 1 hour and 4 hours, and a
/// relearning step of 1 hour.
struct CardReviewLogTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    @Test(
        "a card's review log has its entries, oldest first, each with the interval it set: the learning steps', whole days once graduated, and the relearning step's after a lapse"
    )
    func eachEntryHasTheIntervalItSet() throws {
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

        let log = try engine.reviewLogRows(of: serendipia.id, with: scheduler)

        #expect(
            log.map(\.entry.kind) == [
                .review(.again), .review(.good), .review(.good), .review(.hard), .review(.again), .review(.good),
            ])
        let intervals = log.map(\.interval)
        #expect(
            [intervals[0], intervals[1], intervals[4]] == [.seconds(hours(1)), .seconds(hours(4)), .seconds(hours(1))])
        for graduated in [intervals[2], intervals[3], intervals[5]] {
            #expect(graduated >= .seconds(days(1)))
            #expect(graduated.components.seconds.isMultiple(of: 86_400))
        }
        #expect(
            log.first?.entry.withoutIDs
                == ReviewLogEntry(
                    cardID: serendipia.id, kind: .review(.again), answeredAt: metAt, responseTime: .seconds(8),
                    trigger: .reviewNow, interval: .seconds(hours(1))))
        #expect(log.last?.entry.answeredAt == time.now)
    }

    @Test("each good of a graduated card, rated when it's due, waits longer than the one before in its review log")
    func eachGoodWaitsLongerInTheReviewLog() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 6, movingForward: time)

        let log = try engine.reviewLogRows(of: serendipia.id, with: scheduler)

        let graduated = Array(log.map(\.interval).dropFirst(2))
        #expect(graduated.count == 5)
        #expect(zip(graduated, graduated.dropFirst()).allSatisfy { $0 < $1 })
    }

    // An entry's ID seeds the fuzz of its way's graduated intervals (#404),
    // so the engine takes it from its ID source, and these tests from one
    // that counts, the same on every run.
    @Test(
        "the review log's entries take their IDs from the engine's ID source, so the same reviews with the same IDs graduate a card with the same intervals"
    )
    func entriesTakeTheirIDsFromTheEnginesSource() throws {
        var logs: [[ReviewLogRow]] = []
        for _ in 0..<2 {
            let time = ManualTimeSource(now: try morning(of: 14, in: calendar))
            let engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
            let serendipia = try approveCard("serendipia", in: engine)
            try engine.climb(serendipia, goods: 6, movingForward: time)
            logs.append(try engine.reviewLogRows(of: serendipia.id, with: scheduler))
        }

        let ids = CountingIDSource()
        #expect(logs.first?.map(\.entry.uuid) == (0..<7).map { _ in ids.newID() })
        #expect(logs.first?.map(\.interval) == logs.last?.map(\.interval))
    }

    @Test("a card's reviews ahead are in its review log, marked ahead, and an again ahead sends it to relearn")
    func reviewsAheadAreInTheReviewLog() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 2, movingForward: time)
        // Due in days: these are reviews ahead.
        for rating in [Rating.good, .hard, .again] {
            time.advance(by: hours(1))
            try engine.record(
                .review(rating), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow,
                settings: .defaults, reviewingAhead: true)
        }

        let log = try engine.reviewLogRows(of: serendipia.id, with: scheduler)

        #expect(log.map(\.entry.isAhead) == [false, false, false, true, true, true])
        #expect(log.last?.interval == .seconds(hours(1)))
        #expect(
            try engine.standing(of: serendipia.id, with: scheduler).stageAndDue
                == relearning(step: 0, due: time.now + hours(1)))
    }

    // As in Anki, a change to the scheduling settings keeps each review's
    // interval, and spaces the reviews after it (#404).
    @Test(
        "the last interval in a card's review log is the card's own, as the Interval column says it, with the settings Lucas set, which keep it"
    )
    func theReviewLogEndsOnTheCardsInterval() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 3, movingForward: time)
        try engine.reviewWhenDue(serendipia, .again, movingForward: time)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.climb(ubuntu, goods: 6, movingForward: time)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.meet(ojala)
        time.advance(by: minutes(10))
        try engine.record(
            .review(.good), of: ojala.id, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults,
            reviewingAhead: true)
        try approveCard("acaso", in: engine)
        // Lucas changed the settings the cards were reviewed with.
        let changed = try #require(
            Scheduler(
                learningSteps: [.seconds(minutes(10)), .seconds(hours(8))], relearningSteps: [.seconds(hours(3))],
                desiredRetention: 0.8, longestIntervalInDays: 365, parameters: []))

        var lastIntervalsBySettings: [[Duration?]] = []
        for settingsScheduler in [scheduler, changed] {
            let rows = try engine.cardRows(in: .all, with: settingsScheduler)
            let lastIntervals = try rows.map {
                try engine.reviewLogRows(of: $0.id, with: settingsScheduler).last?.interval
            }
            #expect(rows.map(\.frontFirst.interval) == lastIntervals)
            lastIntervalsBySettings.append(lastIntervals)
        }

        #expect(lastIntervalsBySettings.first == lastIntervalsBySettings.last)
        #expect(lastIntervalsBySettings.first?.last == .some(nil))
    }

    @Test(
        "a card that goes both ways has both ways' entries in its review log, each saying its way, with the interval it set that way"
    )
    func eachEntrySaysItsWayAndHasItsWaysInterval() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        try engine.reviewWhenDue(serendipia, .again, way: .backFirst, movingForward: time)
        try engine.reviewWhenDue(serendipia, .good, way: .backFirst, movingForward: time)

        let log = try engine.reviewLogRows(of: serendipia.id, with: scheduler)

        #expect(log.map(\.entry.way) == [.frontFirst, .backFirst, .frontFirst, .backFirst, .backFirst])
        #expect(
            log.map(\.entry.kind) == [
                .review(.again), .review(.again), .review(.good), .review(.again), .review(.good),
            ])
        #expect(log.map(\.interval) == [hours(1), hours(1), hours(4), hours(1), hours(4)].map { .seconds($0) })
        let row = try #require(try engine.cardRows(in: .all, with: scheduler).first)
        #expect(row.frontFirst.interval == .seconds(hours(4)))
        #expect(row.backFirst?.interval == .seconds(hours(4)))
    }

    // Once Ficha syncs, another device's entries arrive after this device's,
    // whenever they were answered (ADR 0017). Here the iPhone had its first
    // review of serendipia 5 minutes after the Mac, and of ubuntu after the
    // Mac's good: each is spaced again where it falls, as are the Mac's
    // reviews after it.
    @Test(
        "a card's review log lists another device's entries by when they were answered, each with the interval it set where it falls"
    )
    func anotherDevicesEntriesAreListedByWhenTheyWereAnswered() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let metAt = time.now
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        try engine.reviewWhenDue(ubuntu, .good, movingForward: time)
        try engine.receive(firstReview(of: serendipia, at: metAt + minutes(5)))
        try engine.receive(firstReview(of: ubuntu, at: time.now + hours(1)))

        let serendipiaLog = try engine.reviewLogRows(of: serendipia.id, with: scheduler)
        let ubuntuLog = try engine.reviewLogRows(of: ubuntu.id, with: scheduler)

        #expect(serendipiaLog.map(\.entry.kind) == [.review(.again), .review(.again), .review(.good)])
        #expect(serendipiaLog.map(\.interval) == [hours(1), hours(1), hours(4)].map { .seconds($0) })
        #expect(ubuntuLog.map(\.entry.kind) == [.review(.again), .review(.good), .review(.again)])
        #expect(ubuntuLog.map(\.interval) == [hours(1), hours(4), hours(1)].map { .seconds($0) })
        let rows = try engine.cardRows(in: .all, with: scheduler)
        #expect(rows.map(\.frontFirst.interval) == [serendipiaLog.last?.interval, ubuntuLog.last?.interval])
    }

    @Test("a card's Last seen is its latest review, also when another device's earlier one came last")
    func lastSeenIsTheLatestAnswer() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let metAt = time.now
        try engine.meet(serendipia)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        try engine.receive(firstReview(of: serendipia, at: metAt + minutes(5)))

        let row = try #require(try engine.cardRows(in: .all, with: scheduler).first)

        #expect(row.lastSeen == time.now)
    }

    /// The first review of `card`, rated again, that another device recorded
    /// at `time`, from review now: it answered no entry, and kept the first
    /// learning step's hour.
    private func firstReview(of card: Card, at time: Date) -> ReviewLogEntry {
        ReviewLogEntry(
            cardID: card.id, kind: .review(.again), answeredAt: time, responseTime: .seconds(8), trigger: .reviewNow,
            uuid: UUID(), interval: .seconds(hours(1)))
    }

    @Test("a new card's review log is empty, and a card that doesn't exist isn't found")
    func aNewCardsReviewLogIsEmpty() throws {
        let serendipia = try approveCard("serendipia", in: engine)

        #expect(try engine.reviewLogRows(of: serendipia.id, with: scheduler).isEmpty)
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.reviewLogRows(of: 99, with: scheduler)
        }
    }
}

extension Engine {
    /// Adds `entry` to the review log as it comes from another device: at
    /// the end, and without recording it to send.
    fileprivate func receive(_ entry: ReviewLogEntry) throws {
        try writeWithoutRecording { db in try insert(entry, ids: ids, in: db) }
    }
}
