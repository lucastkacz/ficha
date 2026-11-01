internal import FichaFSRS
import Foundation

/// A card's way's review log replayed, entry by entry, with a scheduler's
/// settings, as `Scheduler.standing(after:)` says: where the way is after
/// it, and what the next review needs, its memory, when it was last
/// reviewed, how many reviews it had and what names the card in the fuzz's
/// seed.
struct WayReplay {
    private let scheduler: Scheduler
    private let fsrs: FSRS
    /// The way's entries replayed so far, in the order they're replayed.
    private var entries: [ReviewLogEntry] = []
    /// Where the way is, or nil while it's new.
    private(set) var stage: WayStanding.Stage?
    /// The interval the way's last entry set.
    private(set) var interval = Duration.zero
    /// When the way is due.
    private var due = Date.distantPast
    /// The way's memory, as fsrs-rs works it out, and when it was last
    /// reviewed, from which the next review counts its days, or nil until
    /// it has one.
    private var memory: (state: MemoryState, lastReview: Date)?
    /// How many reviews the way had.
    private var reviews = 0
    /// The reviews that were lapses, agains of the way while it was
    /// graduated, in the order they're replayed.
    private(set) var lapses: [ReviewLogEntry] = []
    /// The interval each review left the way waiting, by its position in the
    /// replay.
    private var intervalsSet: [Int: Duration] = [:]

    /// `entries`, one way's, in any order, replayed with `scheduler`'s
    /// settings.
    init(of entries: [ReviewLogEntry], with scheduler: Scheduler) throws(SchedulingError) {
        self.scheduler = scheduler
        fsrs = try callingFSRS { () throws(FSRSError) in try scheduler.fsrs() }
        for entry in entries.sorted(by: { $0.precedes($1) }) {
            try replay(entry)
        }
    }

    /// Replays `entry`, one of the way's that comes after every entry
    /// replayed so far, in the order `ReviewLogEntry.precedes(_:)` gives, as
    /// an import replays the log it gives a way while it writes it; or throws
    /// when it doesn't come after them, as the same entry twice doesn't.
    mutating func replay(_ entry: ReviewLogEntry) throws(SchedulingError) {
        if let last = entries.last, !last.precedes(entry) {
            throw .unexpectedReviewLog(cardID: entry.cardID)
        }
        let position = entries.count
        entries.append(entry)
        switch entry.kind {
        case .placement(let placement):
            try place(placement, of: entry.cardID)
        case .review(let rating):
            try review(
                rating, of: entry, at: position,
                keeping: answersTheEntryBefore(entry, at: position) ? entry.interval : nil)
        }
    }

    /// The way's entries, in the order they're replayed, each review that
    /// kept no interval keeping the one it set, answering the entry before
    /// it, or none as the way's first, as `Scheduler.keepingIntervals(of:)`
    /// says.
    var keepingIntervals: [ReviewLogEntry] {
        entries.enumerated().map { position, entry in
            guard case .review = entry.kind, entry.interval == nil, let interval = intervalsSet[position] else {
                return entry
            }
            return entry.answering(position > 0 ? entries[position - 1].uuid : nil, keeping: interval)
        }
    }

    /// Where the way stands after its entries.
    var standing: WayStanding {
        guard let stage else {
            return .new
        }
        let memory = memory.map { memory in
            WayStanding.Memory(
                stability: memory.state.stability, difficulty: memory.state.difficulty,
                lastReview: memory.lastReview)
        }
        return .started(stage, interval: interval, due: due, memory: memory)
    }

    /// What the graduated intervals of the next review of `cardWay`, at
    /// `time`, come from, after the way's entries.
    func graduatedIntervals(ofReviewOf cardWay: CardWay, at time: Date) throws(SchedulingError)
        -> GraduatedIntervals
    {
        try graduatedIntervals(ofReviewAt: entries.count, of: cardWay, at: time)
    }

    /// What the graduated intervals of a review of `cardWay` at `position` in
    /// the replay, at `time`, come from: what fsrs-rs works out for each
    /// rating, from the way's memory, or as a new card's without one, after
    /// the days since its last review, rounded to the nearest whole day; and
    /// the fuzz factor, seeded by the way's first entry, or by the card's id
    /// for the way's first review, which has no entry before it.
    private func graduatedIntervals(ofReviewAt position: Int, of cardWay: CardWay, at time: Date)
        throws(SchedulingError) -> GraduatedIntervals
    {
        let days = memory.map { max(0, Int(time.days(since: $0.lastReview).rounded())) }
        let next = try callingFSRS { () throws(FSRSError) in
            try fsrs.nextStates(
                from: memory?.state, desiredRetention: Float(scheduler.desiredRetention), daysElapsed: days ?? 0)
        }
        let card: FuzzSeedCard =
            if position > 0, let first = entries[0].uuid { .firstEntry(first) } else { .cardID(cardWay.cardID) }
        return GraduatedIntervals(
            next: next, fuzzFactor: fuzzFactor(of: card, way: cardWay.way, reviewsBefore: reviews),
            longestIntervalInDays: scheduler.longestIntervalInDays)
    }

    /// Whether `review`, at `position` in the replay, answered the entry
    /// replayed just before it: the entry it names, or, naming none, as a
    /// review of a new way does, none, as the way's first entry.
    private func answersTheEntryBefore(_ review: ReviewLogEntry, at position: Int) -> Bool {
        guard let answered = review.answeredEntry else {
            return position == 0
        }
        return position > 0 && entries[position - 1].uuid == answered
    }

    /// Moves the way as `entry`, a review at `position` in the replay rated
    /// `rating`, does, keeping the interval `kept` when it keeps one.
    private mutating func review(_ rating: Rating, of entry: ReviewLogEntry, at position: Int, keeping kept: Duration?)
        throws(SchedulingError)
    {
        let intervals = try graduatedIntervals(ofReviewAt: position, of: entry.cardWay, at: entry.answeredAt)
        let workedOut = scheduler.stageAndInterval(
            rating: rating, from: stage, lastInterval: interval, intervals: intervals)
        let moved =
            try kept.map { kept throws(SchedulingError) in
                try stageAndInterval(rating: rating, keeping: kept, workedOut: workedOut, cardID: entry.cardID)
            } ?? workedOut
        if rating == .again, stage == .graduated {
            lapses.append(entry)
        }
        stage = moved.stage
        interval = moved.interval
        intervalsSet[position] = interval
        due = entry.answeredAt.adding(interval)
        memory = (intervals.next[rating].memoryState, entry.answeredAt)
        reviews += 1
    }

    /// Where a review rated `rating` that kept the interval `kept` left the
    /// way: where `workedOut`, the rules under the scheduler's settings, put
    /// it when they give that interval, and otherwise where the interval
    /// says it went, as the settings were when the review was recorded:
    /// graduated, for whole days, and for any other interval, on the step
    /// `Rating.move(from:)` moves it onto from its stage.
    private func stageAndInterval(rating: Rating, keeping kept: Duration, workedOut: StageAndInterval, cardID: Int64)
        throws(SchedulingError) -> StageAndInterval
    {
        guard kept > .zero else {
            throw .unexpectedReviewLog(cardID: cardID)
        }
        if kept == workedOut.interval {
            return workedOut
        }
        // A graduated interval is always whole days, and a step's wait is
        // whole days in one case alone: steps are under a day, and only hard
        // on a single step waits longer than a step, 1.5 times as long,
        // which is a day for a step of exactly 16 hours. So only that wait,
        // once the settings changed, reads as graduated.
        if kept.isWholeDays {
            return StageAndInterval(stage: .graduated, interval: kept)
        }
        guard case .onto(let step) = rating.move(from: stage) else {
            // Easy always graduates a way, and a graduated way's hard and
            // good keep it graduated: none waits a step's interval.
            throw .unexpectedReviewLog(cardID: cardID)
        }
        return StageAndInterval(stage: step, interval: kept)
    }

    /// Moves the way as `placement`, which an import gave the card with the
    /// id `cardID`, does.
    private mutating func place(_ placement: Placement, of cardID: Int64) throws(SchedulingError) {
        let placed = placement.interval
        guard placed >= .zero else {
            throw .unexpectedReviewLog(cardID: cardID)
        }
        switch (placed >= .days(1), reviews) {
        case (true, 0):
            guard let ease = placement.ease, ease.isFinite, ease > 0 else {
                throw .unexpectedReviewLog(cardID: cardID)
            }
            let state = try callingFSRS { () throws(FSRSError) in
                try fsrs.memoryState(
                    sm2Interval: Float(placed.inDays), ease: Float(ease), sm2Retention: ankiDefaultHistoricalRetention)
            }
            memory = (state, placement.due.adding(.zero - placed))
            stage = .graduated
        case (false, 0):
            memory = nil
            stage = .learning(step: 0)
        case (true, _):
            stage = .graduated
        case (false, _):
            if stage == .graduated {
                stage = .relearning(step: 0)
            }
        }
        interval = placed
        due = placement.due
    }
}

/// Anki's historical retention as it ships it, 90%: the retention it takes
/// SM-2 to have aimed at for a card it brings with an interval and an ease
/// but no reviews, from which fsrs-rs starts the card's memory
/// (`memory_state_from_sm2`). It's Anki's default deck options'
/// (`historical_retention: 0.9` in `rslib/src/deckconfig/mod.rs`), which
/// Anki passes to fsrs-rs in `rslib/src/scheduler/fsrs/memory_state.rs`;
/// its user can change it, which a placement doesn't carry yet.
private let ankiDefaultHistoricalRetention: Float = 0.9

// The order the scheduler replays a way's log in lives here, beside the
// replay, where the merge gate watches the scheduler.
extension ReviewLogEntry {
    /// Whether this entry comes before `other` as the scheduler replays a
    /// way's log, in an order worked out from the entries alone, so that
    /// every device replays a log that joins two devices' entries alike,
    /// whatever order they arrived in (ADR 0017): in the order they were
    /// answered, and, at the same moment, a placement before a review, and
    /// of two reviews, easy before good, good before hard and hard before
    /// again, so that again, rated at the same moment on another device, has
    /// the last word. Entries that tie on all of this go in the order of
    /// their IDs.
    public func precedes(_ other: ReviewLogEntry) -> Bool {
        (answeredAt, kind.orderAtTheSameMoment, uuid?.uuidString ?? "")
            < (other.answeredAt, other.kind.orderAtTheSameMoment, other.uuid?.uuidString ?? "")
    }
}

extension ReviewLogEntry.Kind {
    /// Where an entry of this kind goes among those answered at the same
    /// moment, as the scheduler replays them.
    fileprivate var orderAtTheSameMoment: Int {
        switch self {
        case .placement: 0
        case .review(let rating): 1 + rating.orderAtTheSameMoment
        }
    }
}
