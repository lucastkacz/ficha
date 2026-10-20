import FichaCore
import Foundation
internal import GRDB

/// A card as the Cards window lists it: the card, where it stands on Lucas's
/// ladder, and when he last saw it.
public struct CardRow: Sendable, Equatable, Identifiable {
    public let card: Card
    /// Where it stands: new, or on a step until it's due, worked out from its
    /// review log.
    public let standing: CardStanding
    /// How long its step waits, or nil while it's new.
    public let wait: Duration?
    /// When Lucas last saw it: its review log's latest entry, its first view
    /// or a review, or nil while it's new.
    public let lastSeen: Date?

    public var id: Int64 {
        card.id
    }

    /// The step it stands on, counted from 0, the first step, or nil while
    /// it's new.
    public var step: Int? {
        guard case .onLadder(let step, _) = standing else {
            return nil
        }
        return step
    }

    /// When the card is due, as the Cards window says it: nil while it's new,
    /// or out of Lucas's reviews, flagged or buried, since it won't show up
    /// then.
    public var due: Date? {
        guard card.isInReviews else {
            return nil
        }
        return standing.due
    }
}

extension Engine {
    /// Every card that isn't buried, as the Cards window lists them, in the
    /// order Lucas approved them, each standing on `ladder`.
    public func cardRows(on ladder: Ladder) throws(EngineError) -> [CardRow] {
        try read { db in
            let entries = Dictionary(grouping: try logEntries(in: db), by: \.cardID)
            return try allCards(in: db).filter { $0.buriedAt == nil }.map { card in
                try CardRow(card: card, after: entries[card.id] ?? [], on: ladder)
            }
        }
    }
}

extension CardRow {
    /// The row of `card`, standing on `ladder` after `entries`, its review
    /// log's, in the order they happened.
    fileprivate init(card: Card, after entries: [ReviewLogEntry], on ladder: Ladder) throws(UnexpectedReviewLog) {
        self.card = card
        standing = try ladder.standing(after: entries)
        lastSeen = entries.last?.answeredAt
        if case .onLadder(let step, _) = standing {
            wait = ladder.waits[step]
        } else {
            wait = nil
        }
    }
}
