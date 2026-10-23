import Foundation

/// The cards in Lucas's reviews, the only ones that show up, as the planners
/// pick from them: out of every card, those whose standing is in his reviews,
/// by id in the order he approved them, with which of them are priority
/// cards, and the whole review log. The planners take nothing else, so which
/// cards can show up, and which come first, is decided here, from where each
/// card stands and its tags, and the merge gate watches it.
public struct CardsInReviews: Sendable, Equatable {
    /// The cards in Lucas's reviews, by id in the order he approved them.
    let ids: [Int64]
    /// The cards in Lucas's reviews with any of the priority tags, which come
    /// first when cards show up (ADR 0011).
    let priorityIDs: Set<Int64>
    /// The whole review log, in the order it was written.
    let log: [ReviewLogEntry]

    /// The cards in Lucas's reviews out of `cards`, every card by id with
    /// where it stands and its tags, in the order he approved them, those
    /// with any of `priorityTags` as priority cards, along with `log`, the
    /// whole review log, in the order it was written.
    public init(
        _ cards: [(id: Int64, standing: CardStanding, tags: [String])],
        priorityTags: Set<String>,
        log: [ReviewLogEntry]
    ) {
        let inReviews = cards.filter { card in
            guard case .inReviews = card.standing else {
                return false
            }
            return true
        }
        ids = inReviews.map(\.id)
        priorityIDs = Set(inReviews.filter { !priorityTags.isDisjoint(with: $0.tags) }.map(\.id))
        self.log = log
    }

    /// Where each card stands on `ladder`, by id in the order Lucas approved
    /// them, after the review log.
    func standings(on ladder: Ladder) throws(UnexpectedReviewLog) -> [(cardID: Int64, standing: LadderStanding)] {
        try ladder.standings(of: ids, after: log)
    }

    /// `cards`, by id, split into the priority cards and the others, each
    /// group in the order it had.
    func splitByPriority(_ cards: [Int64]) -> (priority: [Int64], others: [Int64]) {
        (cards.filter(priorityIDs.contains), cards.filter { !priorityIDs.contains($0) })
    }
}
