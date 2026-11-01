internal import FichaFSRS
import Foundation

/// The settings that decide how long a card's ways wait, as Anki spaces cards
/// with FSRS (ADR 0025), and the scheduler that works out where each way stands
/// from its review log with them (#404). FSRS's arithmetic is fsrs-rs's
/// (ADR 0026); Anki's rules around it, the steps, whole days within their
/// bounds, the buttons a day apart and the fuzz, are worked out here, as Anki
/// keeps them in its own code.
public struct Scheduler: Sendable, Equatable {
    /// The intervals a new way goes through before it graduates, from the
    /// first: each from 10 minutes to less than a day, each longer than the
    /// one before, or none, so that a new way's first rating graduates it.
    public let learningSteps: [Duration]
    /// The intervals a graduated way goes through after a lapse, before it
    /// graduates again, as the learning steps are: none sends a lapse
    /// straight to FSRS's interval.
    public let relearningSteps: [Duration]
    /// How likely Lucas wants to be to remember a way when it comes due, from
    /// 0.70 to 0.99, as Anki allows: FSRS's intervals aim at it.
    public let desiredRetention: Double
    /// The longest interval a graduated way can get, in days, from 1 to
    /// 36,500, as Anki allows.
    public let longestIntervalInDays: Int
    /// FSRS-6's 21 parameters, in fsrs-rs's order, or none for FSRS-6's
    /// defaults, as Anki keeps them until Optimize fits them to the user's
    /// reviews.
    public let parameters: [Float]

    /// The settings Ficha starts with: learning steps of 1 hour and 4 hours,
    /// a relearning step of 1 hour, a desired retention of 90%, a longest
    /// interval of 36,500 days and FSRS-6's default parameters.
    public static let standard = Scheduler(
        checkedLearningSteps: [.hours(1), .hours(4)], relearningSteps: [.hours(1)], desiredRetention: 0.9,
        longestIntervalInDays: 36_500, parameters: [])

    /// These settings, which are known to be valid.
    private init(
        checkedLearningSteps learningSteps: [Duration], relearningSteps: [Duration], desiredRetention: Double,
        longestIntervalInDays: Int, parameters: [Float]
    ) {
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.desiredRetention = desiredRetention
        self.longestIntervalInDays = longestIntervalInDays
        self.parameters = parameters
    }

    /// These settings, or nil unless each is valid, as each property says:
    /// steps from 10 minutes to less than a day, each longer than the one
    /// before, or none; a desired retention from 0.70 to 0.99; a longest
    /// interval from 1 to 36,500 days; and 21 finite parameters, or none.
    public init?(
        learningSteps: [Duration], relearningSteps: [Duration], desiredRetention: Double, longestIntervalInDays: Int,
        parameters: [Float]
    ) {
        guard Self.areValidSteps(learningSteps), Self.areValidSteps(relearningSteps),
            (0.70...0.99).contains(desiredRetention), (1...36_500).contains(longestIntervalInDays),
            parameters.isEmpty || (parameters.count == 21 && parameters.allSatisfy(\.isFinite))
        else {
            return nil
        }
        self.init(
            checkedLearningSteps: learningSteps, relearningSteps: relearningSteps, desiredRetention: desiredRetention,
            longestIntervalInDays: longestIntervalInDays, parameters: parameters)
    }

    /// Whether these are valid learning or relearning steps: each from 10
    /// minutes to less than a day, each longer than the one before, or none.
    private static func areValidSteps(_ steps: [Duration]) -> Bool {
        steps.allSatisfy { (Duration.minutes(10)..<Duration.days(1)).contains($0) }
            && zip(steps, steps.dropFirst()).allSatisfy(<)
    }
}

extension Scheduler {
    /// Where a card's way stands after its entries in the review log, which
    /// can come in any order and from two devices (ADR 0017): they're
    /// replayed in the order `ReviewLogEntry.precedes(_:)` gives, so every
    /// device works out the same standing. Without entries it's new.
    ///
    /// Each review moves the way as
    /// `stageAndInterval(rating:from:lastInterval:intervals:)` says, and
    /// updates its memory with fsrs-rs, after the days since its last review,
    /// rounded to the nearest whole day. A first view, from before the
    /// scheduler, counts as a review rated again.
    ///
    /// The way waits the interval its last entry set, from when it was
    /// answered: so a change to these settings leaves its due time alone
    /// until its next review. A review keeps the interval its device's
    /// preview gave it only when it answered the entry replayed just before
    /// it: the entry it names, or, naming none, as a new way's first review
    /// does, none, as the way's first entry. It leaves the way where the
    /// rules under these settings put it when they give that same interval,
    /// and otherwise where its interval says it went, as the settings were
    /// when it was recorded: graduated, for whole days, and for any other
    /// interval, on the step its rating moves the way onto, which may be a
    /// step these settings no longer have. A review that kept none, or
    /// answered another entry, or one the log doesn't hold, as when its
    /// device didn't know of another device's entry, gets the interval these
    /// settings work out, with the same fuzz on every device, so that a good
    /// rated on one device never erases an again rated on another.
    ///
    /// A placement an import gave the way before any review starts it: on
    /// the first learning step for an interval under a day, and graduated
    /// for one of a day or more, its memory started from that interval and
    /// Anki's ease. A placement after reviews keeps their memory, and gives
    /// the way the interval Anki had for it: graduated for a day or more,
    /// and in its steps for less. Either way, the way is due at the
    /// placement's due time.
    ///
    /// Throws when fsrs-rs fails, or when an entry can't be followed: a
    /// placement without an interval, or without an ease for a graduated
    /// way, or a review that kept an interval its rating can't set.
    public func standing(after entries: [ReviewLogEntry]) throws(SchedulingError) -> WayStanding {
        try WayReplay(of: entries, with: self).standing
    }

    /// The interval each rating would set for a review of `cardWay`, whose
    /// review log entries are `entries`, in any order, at `time`: the
    /// interval a review rated so at that time keeps, as `standing(after:)`
    /// works it out.
    public func preview(of cardWay: CardWay, after entries: [ReviewLogEntry], at time: Date) throws(SchedulingError)
        -> IntervalPreview
    {
        let replay = try WayReplay(of: entries, with: self)
        let intervals = try replay.graduatedIntervals(ofReviewOf: cardWay, at: time)
        let interval = { (rating: Rating) in
            stageAndInterval(rating: rating, from: replay.stage, lastInterval: replay.interval, intervals: intervals)
                .interval
        }
        return IntervalPreview(
            again: interval(.again), hard: interval(.hard), good: interval(.good), easy: interval(.easy))
    }

    /// How likely Lucas is to remember a way with this standing at `time`,
    /// from 0 to 1, as FSRS estimates it from its memory and the time since
    /// its last review, or nil while FSRS has no memory of it.
    public func retrievability(of standing: WayStanding, at time: Date) throws(SchedulingError) -> Float? {
        guard let memory = standing.memory else {
            return nil
        }
        let days = max(0, time.days(since: memory.lastReview))
        let state = MemoryState(stability: memory.stability, difficulty: memory.difficulty)
        return try callingFSRS { () throws(FSRSError) in try fsrs().retrievability(of: state, daysElapsed: Float(days))
        }
    }

    /// FSRS-6 with these settings' parameters, or its defaults when they have
    /// none.
    func fsrs() throws(FSRSError) -> FSRS {
        try FSRS(parameters: parameters.isEmpty ? FSRS.defaultParameters() : parameters)
    }
}

/// The interval each rating would set for a review of a way.
public struct IntervalPreview: Sendable, Equatable {
    public let again: Duration
    public let hard: Duration
    public let good: Duration
    public let easy: Duration

    public init(again: Duration, hard: Duration, good: Duration, easy: Duration) {
        self.again = again
        self.hard = hard
        self.good = good
        self.easy = easy
    }

    /// The interval `rating` would set.
    public subscript(rating: Rating) -> Duration {
        switch rating {
        case .again: again
        case .hard: hard
        case .good: good
        case .easy: easy
        }
    }
}

/// Why the scheduler couldn't work out where a way stands.
public enum SchedulingError: Error, Equatable, CustomStringConvertible {
    /// The review log of the card with this id has an entry the scheduler
    /// can't follow: a placement without an interval, or without an ease for
    /// a graduated way, or a review that kept an interval its rating can't
    /// set.
    case unexpectedReviewLog(cardID: Int64)
    /// fsrs-rs couldn't work out a memory, an interval or a retrievability,
    /// as this says.
    case fsrsFailed(String)

    public var description: String {
        switch self {
        case .unexpectedReviewLog(let cardID):
            """
            Card \(cardID)'s review log has an entry the scheduler can't follow: a placement without an interval, \
            or without an ease for a graduated card, or a review that kept an interval its rating can't set. \
            Check what wrote it: the import, or the device that recorded the review.
            """
        case .fsrsFailed(let description):
            description
        }
    }
}

/// Runs `work`, which calls fsrs-rs, and throws its error as the scheduler's.
func callingFSRS<Value>(_ work: () throws(FSRSError) -> Value) throws(SchedulingError) -> Value {
    do {
        return try work()
    } catch {
        throw .fsrsFailed(error.description)
    }
}
