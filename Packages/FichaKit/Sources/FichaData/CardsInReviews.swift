import FichaCore
internal import GRDB

// Which cards are in Lucas's reviews, as their standing says: the only ones
// the review panel brings, and takes an answer or a flag for. They decide
// which cards show up, so the merge gate (`.claude/hooks/merge-gate.sh`)
// watches this file: changing it makes a pull request risk:high.

/// The cards in Lucas's reviews, in the order he approved them.
func cardsInReviews(in db: Database) throws -> [Card] {
    try allCards(in: db).filter { $0.standing == .inReviews }
}

/// The card with this id, while it's in Lucas's reviews, or an error that
/// says it's buried or flagged, or that there's no such card.
func cardInReviews(_ cardID: Int64, in db: Database) throws -> Card {
    let card = try existingCard(cardID, in: db)
    switch card.standing {
    case .inReviews: return card
    case .inInbox: throw EngineError.cardFlagged(cardID)
    case .buried: throw EngineError.cardBuried(cardID)
    }
}
