import FichaCore
import Foundation
import Testing

/// Tests on the review logs the scheduler replays (#404): two devices' joined
/// (ADR 0017), an import's placements, older entries, a change to the
/// settings, and entries it can't follow.
struct SchedulerLogTests {
    // Once Ficha syncs, a card's review log joins what the Mac and the iPhone
    // each recorded without a connection (ADR 0017): here each rated the
    // interval the graduated placement started.
    @Test(
        "an again on one device and a good the other rated at the same moment leave the way in relearning, in any order"
    )
    func againAndGoodAtTheSameMoment() throws {
        let onTheMac = try #require(try answering(.again, at: start, after: [graduated]).last)
        let onTheIPhone = try #require(try answering(.good, at: start, after: [graduated]).last)
        let entries = [graduated, onTheMac, onTheIPhone]

        let standing = try Scheduler.standard.standing(after: entries)

        #expect(standing.stage == .relearning(step: 0))
        #expect(standing.due == start + hour)
        #expect(try Scheduler.standard.standing(after: entries.reversed()) == standing)
    }

    @Test(
        "a good one device rated before it knew of another device's again, a moment later, leaves the way in relearning"
    )
    func aGoodBeforeAnotherDevicesAgain() throws {
        let onTheIPhone = try #require(try answering(.good, at: start - minute, after: [graduated]).last)
        let onTheMac = try #require(try answering(.again, at: start, after: [graduated]).last)

        let standing = try Scheduler.standard.standing(after: [graduated, onTheIPhone, onTheMac])

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
        "two devices' first reviews of a new way, easy on one and good or hard on the other, leave it where the later one puts it, in either order"
    )
    func twoDevicesFirstReviewsOfANewWay() throws {
        for (onTheMac, onTheIPhone) in [(Rating.easy, Rating.good), (.good, .easy), (.easy, .hard), (.hard, .easy)] {
            let first = try #require(try answering(onTheMac, at: start, after: []).last)
            let later = start + minute
            let second = try #require(try answering(onTheIPhone, at: later, after: []).last)

            let standing = try Scheduler.standard.standing(after: [first, second])

            // Neither knew of the other, so the later review gets the
            // interval its rating sets after the earlier one: easy graduates
            // the way, and a graduated way's good or hard keeps it graduated.
            let afterTheFirst = try Scheduler.standard.preview(of: wayOne, after: [first], at: later)
            #expect(standing.stage == .graduated)
            #expect(standing.interval == afterTheFirst[onTheIPhone])
            #expect(standing.due == later.adding(afterTheFirst[onTheIPhone]))
        }
    }

    @Test(
        "a review that answered an entry the log doesn't hold, or none after the way's first entry, gets its interval worked out again"
    )
    func aReviewThatAnsweredAnotherEntry() throws {
        let preview = try Scheduler.standard.preview(of: wayOne, after: [graduated], at: start)
        let unknown = fixedID(at: start - day, kind: 9)

        for answered in [unknown, nil] {
            let kept = review(.good, at: start, keeping: .days(99), answering: answered)

            let standing = try Scheduler.standard.standing(after: [graduated, kept])

            #expect(standing.interval == preview.good)
        }
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
        let placed = placement(interval: .minutes(10), ease: nil, due: start + 5 * minute, at: start)

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
        // Anki's reviews, which keep its intervals, each answering the review
        // before it, and the first none: 10 minutes, a step it was learning
        // on, then 1, 3 and 8 days.
        var imported: [ReviewLogEntry] = []
        let history: [(Rating, Date, Duration)] = [
            (.again, start, .minutes(10)), (.good, start + 10 * minute, .days(1)), (.good, start + day, .days(3)),
            (.good, start + 4 * day, .days(8)),
        ]
        for (rating, time, interval) in history {
            imported.append(review(rating, at: time, keeping: interval, answering: imported.last?.uuid))
        }
        let importedAt = start + 6 * day
        // Its Set Due Date moved the card later than its last review set.
        let placed = placement(interval: .days(8), ease: 2.5, due: importedAt + 9 * day, at: importedAt)

        let reviewed = try Scheduler.standard.standing(after: imported)
        let standing = try Scheduler.standard.standing(after: imported + [placed])

        #expect(reviewed.stage == .graduated)
        #expect(reviewed.due == start + 12 * day)
        #expect(standing.stage == .graduated)
        #expect(standing.interval == .days(8))
        #expect(standing.due == importedAt + 9 * day)
        #expect(standing.memory == reviewed.memory)
    }

    @Test("a change to the settings leaves each way where it is, due as it was, until its next review")
    func aChangeToTheSettings() throws {
        let learning = try answering(.good, at: start, after: [])
        let reviewed = try answering(.good, at: start, after: [graduated])
        let changed = try scheduler(
            learningSteps: [.hours(2), .hours(8)], relearningSteps: [], desiredRetention: 0.8,
            longestIntervalInDays: 100)

        for log in [learning, reviewed] {
            let before = try Scheduler.standard.standing(after: log)
            let after = try changed.standing(after: log)

            #expect(after == before)
        }
        // From their next review on, the change applies.
        let later = start + 4 * hour
        #expect(try changed.preview(of: wayOne, after: learning, at: later).hard == .hours(8))
        #expect(try Scheduler.standard.preview(of: wayOne, after: learning, at: later).hard == .hours(4))
        #expect(try changed.preview(of: wayOne, after: reviewed, at: start + 30 * day).again >= .days(1))
    }

    @Test(
        "a hard on a single learning step of 20 hours, which waits more than a day, leaves the way on that step after the steps change"
    )
    func aLongHardAfterTheStepsChange() throws {
        let oneLongStep = try scheduler(learningSteps: [.hours(20)])
        let log = try answering(.hard, at: start, after: [], on: oneLongStep)

        let standing = try Scheduler.standard.standing(after: log)

        // 1.5 times the step: 30 hours, which isn't whole days, as a
        // graduated interval always is.
        #expect(standing.stage == .learning(step: 0))
        #expect(standing.interval == .hours(30))
        #expect(standing.due == start + 30 * hour)
    }

    @Test(
        "a log whose reviews kept no interval, as before the scheduler, comes out with each review keeping the one it sets, answering the entry before it"
    )
    func aLogKeepsTheIntervalsItSets() throws {
        let log = [
            graduated, review(.good, at: start + 2 * hour), review(.again, at: start + 12 * day),
            review(.good, at: start + 12 * day + hour),
        ]

        let kept = try Scheduler.standard.keepingIntervals(of: log.reversed())

        #expect(kept.map(\.uuid) == log.map(\.uuid))
        #expect(kept.map(\.answeredEntry) == [nil] + log.dropLast().map(\.uuid))
        var replayed: [ReviewLogEntry] = []
        for entry in kept {
            replayed.append(entry)
            #expect(entry.interval ?? .zero > .zero || entry == graduated)
            if case .review = entry.kind {
                #expect(try Scheduler.standard.standing(after: replayed).interval == entry.interval)
            }
        }
        // Kept, the intervals hold once the settings change.
        let longer = try scheduler(learningSteps: [.hours(2), .hours(8)], relearningSteps: [.hours(3)])
        #expect(try longer.standing(after: kept) == Scheduler.standard.standing(after: kept))
    }

    @Test("a way's lapses are its agains while graduated, not those of a way still learning or relearning")
    func lapsesAreAgainsOfAGraduatedWay() throws {
        let learningAgain = review(.again, at: start - 20 * day)
        let lapse = review(.again, at: start + hour)
        let relearningAgain = review(.again, at: start + 2 * hour)
        let log = [
            learningAgain, graduated, lapse, relearningAgain, review(.good, at: start + 3 * hour),
            review(.good, at: start + 2 * day),
        ]

        #expect(try Scheduler.standard.lapses(after: log) == [lapse])
    }

    @Test(
        "a placement with an interval below none, a graduated one without an ease, or an easy that kept less than a day can't be followed"
    )
    func entriesThatCantBeFollowed() throws {
        let unexpected = SchedulingError.unexpectedReviewLog(cardID: 1)

        #expect(throws: unexpected) {
            try Scheduler.standard.standing(after: [placement(interval: .seconds(-1), due: start, at: start)])
        }
        #expect(throws: unexpected) {
            try Scheduler.standard.standing(after: [placement(interval: .days(10), ease: nil, due: start, at: start)])
        }
        #expect(throws: unexpected) {
            try Scheduler.standard.standing(after: [review(.easy, at: start, keeping: .hours(1))])
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
