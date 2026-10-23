import Foundation

/// The cards in Lucas's reviews, the only ones that show up, as the planners
/// pick from them: out of every card, those whose standing is in his reviews,
/// by id in the order he approved them, with the whole review log. The
/// planners take nothing else, so which cards can show up is decided here,
/// from where each card stands, and the merge gate watches it.
public struct CardsInReviews: Sendable, Equatable {
    /// The cards in Lucas's reviews, by id in the order he approved them.
    let ids: [Int64]
    /// The whole review log, in the order it was written.
    let log: [ReviewLogEntry]

    /// The cards in Lucas's reviews out of `cards`, every card by id with
    /// where it stands, in the order he approved them, along with `log`, the
    /// whole review log, in the order it was written.
    public init(_ cards: [(id: Int64, standing: CardStanding)], log: [ReviewLogEntry]) {
        ids = cards.compactMap { card in
            guard case .inReviews = card.standing else {
                return nil
            }
            return card.id
        }
        self.log = log
    }

    /// Where each card stands on `ladder`, by id in the order Lucas approved
    /// them, after the review log.
    func standings(on ladder: Ladder) throws(UnexpectedReviewLog) -> [(cardID: Int64, standing: LadderStanding)] {
        try ladder.standings(of: ids, after: log)
    }
}
