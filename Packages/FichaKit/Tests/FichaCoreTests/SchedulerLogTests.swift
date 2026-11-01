import FichaCore
import Foundation
import Testing

/// Tests on the review logs the scheduler replays (#404): two devices' joined
/// (ADR 0017), an import's placements, older entries, a change to the
/// settings, and entries it can't follow.
struct SchedulerLogTests {
    /// A way an import from Anki brought graduated, its interval 10 days,
    /// due at the tests' start.
    let graduated = placement(interval: days(10), due: start, at: start - 10 * day)

    // Once Ficha syncs, a card's review log joins what the Mac and the iPhone
    // each recorded without a connection (ADR 0017): here each rated the
    // interval the placement started.
    @Test(
        "an again on one device and a good the other rated at the same moment leave the way in relearning, in any order"
    )
    func againAndGoodAtTheSameMoment() throws {
        let onTheMac = try answering(.again, at: start, after: [graduated]).last
        let onTheIPhone = try answering(.good, at: start, after: [graduated]).last
        let entries = [graduated] + [onTheMac, onTheIPhone].compactMap { $0 }

        let standing = try Scheduler.standard.standing(after: entries)

        #expect(standing.stage == .relearning(step: 0))
        #expect(standing.due == start + hour)
        #expect(try Scheduler.standard.standing(after: entries.reversed()) == standing)
    }

    @Test(
        "a good one device rated before it knew of another device's again, a moment later, leaves the way in relearning"
    )
    func aGoodBeforeAnotherDevicesAgain() throws {
        let onTheIPhone = try answering(.good, at: start - minute, after: [graduated]).last
        let onTheMac = try answering(.again, at: start, after: [graduated]).last

        let standing = try Scheduler.standard.standing(after: [graduated] + [onTheIPhone, onTheMac].compactMap { $0 })

        #expect(standing.stage == .relearning(step: 0))
        #expect(standing.due == start + hour)
    }

    @Test(
        "a good one device rated after another device's again, before it knew of it, moves the way on from relearning, not by the interval it kept"
    )
    func aGoodAfterAnotherDevicesAgain() throws {
        let lapsed = try answering(.again, at: start, after: [graduated])
        let later = start + 5 * minute
        let onTheIPhone = try #require(try answering(.good, at: later, after: [graduated]).last)

        let standing = try Scheduler.standard.standing(after: lapsed + [onTheIPhone])

        // The good on the relearning step the again left the way on
        // graduates it with FSRS's interval after the lapse.
        let afterTheLapse = try Scheduler.standard.preview(of: wayOne, after: lapsed, at: later)
        #expect(standing.stage == .graduated)
        #expect(standing.interval == afterTheLapse.good)
        #expect(try #require(onTheIPhone.interval) > afterTheLapse.good)
        #expect(standing.memory?.lastReview == later)
    }

    @Test(
        "two devices' goods of the same due way both count: the second, the same day, leaves its stability as it was and never shortens its interval"
    )
    func twoGoodsOfTheSameDueWay() throws {
        let onTheMac = try answering(.good, at: start, after: [graduated])
        let later = start + 2 * hour
        let onTheIPhone = try #require(try answering(.good, at: later, after: [graduated]).last)

        let mac = try Scheduler.standard.standing(after: onTheMac)
        let joined = try Scheduler.standard.standing(after: onTheMac + [onTheIPhone])

        #expect(joined.interval == (try Scheduler.standard.preview(of: wayOne, after: onTheMac, at: later).good))
        #expect(joined.due == later.adding(try #require(joined.interval)))
        #expect(try #require(joined.interval) >= #require(mac.interval))
        #expect(joined.memory?.stability == mac.memory?.stability)
        #expect(joined.memory?.lastReview == later)
    }

    @Test(
        "every device works out the same interval for a review it works out again, though each knows the card by its own id"
    )
    func everyDeviceWorksOutTheSameInterval() throws {
        let onTheMac = try answering(.good, at: start, after: [graduated])
        let onTheIPhone = try #require(try answering(.good, at: start + 2 * hour, after: [graduated]).last)
        let log = onTheMac + [onTheIPhone]

        let onCardOne = try Scheduler.standard.standing(after: log)
        let onCardSeven = try Scheduler.standard.standing(after: log.map { $0.ofCard(7) })

        #expect(onCardSeven == onCardOne)
    }

    @Test("a placement under a day starts the way on the first learning step, due when Anki had it due")
    func aPlacementOfALearningCard() throws {
        let placed = placement(interval: minutes(10), ease: nil, due: start + 5 * minute, at: start)

        let standing = try Scheduler.standard.standing(after: [placed])
        let good = try Scheduler.standard.standing(after: answering(.good, at: start + 5 * minute, after: [placed]))

        #expect(standing.stage == .learning(step: 0))
        #expect(standing.due == start + 5 * minute)
        #expect(standing.memory == nil)
        #expect(good.stage == .learning(step: 1))
    }

    @Test(
        "a placement after imported reviews keeps the memory they gave the way, and the interval and due date Anki had")
    func aPlacementAfterImportedReviews() throws {
        // Anki's reviews, which keep its intervals and answer the review
        // before them: 10 minutes, a step it was learning on, then 1, 3 and 8
        // days.
        let imported = [
            review(.again, at: start, keeping: minutes(10)),
            review(.good, at: start + 10 * minute, keeping: days(1)),
            review(.good, at: start + day, keeping: days(3)),
            review(.good, at: start + 4 * day, keeping: days(8)),
        ]
        let importedAt = start + 6 * day
        // Its Set Due Date moved the card later than its last review set.
        let placed = placement(interval: days(8), ease: 2.5, due: importedAt + 9 * day, at: importedAt)

        let reviewed = try Scheduler.standard.standing(after: imported)
        let standing = try Scheduler.standard.standing(after: imported + [placed])

        #expect(reviewed.stage == .graduated)
        #expect(reviewed.due == start + 12 * day)
        #expect(standing.stage == .graduated)
        #expect(standing.interval == days(8))
        #expect(standing.due == importedAt + 9 * day)
        #expect(standing.memory == reviewed.memory)
    }

    @Test("a change to the settings leaves each way where it is, due as it was, until its next review")
    func aChangeToTheSettings() throws {
        let learning = try answering(.good, at: start, after: [])
        let reviewed = try answering(.good, at: start, after: [graduated])
        let changed = try scheduler(
            learningSteps: [hours(2), hours(8)], relearningSteps: [], desiredRetention: 0.8, longestIntervalInDays: 100)

        for log in [learning, reviewed] {
            let before = try Scheduler.standard.standing(after: log)
            let after = try changed.standing(after: log)

            #expect(after == before)
        }
        // From their next review on, the change applies.
        let later = start + 4 * hour
        #expect(try changed.preview(of: wayOne, after: learning, at: later).hard == hours(8))
        #expect(try Scheduler.standard.preview(of: wayOne, after: learning, at: later).hard == hours(4))
        #expect(try changed.preview(of: wayOne, after: reviewed, at: start + 30 * day).again >= days(1))
    }

    @Test("a first view, from before the scheduler, counts as a review rated again")
    func aFirstViewCountsAsAgain() throws {
        let firstView = ReviewLogEntry(
            cardID: 1, kind: .firstView, answeredAt: start, responseTime: .seconds(5), trigger: .appearance,
            uuid: fixedID(at: start, kind: 5))

        let standing = try Scheduler.standard.standing(after: [firstView])
        let again = try Scheduler.standard.standing(after: answering(.again, at: start, after: []))

        #expect(standing == again)
    }

    @Test(
        "a placement without an interval, a graduated one without an ease, or an easy that kept less than a day can't be followed"
    )
    func entriesThatCantBeFollowed() throws {
        let unexpected = SchedulingError.unexpectedReviewLog(cardID: 1)

        #expect(throws: unexpected) {
            try Scheduler.standard.standing(after: [placement(interval: nil, due: start, at: start)])
        }
        #expect(throws: unexpected) {
            try Scheduler.standard.standing(after: [placement(interval: days(10), ease: nil, due: start, at: start)])
        }
        #expect(throws: unexpected) {
            try Scheduler.standard.standing(after: [review(.easy, at: start, keeping: hours(1))])
        }
    }
}

extension ReviewLogEntry {
    /// This entry as a device that knows its card by the id `cardID` holds
    /// it.
    fileprivate func ofCard(_ cardID: Int64) -> ReviewLogEntry {
        if case .placement(let placement) = kind {
            return ReviewLogEntry(placing: cardID, way: way, on: placement, at: answeredAt, uuid: uuid)
        }
        return ReviewLogEntry(
            cardID: cardID, way: way, kind: kind, answeredAt: answeredAt, responseTime: responseTime,
            trigger: trigger ?? .reviewNow, isAhead: isAhead, uuid: uuid, answeredEntry: answeredEntry,
            interval: interval)
    }
}
