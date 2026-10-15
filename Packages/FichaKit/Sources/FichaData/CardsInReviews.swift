internal import GRDB

// Which cards are in Lucas's reviews: those neither flagged nor buried, the
// only ones the review panel brings, and takes an answer or a flag for. They
// decide which cards show up, so the merge gate (`.claude/hooks/merge-gate.sh`)
// watches this file: changing it makes a pull request risk:high.

extension Card {
    /// Whether the card is in Lucas's reviews: neither flagged, waiting in
    /// the inbox to be fixed, nor buried.
    var isInReviews: Bool {
        flag == nil && buriedAt == nil
    }
}

/// The cards in Lucas's reviews, in the order he approved them.
func cardsInReviews(in db: Database) throws -> [Card] {
    try allCards(in: db).filter(\.isInReviews)
}

/// The card with this id, while it's in Lucas's reviews, or an error that
/// says it's buried or flagged, or that there's no such card.
func cardInReviews(_ cardID: Int64, in db: Database) throws -> Card {
    let card = try existingCard(cardID, in: db)
    guard card.buriedAt == nil else {
        throw EngineError.cardBuried(cardID)
    }
    guard card.flag == nil else {
        throw EngineError.cardFlagged(cardID)
    }
    return card
}
