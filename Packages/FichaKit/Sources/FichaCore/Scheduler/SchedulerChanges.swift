import Foundation

// The changes Settings' Scheduling tab makes to the scheduler's settings
// (#404), each of which leaves them valid, or makes none: which intervals a
// step offers, the step Add Step adds, and a desired retention or a longest
// interval kept within what the scheduler takes.

extension Scheduler {
    /// The learning steps or the relearning steps.
    public enum StepList: Sendable, Hashable {
        case learning
        case relearning
    }

    /// The intervals Settings offers a step, within `stepIntervals`, shortest
    /// first: Ficha's own steps among them.
    public static let stepIntervalsOffered: [Duration] =
        [10, 15, 20, 30, 45].map(Duration.minutes) + [1, 2, 3, 4, 6, 8, 12].map(Duration.hours)

    /// The steps of `list`.
    public func steps(_ list: StepList) -> [Duration] {
        switch list {
        case .learning: learningSteps
        case .relearning: relearningSteps
        }
    }

    /// The intervals the step at `index` of `list` can be changed to,
    /// shortest first: those Settings offers that keep it longer than the
    /// step before it and shorter than the one after it, and its own. None
    /// when `list` has no such step.
    public func intervals(forStep index: Int, of list: StepList) -> [Duration] {
        let steps = steps(list)
        guard steps.indices.contains(index) else {
            return []
        }
        let fitting = Self.stepIntervalsOffered.filter { interval in
            (index == 0 || steps[index - 1] < interval) && (index == steps.count - 1 || interval < steps[index + 1])
        }
        return Set(fitting + [steps[index]]).sorted()
    }

    /// These settings with a step added at the end of `list`, as Add Step
    /// adds it: the first interval Settings offers after the last step's, or,
    /// when `list` has none, Ficha's first step of that list, 1 hour. Nil
    /// when none is offered after the last step.
    public func addingStep(to list: StepList) -> Scheduler? {
        let steps = steps(list)
        let added =
            if let last = steps.last {
                Self.stepIntervalsOffered.first { $0 > last }
            } else {
                Self.standard.steps(list).first
            }
        return added.flatMap { replacing(list, with: steps + [$0]) }
    }

    /// These settings with the step at `index` of `list` changed to
    /// `interval`, or nil when `list` has no such step, or `interval` doesn't
    /// keep the steps valid.
    public func changingStep(_ index: Int, of list: StepList, to interval: Duration) -> Scheduler? {
        var steps = steps(list)
        guard steps.indices.contains(index) else {
            return nil
        }
        steps[index] = interval
        return replacing(list, with: steps)
    }

    /// These settings without the step at `index` of `list`, or nil when
    /// `list` has no such step, as when Settings' row outlives the step it
    /// showed for a moment.
    public func removingStep(_ index: Int, of list: StepList) -> Scheduler? {
        var steps = steps(list)
        guard steps.indices.contains(index) else {
            return nil
        }
        steps.remove(at: index)
        return replacing(list, with: steps)
    }

    /// These settings with a desired retention of `retention` as a whole
    /// percentage, the nearest, within `desiredRetentions`, as Settings
    /// shows it and steps it a percent at a time: a Double holds a
    /// hundredth added to a percentage only roughly. Nil for a retention
    /// that isn't a number.
    public func changingDesiredRetention(to retention: Double) -> Scheduler? {
        let percentage = (retention * 100).rounded() / 100
        let bounds = Self.desiredRetentions
        return replacing(desiredRetention: min(max(percentage, bounds.lowerBound), bounds.upperBound))
    }

    /// These settings with a longest interval of `days`, within
    /// `longestIntervalsInDays`: a number typed in Settings past them stops
    /// at the nearest.
    public func changingLongestInterval(toDays days: Int) -> Scheduler? {
        let bounds = Self.longestIntervalsInDays
        return replacing(longestIntervalInDays: min(max(days, bounds.lowerBound), bounds.upperBound))
    }

    /// These settings with those given in place of theirs, or nil unless
    /// that leaves them valid.
    public func replacing(
        learningSteps: [Duration]? = nil, relearningSteps: [Duration]? = nil, desiredRetention: Double? = nil,
        longestIntervalInDays: Int? = nil, parameters: [Float]? = nil
    ) -> Scheduler? {
        Scheduler(
            learningSteps: learningSteps ?? self.learningSteps,
            relearningSteps: relearningSteps ?? self.relearningSteps,
            desiredRetention: desiredRetention ?? self.desiredRetention,
            longestIntervalInDays: longestIntervalInDays ?? self.longestIntervalInDays,
            parameters: parameters ?? self.parameters)
    }

    /// These settings with `steps` as the steps of `list`, or nil unless
    /// they're valid.
    private func replacing(_ list: StepList, with steps: [Duration]) -> Scheduler? {
        switch list {
        case .learning: replacing(learningSteps: steps)
        case .relearning: replacing(relearningSteps: steps)
        }
    }
}
