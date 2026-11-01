import FichaCore
import Foundation
import Testing

/// Tests on the memory and intervals the scheduler gives a way (#404): FSRS's,
/// as fsrs-rs works them out, in whole days within Anki's bounds and fuzz.
/// Some keep fsrs-rs's own expected values, at the version Ficha pins, so an
/// upgrade that changes them fails here (ADR 0026): each cites where fsrs-rs
/// states them, in
/// https://github.com/open-spaced-repetition/fsrs-rs/blob/v6.6.2/src/inference.rs.
struct SchedulerIntervalsTests {
    @Test("a way's memory after again, good the same day, and good 1, 3, 8 and 21 days apart is fsrs-rs's")
    func memoryAfterKnownRatings() throws {
        var log = try answering(.again, at: start, after: [])
        var time = start + hour
        log = try answering(.good, at: time, after: log)
        for days in [1.0, 3, 8, 21] {
            time += days * day
            log = try answering(.good, at: time, after: log)
        }

        let memory = try #require(try Scheduler.standard.standing(after: log).memory)

        // `test_memory_state`, for the default parameters: ratings 1, 3, 3,
        // 3, 3 and 3, 0, 0, 1, 3, 8 and 21 days apart, within its tolerance.
        #expect(abs(memory.stability - 53.62691) < 1e-4)
        #expect(abs(memory.difficulty - 6.3574867) < 1e-4)
        #expect(memory.lastReview == time)
    }

    @Test("a new way's first good gives it fsrs-rs's memory for a new card rated good")
    func memoryAfterANewWaysGood() throws {
        let memory = try #require(try Scheduler.standard.standing(after: answering(.good, at: start, after: [])).memory)

        // `FSRS::next_states`'s example, for a new card with the default
        // parameters.
        #expect(memory.stability == 2.3065)
        #expect(memory.difficulty == 2.118104)
    }

    @Test(
        "with no learning steps, a new way's intervals are fsrs-rs's for the default parameters at 90%, in whole days")
    func newWaysIntervalsWithoutSteps() throws {
        let scheduler = try scheduler(learningSteps: [])

        let preview = try scheduler.preview(of: wayOne, after: [], at: start)

        // `FSRS::next_states`'s example: 0.212, 1.2931, 2.3065 and 8.2956
        // days. Again's rounds to none, and a graduated interval is a day at
        // least; easy's falls in Anki's fuzz around 8 days, from 6 to 10.
        #expect(preview.days.prefix(3) == [1, 1, 2])
        #expect((6...10).contains(preview.days[3]))
    }

    @Test("a placement starts a graduated way from Anki's interval and ease, as fsrs-rs starts a card from SM-2's")
    func aPlacementStartsAGraduatedWay() throws {
        let placed = placement(interval: days(10), ease: 2.5, due: start, at: start - 3 * day)

        let standing = try Scheduler.standard.standing(after: [placed])

        #expect(standing.stage == .graduated)
        #expect(standing.interval == days(10))
        #expect(standing.due == start)
        let memory = try #require(standing.memory)
        // `test_memory_from_sm2`'s first case, within its tolerance.
        #expect(abs(memory.stability - 10) < 1e-4)
        #expect(abs(memory.difficulty - 6.9140563) < 1e-4)
        // Reviewed its interval before it was due, as Anki reckons it.
        #expect(memory.lastReview == start - 10 * day)
    }

    @Test("a way's retrievability is 100% at its last review and 90% once its stability's days have passed")
    func retrievability() throws {
        let standing = try Scheduler.standard.standing(after: [
            placement(interval: days(10), due: start, at: start - 3 * day)
        ])
        let memory = try #require(standing.memory)

        let atLastReview = try #require(try Scheduler.standard.retrievability(of: standing, at: memory.lastReview))
        let afterStability = try #require(
            try Scheduler.standard.retrievability(
                of: standing, at: memory.lastReview + TimeInterval(memory.stability) * day))

        #expect(atLastReview == 1)
        #expect(abs(afterStability - 0.9) < 1e-5)
        #expect(try Scheduler.standard.retrievability(of: .new, at: start) == nil)
    }

    @Test("a graduated way's hard, good and easy stay a day apart, even when FSRS's intervals all round to none")
    func hardGoodAndEasyADayApart() throws {
        let scheduler = try scheduler(learningSteps: [], desiredRetention: 0.99)
        let graduated = try answering(.hard, at: start, after: [], on: scheduler)

        let preview = try scheduler.preview(of: wayOne, after: graduated, at: start + day)

        // At 99%, a day after a new card's hard, FSRS's hard, good and easy
        // are 0.22, 0.31 and 0.51 days.
        #expect(preview.days.dropFirst() == [1, 2, 3])
    }

    @Test("the longest interval caps a graduated way's hard, good and easy")
    func theLongestIntervalCaps() throws {
        let scheduler = try scheduler(longestIntervalInDays: 10)
        let graduated = [placement(interval: days(30), due: start, at: start - 30 * day)]

        let preview = try scheduler.preview(of: wayOne, after: graduated, at: start)

        // FSRS gives a card 30 days after its last review weeks more.
        #expect(preview.days[1] <= 10)
        #expect(preview.days.suffix(2) == [10, 10])
    }

    @Test(
        "a graduated interval falls anywhere in Anki's fuzz around FSRS's, and the same card's always in the same place"
    )
    func fuzzWithinAnkisRange() throws {
        let scheduler = try scheduler(learningSteps: [])
        let cards = (1...300).map { CardWay(cardID: Int64($0), way: .frontFirst) }

        let easy = try cards.map { try scheduler.preview(of: $0, after: [], at: start).days[3] }
        let again = try cards.map { try scheduler.preview(of: $0, after: [], at: start + day).days[3] }

        // A new card's easy is 8.2956 days, which Anki rounds to 8, and fuzzes
        // by a day, 15% of 4.5 days and 10% of 1 day each way: from 6 to 10.
        #expect(Set(easy) == Set(6...10))
        #expect(again == easy)
    }

    @Test("the interval a review keeps is the one its preview gave, and one that kept none gets the same")
    func thePreviewIsWhatAReviewKeeps() throws {
        let graduated = [placement(interval: days(10), due: start, at: start - 10 * day)]
        let preview = try Scheduler.standard.preview(of: wayOne, after: graduated, at: start)

        for rating in Rating.allRatings {
            let kept = try Scheduler.standard.standing(after: answering(rating, at: start, after: graduated))
            let workedOut = try Scheduler.standard.standing(after: graduated + [review(rating, at: start)])

            #expect(kept.interval == preview[rating])
            #expect(kept.due == start.adding(preview[rating]))
            #expect(workedOut == kept)
        }
    }

    @Test("the days since a way's last review are rounded to the nearest whole day")
    func elapsedDaysAreRounded() throws {
        let reviewed = try answering(.good, at: start, after: [])
        let memory = { (time: Date) in
            try Scheduler.standard.standing(after: answering(.good, at: time, after: reviewed)).memory?.stability
        }

        #expect(try memory(start + 11 * hour) == memory(start + 5 * minute))
        #expect(try memory(start + 13 * hour) == memory(start + day))
        #expect(try memory(start + day + 11 * hour) == memory(start + day))
        #expect(try memory(start + day + 13 * hour) == memory(start + 2 * day))
        #expect(try memory(start + day) != memory(start + 2 * day))
    }

    @Test("a late review counts the time the card really waited, and lengthens the interval more than one on time")
    func aLateReview() throws {
        let graduated = [placement(interval: days(10), due: start, at: start - 10 * day)]

        let onTime = try Scheduler.standard.standing(after: answering(.good, at: start, after: graduated))
        let late = try Scheduler.standard.standing(after: answering(.good, at: start + 20 * day, after: graduated))

        let onTimeStability = try #require(onTime.memory?.stability)
        let lateStability = try #require(late.memory?.stability)
        #expect(lateStability > onTimeStability)
        #expect(try #require(late.graduatedDays) > #require(onTime.graduatedDays))
    }

    @Test("a review ahead counts, and lengthens the interval less than one on time")
    func aReviewAhead() throws {
        let graduated = [placement(interval: days(10), due: start, at: start - 10 * day)]
        let placedStability = try #require(try Scheduler.standard.standing(after: graduated).memory?.stability)

        let onTime = try Scheduler.standard.standing(after: answering(.good, at: start, after: graduated))
        let ahead = try Scheduler.standard.standing(after: answering(.good, at: start - 7 * day, after: graduated))

        let onTimeStability = try #require(onTime.memory?.stability)
        let aheadStability = try #require(ahead.memory?.stability)
        #expect(aheadStability > placedStability)
        #expect(aheadStability < onTimeStability)
        #expect(try #require(ahead.graduatedDays) < #require(onTime.graduatedDays))
    }
}
