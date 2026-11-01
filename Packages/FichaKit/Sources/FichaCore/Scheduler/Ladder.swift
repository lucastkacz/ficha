import Foundation

/// The ladder: the fixed waits a card climbs as Lucas remembers it (ADR 0002).
/// Its steps count from 0, the first step.
public struct Ladder: Sendable, Equatable {
    /// Each step's wait, from the first step up: one at least, each longer
    /// than the one before.
    public let waits: [Duration]

    /// The ladder Ficha starts with: 1 hour, 4 hours, 2 days, 5 days, 12
    /// days, 30 days and 75 days.
    public static let standard = Ladder(
        checkedWaits: [.hours(1), .hours(4), .days(2), .days(5), .days(12), .days(30), .days(75)])

    /// The ladder with these waits, which are known to be one at least, each
    /// longer than the one before.
    private init(checkedWaits waits: [Duration]) {
        self.waits = waits
    }

    /// The ladder with these waits, from the first step up, or nil unless
    /// there's one at least and each is longer than the one before, the
    /// first longer than nothing.
    public init?(waits: [Duration]) {
        guard !waits.isEmpty, zip([.zero] + waits, waits).allSatisfy({ $0 < $1 }) else {
            return nil
        }
        self.waits = waits
    }

    /// Where a card's way stands on the ladder after that way's entries in
    /// the review log, as if it were a card of its own (ADR 0016). The
    /// entries can come in any order, and from two devices, each of which
    /// rated the card for the wait it knew of (ADR 0017): they're replayed in
    /// the order `ReviewLogEntry.isReplayed(before:)` gives, so every device
    /// works out the same step. Without entries it's new. Its first view
    /// puts it on the first step, to wait its wait from then, and a
    /// placement, which an import gave it in place of a first view, on the
    /// placement's step until its due time, or on the last step when the
    /// ladder no longer has that one (ADR 0013). Another device's first view
    /// after that changes nothing. Then good moves it up one step, as easy
    /// does, hard keeps it on its step and again sends it back to the first.
    /// The last step repeats for good. After each review, the card waits its
    /// step's wait from when Lucas answered. A review ahead only counts when
    /// it's an again: hard and good leave the card's step and due time as
    /// they were (ADR 0002). Each review answered the entry it names, or the
    /// entry replayed before it, as on one device, when it names none or one
    /// the log doesn't have. A good that answered an entry replayed before
    /// the good that last moved the card up counts as ahead too: another
    /// device rated the same wait before it knew of that one, so one wait
    /// never climbs two steps. And a review its device took for one ahead
    /// counts as on time when an entry that device didn't know of had made
    /// the card due by then.
    public func standing(after entries: [ReviewLogEntry]) throws(UnexpectedReviewLog) -> LadderStanding {
        let entries = entries.sorted { $0.isReplayed(before: $1) }
        let positions = Dictionary(
            entries.indices.compactMap { position in entries[position].uuid.map { ($0, position) } },
            uniquingKeysWith: { first, _ in first })
        var replay: Replay?
        for (position, entry) in entries.enumerated() {
            switch (entry.kind, replay) {
            case (.firstView, .none):
                replay = Replay(
                    ladder: self, step: 0, due: entry.answeredAt.adding(waits[0]), lastMove: position)
            case (.placement(let placement), .none) where placement.step >= 0:
                replay = Replay(
                    ladder: self, step: min(placement.step, waits.count - 1), due: placement.due,
                    lastMove: position)
            case (.firstView, .some):
                continue
            case (.review(let rating), .some):
                let answered = entry.answeredEntry.flatMap { positions[$0] } ?? position - 1
                replay?.review(rating, of: entry, at: position, answering: answered)
            case (.placement, _), (.review, .none):
                throw UnexpectedReviewLog(cardID: entry.cardID)
            }
        }
        guard let replay else {
            return .new
        }
        return .onLadder(step: replay.step, due: replay.due)
    }

    /// Where an import that brings a card's progress from another app places
    /// it, as it stood there at `stage` (ADR 0013): a card being learned on
    /// the first step, and one in review on the step whose wait is nearest
    /// its interval, the last step when its interval is longer, the shorter
    /// wait when two are as near; each due when it was due there. Nil for a
    /// new card, which comes in new.
    public func placement(of stage: ImportedProgress.Stage) -> Placement? {
        switch stage {
        case .new:
            nil
        case .learning(let due):
            Placement(step: 0, due: due)
        case .review(let interval, let due):
            Placement(step: nearestStep(to: interval), due: due)
        }
    }

    /// The step whose wait is nearest `interval`, the first of two as near.
    private func nearestStep(to interval: Duration) -> Int {
        let distances = waits.map { wait in wait > interval ? wait - interval : interval - wait }
        return distances.indices.min { distances[$0] < distances[$1] } ?? 0
    }

    /// How many of the ways of `cards` are due at `now`, and how many of the
    /// cards are learned: their front-first way on a step that waits 30 days
    /// or more, so that switching Both ways on changes nothing there.
    public func counts(of cards: CardsInReviews, at now: Date) throws(UnexpectedReviewLog) -> (due: Int, learned: Int) {
        let standings = try cards.standings(on: self)
        let frontFirst = standings.filter { cardWay, _ in cardWay.way == .frontFirst }.map(\.standing)
        return (standings.count { $0.standing.isDue(at: now) }, frontFirst.count(where: isLearned))
    }

    /// Where each of these cards' ways stands, in the order given, after the
    /// review log's entries, in any order: each way after its own.
    func standings(of ways: [CardWay], after log: [ReviewLogEntry]) throws(UnexpectedReviewLog)
        -> [(way: CardWay, standing: LadderStanding)]
    {
        let entries = Dictionary(grouping: log, by: \.cardWay)
        return try ways.map { way throws(UnexpectedReviewLog) in (way, try standing(after: entries[way] ?? [])) }
    }

    /// Whether a card that stands on this ladder is learned: on a step that
    /// waits 30 days or more. The menu counts these cards, and the Cards
    /// window lists them.
    public func isLearned(_ standing: LadderStanding) -> Bool {
        guard case .onLadder(let step, _) = standing else {
            return false
        }
        return waits[step] >= .days(30)
    }
}

// The order the ladder replays a way's log in lives here, beside the replay,
// where the merge gate watches the scheduler.
extension ReviewLogEntry {
    /// Whether this entry comes before `other` as the ladder replays a way's
    /// log, in an order worked out from the entries alone, so that every
    /// device replays a log that joins two devices' entries alike, whatever
    /// order they arrived in (ADR 0017). First views and placements come
    /// first, since only they start a way, and reviews after them, each in
    /// the order Lucas answered them. At the same moment, a first view comes
    /// before a placement, a lower step's placement first, and of two
    /// reviews, easy before good, good before hard and hard before again, so
    /// that a "Don't know" rated at the same moment as a "Know it" on another
    /// device has the last word. Entries that tie on all of this move the way
    /// alike.
    public func isReplayed(before other: ReviewLogEntry) -> Bool {
        if kind.startsAWay != other.kind.startsAWay {
            return kind.startsAWay
        }
        if answeredAt != other.answeredAt {
            return answeredAt < other.answeredAt
        }
        switch (kind, other.kind) {
        case (.firstView, .placement):
            return true
        case (.placement(let placement), .placement(let otherPlacement)):
            return (placement.step, placement.due) < (otherPlacement.step, otherPlacement.due)
        case (.review(let rating), .review(let otherRating)):
            return rating.orderAtTheSameMoment < otherRating.orderAtTheSameMoment
        default:
            return false
        }
    }
}

extension ReviewLogEntry.Kind {
    /// Whether an entry of this kind can start a way: a first view or a
    /// placement, and not a review.
    fileprivate var startsAWay: Bool {
        switch self {
        case .firstView, .placement: true
        case .review: false
        }
    }
}

/// Where a card's way stands on a ladder as its log is replayed, entry by
/// entry, from the entry that started it, and which entries of the replay,
/// by their positions in it, last moved it and last moved it up.
private struct Replay {
    let ladder: Ladder
    var step: Int
    var due: Date
    /// The position of the entry that last set the way's step and due time.
    var lastMove: Int
    /// The position of the good that last moved the way up a step, or nil
    /// when none has.
    var lastClimb: Int?

    /// Moves the way as `review`, at `position` in the replay, with `rating`,
    /// does, as `Ladder.standing(after:)` says, given that it answered the
    /// entry at `answered`.
    mutating func review(_ rating: Rating, of review: ReviewLogEntry, at position: Int, answering answered: Int) {
        let time = review.answeredAt
        let knewLastMove = answered >= lastMove
        let ahead = review.isAhead && (knewLastMove || due > time)
        let answeredAClimbedWait = lastClimb.map { answered < $0 } ?? false
        switch rating {
        case .again:
            step = 0
        case .hard:
            guard !ahead else {
                return
            }
        case .good, .easy:
            guard !ahead, !answeredAClimbedWait else {
                return
            }
            let climbed = min(step + 1, ladder.waits.count - 1)
            if climbed > step {
                lastClimb = position
            }
            step = climbed
        }
        due = time.adding(ladder.waits[step])
        lastMove = position
    }
}

/// A card's way's review log with reviews but no first view or placement to
/// start it, or with a placement that doesn't start it or is on a step below
/// the first: the ladder can't tell where the card stands.
public struct UnexpectedReviewLog: Error, Equatable {
    public let cardID: Int64
}
