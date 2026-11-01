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

    /// The intervals a learning or relearning step can have: from 10 minutes
    /// to less than a day.
    public static let stepIntervals: Range<Duration> = Duration.minutes(10)..<Duration.days(1)
    /// The desired retentions the scheduler takes, as Anki allows them.
    public static let desiredRetentions: ClosedRange<Double> = 0.70...0.99
    /// The longest intervals the scheduler takes, in days, as Anki allows
    /// them.
    public static let longestIntervalsInDays: ClosedRange<Int> = 1...36_500

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
    /// steps within `stepIntervals`, from 10 minutes to less than a day, each
    /// longer than the one before, or none; a desired retention within
    /// `desiredRetentions`, from 0.70 to 0.99; a longest interval within
    /// `longestIntervalsInDays`, from 1 to 36,500 days; and 21 finite
    /// parameters, or none.
    public init?(
        learningSteps: [Duration], relearningSteps: [Duration], desiredRetention: Double, longestIntervalInDays: Int,
        parameters: [Float]
    ) {
        guard Self.areValidSteps(learningSteps), Self.areValidSteps(relearningSteps),
            Self.desiredRetentions.contains(desiredRetention),
            Self.longestIntervalsInDays.contains(longestIntervalInDays),
            parameters.isEmpty || (parameters.count == 21 && parameters.allSatisfy(\.isFinite))
        else {
            return nil
        }
        self.init(
            checkedLearningSteps: learningSteps, relearningSteps: relearningSteps, desiredRetention: desiredRetention,
            longestIntervalInDays: longestIntervalInDays, parameters: parameters)
    }

    /// Whether these are valid learning or relearning steps: each within
    /// `stepIntervals`, each longer than the one before, or none.
    private static func areValidSteps(_ steps: [Duration]) -> Bool {
        steps.allSatisfy(stepIntervals.contains) && zip(steps, steps.dropFirst()).allSatisfy(<)
    }

    /// These settings, but for each that `changed` changed from `old`, which
    /// it gives: the user changed those, and these may hold another device's
    /// later change to the others, since each syncs on its own (ADR 0017).
    /// Each is valid on its own, so the settings they make together are too.
    public func taking(_ changed: Scheduler, changedFrom old: Scheduler) -> Scheduler {
        /// `changed`'s setting at `keyPath` when it differs from `old`'s,
        /// and these settings' otherwise.
        func taken<Value: Equatable>(_ keyPath: KeyPath<Scheduler, Value>) -> Value {
            changed[keyPath: keyPath] != old[keyPath: keyPath] ? changed[keyPath: keyPath] : self[keyPath: keyPath]
        }
        return Scheduler(
            checkedLearningSteps: taken(\.learningSteps), relearningSteps: taken(\.relearningSteps),
            desiredRetention: taken(\.desiredRetention), longestIntervalInDays: taken(\.longestIntervalInDays),
            parameters: taken(\.parameters))
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
    /// rounded to the nearest whole day.
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
    /// placement with a negative interval, or without an ease for a
    /// graduated way, or a review that kept an interval its rating can't set.
    public func standing(after entries: [ReviewLogEntry]) throws(SchedulingError) -> WayStanding {
        try WayReplay(of: entries, with: self).standing
    }

    /// Where each of `ways` stands, in the order given, after the review
    /// log's entries, in any order: each way after its own.
    func standings(of ways: [CardWay], after log: [ReviewLogEntry]) throws(SchedulingError)
        -> [(way: CardWay, standing: WayStanding)]
    {
        let entries = Dictionary(grouping: log, by: \.cardWay)
        return try ways.map { way throws(SchedulingError) in (way, try standing(after: entries[way] ?? [])) }
    }

    /// How many of the ways of `cards` are due at `now`, and how many of the
    /// cards are learned: their front-first way graduated with an interval of
    /// 21 days or more, so that switching Both ways on changes nothing there.
    public func counts(of cards: CardsInReviews, at now: Date) throws(SchedulingError) -> (due: Int, learned: Int) {
        let standings = try cards.standings(with: self)
        let frontFirst = standings.filter { cardWay, _ in cardWay.way == .frontFirst }.map(\.standing)
        return (standings.count { $0.standing.isDue(at: now) }, frontFirst.count(where: \.isLearned))
    }

    /// The reviews among one way's `entries`, in any order, that were lapses:
    /// agains of the way while it was graduated, as Anki counts a card's
    /// lapses, in the order they're replayed. A new way's agains, in its
    /// learning steps, and a relearning way's are none.
    public func lapses(after entries: [ReviewLogEntry]) throws(SchedulingError) -> [ReviewLogEntry] {
        try WayReplay(of: entries, with: self).lapses
    }

    /// One way's `entries`, in any order, in the order they're replayed, as
    /// the review log keeps them from now on: each review that kept no
    /// interval keeping the one the replay gives it, and answering the entry
    /// replayed just before it, or none as the way's first entry, so that the
    /// replay keeps that interval, and a later change to these settings
    /// leaves the way's due time alone (#404). The other entries stay as they
    /// are. The migration that brought the scheduler gives every review it
    /// carried over its interval so, and sync a review that comes without
    /// one from an older version of Ficha.
    public func keepingIntervals(of entries: [ReviewLogEntry]) throws(SchedulingError) -> [ReviewLogEntry] {
        try WayReplay(of: entries, with: self).keepingIntervals
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
    /// can't follow: a placement with a negative interval, or without an
    /// ease for a graduated way, or a review that kept an interval its rating
    /// can't set.
    case unexpectedReviewLog(cardID: Int64)
    /// fsrs-rs couldn't work out a memory, an interval or a retrievability,
    /// as this says.
    case fsrsFailed(String)

    public var description: String {
        switch self {
        case .unexpectedReviewLog(let cardID):
            """
            Card \(cardID)'s review log has an entry the scheduler can't follow: a placement with a negative \
            interval, or without an ease for a graduated card, or a review that kept an interval its rating can't set. \
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
