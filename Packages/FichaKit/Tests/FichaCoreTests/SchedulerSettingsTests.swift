import FichaCore
import Foundation
import Testing

/// Tests on which settings make a scheduler (#404), Anki's limits and Ficha's
/// steps of less than a day, and on the changes Settings' Scheduling tab makes
/// to them within those.
struct SchedulerSettingsTests {
    @Test("steps from 10 minutes to less than a day, each longer than the one before, or none, are valid")
    func validSteps() {
        let valid: [[Duration]] = [
            [], [.minutes(10)], [.hours(1), .hours(4)], [.minutes(10), .hours(23), .days(1) - .seconds(1)],
        ]
        for steps in valid {
            #expect(stepsAreValid(steps))
        }
    }

    @Test("a step under 10 minutes, of a day or more, or no longer than the one before isn't valid")
    func invalidSteps() {
        let invalid: [[Duration]] = [
            [.minutes(9)], [.days(1)], [.hours(4), .hours(1)], [.hours(1), .hours(1)], [.zero],
        ]
        for steps in invalid {
            #expect(!stepsAreValid(steps))
        }
    }

    @Test("a desired retention from 70% to 99% is valid, and none outside it")
    func desiredRetention() {
        let scheduler = { (retention: Double) in
            Scheduler(
                learningSteps: [], relearningSteps: [], desiredRetention: retention, longestIntervalInDays: 36_500,
                parameters: [])
        }

        #expect(scheduler(0.7) != nil)
        #expect(scheduler(0.99) != nil)
        #expect(scheduler(0.69) == nil)
        #expect(scheduler(1) == nil)
        #expect(scheduler(.nan) == nil)
    }

    @Test("a longest interval from 1 to 36,500 days is valid, and none outside it")
    func longestInterval() {
        let scheduler = { (days: Int) in
            Scheduler(
                learningSteps: [], relearningSteps: [], desiredRetention: 0.9, longestIntervalInDays: days,
                parameters: [])
        }

        #expect(scheduler(1) != nil)
        #expect(scheduler(36_500) != nil)
        #expect(scheduler(0) == nil)
        #expect(scheduler(36_501) == nil)
    }

    @Test("FSRS-6's 21 finite parameters are valid, or none, for its defaults, and no other number of them")
    func parameters() {
        let scheduler = { (parameters: [Float]) in
            Scheduler(
                learningSteps: [], relearningSteps: [], desiredRetention: 0.9, longestIntervalInDays: 36_500,
                parameters: parameters)
        }
        let twentyOne = [Float](repeating: 0.5, count: 21)

        #expect(scheduler([]) != nil)
        #expect(scheduler(twentyOne) != nil)
        #expect(scheduler(Array(twentyOne.dropLast())) == nil)
        #expect(scheduler(twentyOne + [0.5]) == nil)
        #expect(scheduler(Array(twentyOne.dropLast()) + [.infinity]) == nil)
    }

    @Test("a step offers the intervals that keep it longer than the step before it and shorter than the one after it")
    func aStepOffersTheIntervalsThatFit() throws {
        let settings = try scheduler(
            learningSteps: [.minutes(10), .hours(1), .hours(4)], relearningSteps: [.minutes(25)])

        #expect(settings.intervals(forStep: 0, of: .learning) == [10, 15, 20, 30, 45].map(Duration.minutes))
        #expect(
            settings.intervals(forStep: 1, of: .learning)
                == [15, 20, 30, 45].map(Duration.minutes) + [1, 2, 3].map(Duration.hours))
        #expect(settings.intervals(forStep: 2, of: .learning) == [2, 3, 4, 6, 8, 12].map(Duration.hours))
        // A step of its own, as another device or the CLI may set, stays
        // among them.
        #expect(
            settings.intervals(forStep: 0, of: .relearning)
                == [10, 15, 20, 25, 30, 45].map(Duration.minutes) + [1, 2, 3, 4, 6, 8, 12].map(Duration.hours))
        #expect(settings.intervals(forStep: 3, of: .learning).isEmpty)
        #expect(Scheduler.stepIntervalsOffered.allSatisfy(Scheduler.stepIntervals.contains))
    }

    @Test("Add Step adds the first interval offered after the last step, 1 hour to no steps, and none after 12 hours")
    func addStepAddsTheNextIntervalOffered() throws {
        let settings = try scheduler(
            learningSteps: [.minutes(10), .minutes(45)], relearningSteps: [.hours(12)])

        #expect(settings.addingStep(to: .learning)?.learningSteps == [.minutes(10), .minutes(45), .hours(1)])
        #expect(settings.addingStep(to: .relearning) == nil)
        #expect(try scheduler(relearningSteps: []).addingStep(to: .relearning)?.relearningSteps == [.hours(1)])
        #expect(try scheduler(learningSteps: []).addingStep(to: .learning)?.learningSteps == [.hours(1)])
    }

    // Settings' row may outlive its step for a moment once it's removed.
    @Test("a step changes or goes only while it's there, and a change that breaks the steps' order changes nothing")
    func aStepChangesOrGoesWhileItsThere() throws {
        let settings = try scheduler(learningSteps: [.minutes(10), .hours(1)])

        #expect(settings.changingStep(1, of: .learning, to: .hours(2))?.learningSteps == [.minutes(10), .hours(2)])
        #expect(settings.changingStep(1, of: .learning, to: .minutes(10)) == nil)
        #expect(settings.changingStep(2, of: .learning, to: .hours(2)) == nil)
        #expect(settings.removingStep(0, of: .learning)?.learningSteps == [.hours(1)])
        #expect(settings.removingStep(0, of: .relearning)?.relearningSteps == [])
        #expect(settings.removingStep(1, of: .relearning) == nil)
    }

    // Settings' stepper adds a hundredth at a time, which a Double holds
    // only roughly, and a number typed in its field may be any.
    @Test(
        "Settings keeps a desired retention to a whole percentage from 70% to 99%, and a longest interval from 1 to 36,500 days"
    )
    func settingsKeepsTheRetentionAndTheLongestIntervalWithinTheirBounds() {
        let settings = Scheduler.standard

        #expect(settings.changingDesiredRetention(to: 0.93 + 0.01)?.desiredRetention == 0.94)
        #expect(settings.changingDesiredRetention(to: 0.873)?.desiredRetention == 0.87)
        #expect(settings.changingDesiredRetention(to: 0.5)?.desiredRetention == 0.7)
        #expect(settings.changingDesiredRetention(to: 1)?.desiredRetention == 0.99)
        #expect(settings.changingDesiredRetention(to: .nan) == nil)
        #expect(settings.changingLongestInterval(toDays: 365)?.longestIntervalInDays == 365)
        #expect(settings.changingLongestInterval(toDays: 0)?.longestIntervalInDays == 1)
        #expect(settings.changingLongestInterval(toDays: 100_000)?.longestIntervalInDays == 36_500)
    }

    /// Whether `steps` are valid learning steps, and valid relearning steps
    /// too, since the same rules hold for both.
    private func stepsAreValid(_ steps: [Duration]) -> Bool {
        let asLearning = Scheduler(
            learningSteps: steps, relearningSteps: [], desiredRetention: 0.9, longestIntervalInDays: 36_500,
            parameters: [])
        let asRelearning = Scheduler(
            learningSteps: [], relearningSteps: steps, desiredRetention: 0.9, longestIntervalInDays: 36_500,
            parameters: [])
        return asLearning != nil && asRelearning != nil
    }
}
