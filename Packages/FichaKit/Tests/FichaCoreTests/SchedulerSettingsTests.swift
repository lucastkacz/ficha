import FichaCore
import Foundation
import Testing

/// Tests on which settings make a scheduler (#404): Anki's limits, and Ficha's
/// steps of less than a day.
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
