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
        checkedWaits: [hours(1), hours(4), days(2), days(5), days(12), days(30), days(75)])

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
    /// after that changes nothing. Then good moves it up one step, hard keeps
    /// it on its step and again sends it back to the first. The last step
    /// repeats for good. After each review, the card waits its step's wait
    /// from when Lucas answered. A review ahead only counts when it's an
    /// again: hard and good leave the card's step and due time as they were
    /// (ADR 0002). So does a good that answers the same wait as the good that
    /// last moved the card up, which another device rated before it knew of
    /// that one, so one wait never climbs two steps; an again since then
    /// lets the card climb again.
    public func standing(after entries: [ReviewLogEntry]) throws(UnexpectedReviewLog) -> LadderStanding {
        let entries = entries.sorted { $0.isReplayed(before: $1) }
        guard let first = entries.first else {
            return .new
        }
        var replay = try Replay(startedBy: first, on: self)
        for entry in entries.dropFirst() {
            switch entry.kind {
            case .firstView:
                continue
            case .placement:
                throw UnexpectedReviewLog(cardID: entry.cardID)
            case .review(let rating):
                replay.review(rating, at: entry.answeredAt, ahead: entry.isAhead)
            }
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
        return waits[step] >= days(30)
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
    /// reviews, good before hard and hard before again, so that a "Don't
    /// know" rated at the same moment as a "Know it" on another device has
    /// the last word. Entries that tie on all of this move the way alike.
    public func isReplayed(before other: ReviewLogEntry) -> Bool {
        replayOrder < other.replayOrder
    }

    /// The values `isReplayed(before:)` compares, in turn: whether it's a
    /// review, when Lucas answered, its kind's place at the same moment, and
    /// a placement's step and due time.
    private var replayOrder: (Int, Date, Int, Int, Date) {
        switch kind {
        case .firstView: (0, answeredAt, 0, 0, answeredAt)
        case .placement(let placement): (0, answeredAt, 1, placement.step, placement.due)
        case .review(.good): (1, answeredAt, 0, 0, answeredAt)
        case .review(.hard): (1, answeredAt, 1, 0, answeredAt)
        case .review(.again): (1, answeredAt, 2, 0, answeredAt)
        }
    }
}

/// Where a card's way stands on a ladder as its log is replayed, entry by
/// entry, from the entry that started it.
private struct Replay {
    let ladder: Ladder
    var step: Int
    var due: Date
    /// When good last moved the way up a step, and until when another good
    /// answers the same wait, or nil when nothing moved it up since it
    /// started or again last sent it back.
    var lastClimb: (at: Date, sameWaitUntil: Date)?

    /// The way as `start`, its first view or its placement, puts it on
    /// `ladder`, or an error when it's a review, which can't start a way, or
    /// a placement on a step below the first.
    init(startedBy start: ReviewLogEntry, on ladder: Ladder) throws(UnexpectedReviewLog) {
        self.ladder = ladder
        switch start.kind {
        case .firstView:
            step = 0
            due = start.answeredAt.adding(ladder.waits[0])
        case .placement(let placement):
            guard placement.step >= 0 else {
                throw UnexpectedReviewLog(cardID: start.cardID)
            }
            step = min(placement.step, ladder.waits.count - 1)
            due = placement.due
        case .review:
            throw UnexpectedReviewLog(cardID: start.cardID)
        }
    }

    /// Moves the way as a review with `rating` at `time` does, a review
    /// ahead when `ahead` says so, as `Ladder.standing(after:)` says.
    mutating func review(_ rating: Rating, at time: Date, ahead: Bool) {
        switch (rating, ahead) {
        case (.again, _):
            step = 0
            lastClimb = nil
        case (.hard, false):
            break
        case (.good, false):
            if let lastClimb, time < lastClimb.sameWaitUntil {
                return
            }
            let climbed = min(step + 1, ladder.waits.count - 1)
            if climbed > step {
                lastClimb = (time, time.adding(sameWait(afterClimbingFrom: step)))
            }
            step = climbed
        case (.hard, true), (.good, true):
            return
        }
        due = time.adding(ladder.waits[step])
    }

    /// How long after good moves a way up from `step` another good of that
    /// way answers the same wait: one another device rated before it knew of
    /// the first. On one device, the way waits the next step's wait, longer
    /// than this step's, before it's due again, and an appearance brings it
    /// along no more than the longest look-ahead earlier, so its next good
    /// never comes this soon. That holds also after Lucas changes the
    /// ladder, unless he lengthens both steps, this one past the next one's
    /// old wait.
    private func sameWait(afterClimbingFrom step: Int) -> Duration {
        min(ladder.waits[step], ladder.waits[step + 1] - ReviewSettings.longestLookAhead)
    }
}

/// A card's review log without a first view or a placement, or with a
/// placement that doesn't start it or is on a step below the first: the
/// ladder can't tell where the card stands.
public struct UnexpectedReviewLog: Error, Equatable {
    public let cardID: Int64
}

/// A span of whole hours.
private func hours(_ count: Int64) -> Duration {
    .seconds(count * 60 * 60)
}

/// A span of whole days.
private func days(_ count: Int64) -> Duration {
    .seconds(count * 24 * 60 * 60)
}
