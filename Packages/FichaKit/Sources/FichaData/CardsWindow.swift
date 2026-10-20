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

    /// When the card is due, as the Cards window says it: nil while it's
    /// new, flagged or buried, since it won't show up until then.
    public var due: Date? {
        guard card.flag == nil, card.buriedAt == nil else {
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
                let cardEntries = entries[card.id] ?? []
                let standing = try ladder.standing(after: cardEntries)
                return CardRow(
                    card: card,
                    standing: standing,
                    wait: standing.step.map { ladder.waits[$0] },
                    lastSeen: cardEntries.last?.answeredAt
                )
            }
        }
    }
}

extension CardStanding {
    /// The step the card stands on, counted from 0, or nil while it's new.
    fileprivate var step: Int? {
        guard case .onLadder(let step, _) = self else {
            return nil
        }
        return step
    }
}
