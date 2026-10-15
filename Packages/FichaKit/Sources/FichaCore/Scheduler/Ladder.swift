import Foundation

/// The ladder: the fixed waits a card climbs as Lucas remembers it (ADR 0002).
/// Its steps count from 0, the first step.
public struct Ladder: Sendable, Equatable {
    /// Each step's wait, from the first step up. There's always one at least:
    /// the standard ladder is the only one, until Lucas can set his own.
    public let waits: [Duration]

    /// The ladder Ficha starts with: 1 hour, 4 hours, 2 days, 5 days, 12
    /// days, 30 days and 75 days.
    public static let standard = Ladder(waits: [
        hours(1), hours(4), days(2), days(5), days(12), days(30), days(75),
    ])

    private init(waits: [Duration]) {
        self.waits = waits
    }

    /// Where a card stands after the entries of its review log, in the order
    /// they happened. Without entries it's new. Its first view puts it on the
    /// first step; then good moves it up one step, hard keeps it on its step
    /// and again sends it back to the first. The last step repeats for good.
    /// After each entry, the card waits its step's wait from when Lucas
    /// answered.
    public func standing(after entries: [ReviewLogEntry]) throws(UnexpectedReviewLog) -> CardStanding {
        guard let first = entries.first else {
            return .new
        }
        guard first.kind == .firstView else {
            throw UnexpectedReviewLog(cardID: first.cardID)
        }
        var step = 0
        for entry in entries.dropFirst() {
            guard case .review(let rating) = entry.kind else {
                throw UnexpectedReviewLog(cardID: entry.cardID)
            }
            switch rating {
            case .again: step = 0
            case .hard: break
            case .good: step = min(step + 1, waits.count - 1)
            }
        }
        let last = entries[entries.count - 1]
        return .onLadder(step: step, due: last.answeredAt.addingTimeInterval(waits[step] / .seconds(1)))
    }

    /// How many cards are due at `now`, and how many are learned: on a step
    /// that waits 30 days or more. Out of every card, by id, and the whole
    /// review log, in the order it was written.
    public func counts(of cardIDs: [Int64], after log: [ReviewLogEntry], at now: Date) throws(UnexpectedReviewLog)
        -> (due: Int, learned: Int)
    {
        let standings = try standings(of: cardIDs, after: log).map(\.standing)
        return (standings.count { $0.isDue(at: now) }, standings.count(where: isLearned))
    }

    /// Where each card stands, by id in the order given, after the review
    /// log's entries, in the order they were written.
    func standings(of cardIDs: [Int64], after log: [ReviewLogEntry]) throws(UnexpectedReviewLog)
        -> [(cardID: Int64, standing: CardStanding)]
    {
        let entries = Dictionary(grouping: log, by: \.cardID)
        return try cardIDs.map { id throws(UnexpectedReviewLog) in (id, try standing(after: entries[id] ?? [])) }
    }

    /// Whether a card that stands on this ladder is learned: on a step that
    /// waits 30 days or more.
    private func isLearned(_ standing: CardStanding) -> Bool {
        guard case .onLadder(let step, _) = standing else {
            return false
        }
        return waits[step] >= days(30)
    }
}

/// A card's review log that doesn't start with its first view, or that has a
/// second one: the ladder can't tell where the card stands.
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
