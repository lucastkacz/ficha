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
    /// The way's entries, in the order they're replayed.
    private let entries: [ReviewLogEntry]
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

    /// `entries`, one way's, in any order, replayed with `scheduler`'s
    /// settings.
    init(of entries: [ReviewLogEntry], with scheduler: Scheduler) throws(SchedulingError) {
        self.scheduler = scheduler
        fsrs = try callingFSRS { () throws(FSRSError) in try scheduler.fsrs() }
        self.entries = entries.sorted { $0.precedes($1) }
        let positions = Dictionary(
            self.entries.indices.compactMap { position in self.entries[position].uuid.map { ($0, position) } },
            uniquingKeysWith: { first, _ in first })
        for (position, entry) in self.entries.enumerated() {
            switch entry.kind {
            case .placement(let placement):
                try place(placement, of: entry.cardID)
            case .firstView:
                try review(.again, of: entry, at: position, keeping: nil)
            case .review(let rating):
                let answered = entry.answeredEntry.flatMap { positions[$0] } ?? position - 1
                try review(rating, of: entry, at: position, keeping: answered == position - 1 ? entry.interval : nil)
            }
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

    /// What fsrs-rs works out for each rating of a review of the way at
    /// `time`: from its memory, or as a new card's without one, after the
    /// days since its last review, rounded to the nearest whole day.
    func nextStates(at time: Date) throws(SchedulingError) -> NextStates {
        let days = memory.map { max(0, Int((time.timeIntervalSince($0.lastReview) / oneDay.timeInterval).rounded())) }
        return try callingFSRS { () throws(FSRSError) in
            try fsrs.nextStates(
                from: memory?.state, desiredRetention: Float(scheduler.desiredRetention), daysElapsed: days ?? 0)
        }
    }

    /// The fuzz factor of the next review of `cardWay`, after the way's
    /// entries.
    func fuzzFactor(ofReviewOf cardWay: CardWay) -> Double {
        FichaCore.fuzzFactor(
            of: card(before: entries.count, id: cardWay.cardID), way: cardWay.way, reviewsBefore: reviews)
    }

    /// What names the card with the id `cardID` in the fuzz's seed of a
    /// review at `position` in the replay: the way's first entry, unless the
    /// review is the first.
    private func card(before position: Int, id cardID: Int64) -> FuzzCard {
        guard position > 0, let first = entries[0].uuid else {
            return .cardID(cardID)
        }
        return .firstEntry(first)
    }

    /// Moves the way as `entry`, a review at `position` in the replay rated
    /// `rating`, does, keeping the interval `kept` when it keeps one.
    private mutating func review(_ rating: Rating, of entry: ReviewLogEntry, at position: Int, keeping kept: Duration?)
        throws(SchedulingError)
    {
        let next = try nextStates(at: entry.answeredAt)
        let factor = FichaCore.fuzzFactor(
            of: card(before: position, id: entry.cardID), way: entry.way, reviewsBefore: reviews)
        let worked = scheduler.outcome(of: rating, at: stage, after: interval, given: next, fuzzFactor: factor)
        let outcome =
            try kept.map { kept throws(SchedulingError) in
                try self.outcome(of: rating, keeping: kept, workedOut: worked, cardID: entry.cardID)
            } ?? worked
        stage = outcome.stage
        interval = outcome.interval
        due = entry.answeredAt.adding(interval)
        memory = (next[rating].memoryState, entry.answeredAt)
        reviews += 1
    }

    /// Where a review rated `rating` that kept the interval `kept` moved the
    /// way: where `workedOut`, the rules under the scheduler's settings, put
    /// it when they give that interval, and otherwise where the interval
    /// says it went, as the settings were when the review was recorded:
    /// graduated, for a day or more, and for less, on the step the rating
    /// moves it to from its stage.
    private func outcome(of rating: Rating, keeping kept: Duration, workedOut: Outcome, cardID: Int64)
        throws(SchedulingError) -> Outcome
    {
        guard kept > .zero else {
            throw .unexpectedReviewLog(cardID: cardID)
        }
        if kept == workedOut.interval {
            return workedOut
        }
        if kept >= oneDay {
            return Outcome(stage: .graduated, interval: kept)
        }
        let stage: WayStanding.Stage
        switch (self.stage, rating) {
        case (nil, .again), (.learning, .again), (nil, .hard):
            stage = .learning(step: 0)
        case (.learning(let step), .hard):
            stage = .learning(step: step)
        case (nil, .good):
            stage = .learning(step: 1)
        case (.learning(let step), .good):
            stage = .learning(step: step + 1)
        case (.graduated, .again), (.relearning, .again):
            stage = .relearning(step: 0)
        case (.relearning(let step), .hard):
            stage = .relearning(step: step)
        case (.relearning(let step), .good):
            stage = .relearning(step: step + 1)
        case (_, .easy), (.graduated, .hard), (.graduated, .good):
            // Easy always graduates a way, and a graduated way's hard and
            // good keep it graduated: none sets an interval under a day.
            throw .unexpectedReviewLog(cardID: cardID)
        }
        return Outcome(stage: stage, interval: kept)
    }

    /// Moves the way as `placement`, which an import gave the card with the
    /// id `cardID`, does.
    private mutating func place(_ placement: Placement, of cardID: Int64) throws(SchedulingError) {
        guard let placed = placement.interval, placed >= .zero else {
            throw .unexpectedReviewLog(cardID: cardID)
        }
        switch (placed >= oneDay, reviews) {
        case (true, 0):
            guard let ease = placement.ease, ease.isFinite, ease > 0 else {
                throw .unexpectedReviewLog(cardID: cardID)
            }
            let state = try callingFSRS { () throws(FSRSError) in
                try fsrs.memoryState(
                    sm2Interval: Float(placed.timeInterval / oneDay.timeInterval), ease: Float(ease),
                    sm2Retention: sm2Retention)
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

/// The retention SM-2 spaced a card Anki brings without reviews for, which
/// its memory starts from: Anki's historical retention, 90% unless its user
/// changed it, which Ficha doesn't read.
private let sm2Retention: Float = 0.9

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
    /// the last word. A first view counts as a review rated again. Entries
    /// that tie on all of this go in the order of their IDs.
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
        case .firstView: 1 + Rating.again.orderAtTheSameMoment
        }
    }
}
