import FichaCore
import Foundation
import Testing

/// Tests on how a rating moves a way through its learning and relearning
/// steps, as Anki moves a card (#404), through the standing the scheduler
/// works out from the way's review log. The standard learning steps are 1
/// hour and 4 hours, and its relearning step 1 hour.
struct SchedulerStepsTests {
    @Test("a way without entries is new")
    func aWayWithoutEntriesIsNew() throws {
        #expect(try Scheduler.standard.standing(after: []) == .new)
    }

    @Test("a new way rated again or hard waits on the first learning step, hard halfway to the second")
    func againAndHardOnANewWay() throws {
        let again = try Scheduler.standard.standing(after: answering(.again, at: start, after: []))
        let hard = try Scheduler.standard.standing(after: answering(.hard, at: start, after: []))

        #expect(again.stage == .learning(step: 0))
        #expect(again.interval == hours(1))
        #expect(again.due == start + hour)
        // Halfway between 1 hour and 4 hours.
        #expect(hard.stage == .learning(step: 0))
        #expect(hard.interval == minutes(150))
        #expect(hard.due == start + 150 * minute)
    }

    @Test("a new way rated good goes to the second learning step, and easy graduates it")
    func goodAndEasyOnANewWay() throws {
        let good = try Scheduler.standard.standing(after: answering(.good, at: start, after: []))
        let easy = try Scheduler.standard.standing(after: answering(.easy, at: start, after: []))

        #expect(good.stage == .learning(step: 1))
        #expect(good.interval == hours(4))
        #expect(easy.stage == .graduated)
        #expect(try #require(easy.graduatedDays) >= 1)
    }

    @Test(
        "on the first learning step, again repeats it, hard waits halfway to the second, good moves on, easy graduates")
    func eachRatingOnTheFirstLearningStep() throws {
        let onFirstStep = try answering(.again, at: start, after: [])
        let later = start + hour

        let standing = try [Rating.again, .hard, .good, .easy].map { rating in
            try Scheduler.standard.standing(after: answering(rating, at: later, after: onFirstStep))
        }

        #expect(standing.map(\.stage) == [.learning(step: 0), .learning(step: 0), .learning(step: 1), .graduated])
        #expect(standing.prefix(3).map(\.interval) == [hours(1), minutes(150), hours(4)])
        #expect(standing.map(\.due).prefix(3) == [later + hour, later + 150 * minute, later + 4 * hour])
    }

    @Test("on the last learning step, again goes back to the first, hard repeats it, and good and easy graduate")
    func eachRatingOnTheLastLearningStep() throws {
        let onLastStep = try answering(.good, at: start, after: [])
        let later = start + 4 * hour

        let standing = try [Rating.again, .hard, .good, .easy].map { rating in
            try Scheduler.standard.standing(after: answering(rating, at: later, after: onLastStep))
        }

        #expect(standing.map(\.stage) == [.learning(step: 0), .learning(step: 1), .graduated, .graduated])
        #expect(standing.prefix(2).map(\.interval) == [hours(1), hours(4)])
        // FSRS's good and easy for a card rated good, then good again the
        // same day, are days apart once rounded.
        let good = try #require(standing[2].graduatedDays)
        let easy = try #require(standing[3].graduatedDays)
        #expect(good >= 1)
        #expect(easy > good)
    }

    @Test("again on a graduated way is a lapse, to the relearning step; hard, good and easy keep it graduated")
    func eachRatingOfAGraduatedWay() throws {
        let graduated = [placement(interval: days(10), due: start, at: start - 10 * day)]

        let standing = try [Rating.again, .hard, .good, .easy].map { rating in
            try Scheduler.standard.standing(after: answering(rating, at: start, after: graduated))
        }

        #expect(standing.map(\.stage) == [.relearning(step: 0), .graduated, .graduated, .graduated])
        #expect(standing[0].interval == hours(1))
        #expect(standing[0].due == start + hour)
        let passing = try standing.dropFirst().map { try #require($0.graduatedDays) }
        #expect(passing == passing.sorted())
        #expect(Set(passing).count == 3)
    }

    @Test(
        "on the one relearning step, again repeats it, hard waits 1.5 times as long, and good and easy graduate the way"
    )
    func eachRatingOnTheOneRelearningStep() throws {
        let graduated = [placement(interval: days(10), due: start, at: start - 10 * day)]
        let lapsed = try answering(.again, at: start, after: graduated)
        let later = start + hour

        let standing = try [Rating.again, .hard, .good, .easy].map { rating in
            try Scheduler.standard.standing(after: answering(rating, at: later, after: lapsed))
        }

        #expect(standing.map(\.stage) == [.relearning(step: 0), .relearning(step: 0), .graduated, .graduated])
        #expect(standing.prefix(2).map(\.interval) == [hours(1), minutes(90)])
        #expect(try #require(standing[3].graduatedDays) > #require(standing[2].graduatedDays))
    }

    @Test("with two relearning steps, hard on the first waits halfway to the second, and good moves to the second")
    func twoRelearningSteps() throws {
        let scheduler = try scheduler(relearningSteps: [hours(1), hours(4)])
        let graduated = [placement(interval: days(10), due: start, at: start - 10 * day)]
        let lapsed = try answering(.again, at: start, after: graduated, on: scheduler)
        let later = start + hour

        let hard = try scheduler.standing(after: answering(.hard, at: later, after: lapsed, on: scheduler))
        let good = try scheduler.standing(after: answering(.good, at: later, after: lapsed, on: scheduler))

        #expect(hard.stage == .relearning(step: 0))
        #expect(hard.interval == minutes(150))
        #expect(good.stage == .relearning(step: 1))
        #expect(good.interval == hours(4))
    }

    @Test("with one learning step, hard on it waits 1.5 times as long, and good graduates a new way")
    func oneLearningStep() throws {
        let scheduler = try scheduler(learningSteps: [hours(2)])

        let hard = try scheduler.standing(after: answering(.hard, at: start, after: [], on: scheduler))
        let good = try scheduler.standing(after: answering(.good, at: start, after: [], on: scheduler))

        #expect(hard.stage == .learning(step: 0))
        #expect(hard.interval == hours(3))
        #expect(good.stage == .graduated)
    }

    @Test("with no learning steps, a new way's first rating graduates it, whatever the rating")
    func noLearningSteps() throws {
        let scheduler = try scheduler(learningSteps: [])

        let standing = try [Rating.again, .hard, .good, .easy].map { rating in
            try scheduler.standing(after: answering(rating, at: start, after: [], on: scheduler))
        }

        #expect(standing.allSatisfy { $0.stage == .graduated })
    }

    @Test("with no relearning steps, a lapse goes straight to FSRS's interval after it, a day at least")
    func noRelearningSteps() throws {
        let scheduler = try scheduler(relearningSteps: [])
        let graduated = [placement(interval: days(10), due: start, at: start - 10 * day)]

        let lapsed = try scheduler.standing(after: answering(.again, at: start, after: graduated, on: scheduler))

        #expect(lapsed.stage == .graduated)
        #expect(try #require(lapsed.graduatedDays) >= 1)
        #expect(try #require(lapsed.graduatedDays) < 10)
    }

    @Test(
        "a way on a learning step the steps no longer have stays on it, due as it was, and counts as on the last step")
    func aStepThatNoLongerExists() throws {
        let threeSteps = try scheduler(learningSteps: [hours(1), hours(4), hours(8)])
        let onThirdStep = try answering(
            .good, at: start + 4 * hour, after: answering(.good, at: start, after: [], on: threeSteps), on: threeSteps)
        let later = start + 12 * hour

        let standing = try Scheduler.standard.standing(after: onThirdStep)
        let rated = try [Rating.again, .hard, .good].map { rating in
            try Scheduler.standard.standing(after: answering(rating, at: later, after: onThirdStep))
        }

        #expect(standing.stage == .learning(step: 2))
        #expect(standing.due == start + 12 * hour)
        // The standard steps' last is the second, of 4 hours.
        #expect(rated.map(\.stage) == [.learning(step: 0), .learning(step: 1), .graduated])
        #expect(rated.prefix(2).map(\.interval) == [hours(1), hours(4)])
    }
}
