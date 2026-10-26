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
    /// the review log, in the order they happened, as if it were a card of
    /// its own (ADR 0016). Without entries it's new. Its first view
    /// puts it on the first step, to wait its wait from then, and a
    /// placement, which an import gave it in place of a first view, on the
    /// placement's step until its due time, or on the last step when the
    /// ladder no longer has that one (ADR 0013). Then good moves it up one
    /// step, hard keeps it on its step and again sends it back to the first.
    /// The last step repeats for good. After each review, the card waits its
    /// step's wait from when Lucas answered. A review ahead only counts when
    /// it's an again: hard and good leave the card's step and due time as
    /// they were (ADR 0002).
    public func standing(after entries: [ReviewLogEntry]) throws(UnexpectedReviewLog) -> LadderStanding {
        guard let first = entries.first else {
            return .new
        }
        var step: Int
        var due: Date
        switch first.kind {
        case .firstView:
            step = 0
            due = first.answeredAt.adding(waits[0])
        case .placement(let placement):
            guard placement.step >= 0 else {
                throw UnexpectedReviewLog(cardID: first.cardID)
            }
            step = min(placement.step, waits.count - 1)
            due = placement.due
        case .review:
            throw UnexpectedReviewLog(cardID: first.cardID)
        }
        for entry in entries.dropFirst() {
            guard case .review(let rating) = entry.kind else {
                throw UnexpectedReviewLog(cardID: entry.cardID)
            }
            switch (rating, entry.isAhead) {
            case (.again, _): step = 0
            case (.hard, false): break
            case (.good, false): step = min(step + 1, waits.count - 1)
            case (.hard, true), (.good, true): continue
            }
            due = entry.answeredAt.adding(waits[step])
        }
        return .onLadder(step: step, due: due)
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
        let frontFirst = standings.filter { $0.way.way == .frontFirst }.map(\.standing)
        return (standings.count { $0.standing.isDue(at: now) }, frontFirst.count(where: isLearned))
    }

    /// Where each of these cards' ways stands, in the order given, after the
    /// review log's entries, in the order they were written: each way after
    /// its own.
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

/// A card's review log that doesn't start with its first view or a placement,
/// or that has a second one later, or a placement on a step below the first:
/// the ladder can't tell where the card stands.
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
