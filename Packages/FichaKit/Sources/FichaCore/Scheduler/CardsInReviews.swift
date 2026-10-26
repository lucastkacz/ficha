import Foundation

/// The cards in Lucas's reviews, the only ones that show up, as the planners
/// pick from them: out of every card, the ways of those whose standing is in
/// his reviews, by card in the order he approved them, with which cards are
/// priority cards, and the whole review log. The planners take nothing else,
/// so which ways can show up, and which come first, is decided here, from
/// where each card stands and its tags, and the merge gate watches it.
public struct CardsInReviews: Sendable, Equatable {
    /// The ways in Lucas's reviews, by card in the order he approved them:
    /// each card's front-first way, since no card shows up back first yet.
    let ways: [CardWay]
    /// The cards in Lucas's reviews with any of the priority tags, by id,
    /// whose ways come first when cards show up (ADR 0011).
    let priorityIDs: Set<Int64>
    /// The whole review log, in the order it was written.
    let log: [ReviewLogEntry]
    /// The tags of the cards in Lucas's reviews, which the menu's Prioritize
    /// submenu offers.
    public let tags: Set<String>

    /// The cards in Lucas's reviews out of `cards`, every card by id with
    /// where it stands and its tags, in the order he approved them, those
    /// with any of `priorityTags` as priority cards, along with `log`, the
    /// whole review log, in the order it was written.
    public init(
        _ cards: [(id: Int64, standing: CardStanding, tags: [String])],
        priorityTags: Set<String>,
        log: [ReviewLogEntry]
    ) {
        let inReviews = cards.filter { $0.standing == .inReviews }
        ways = inReviews.map { CardWay(cardID: $0.id, way: .frontFirst) }
        priorityIDs = Set(inReviews.filter { !priorityTags.isDisjoint(with: $0.tags) }.map(\.id))
        self.log = log
        tags = Set(inReviews.flatMap(\.tags))
    }

    /// These ways in Lucas's reviews, these cards as priority cards, this
    /// review log, and the tags of the cards in his reviews.
    private init(ways: [CardWay], priorityIDs: Set<Int64>, log: [ReviewLogEntry], tags: Set<String>) {
        self.ways = ways
        self.priorityIDs = priorityIDs
        self.log = log
        self.tags = tags
    }

    /// The same cards as if no tag were a priority tag.
    var withoutPriority: CardsInReviews {
        CardsInReviews(ways: ways, priorityIDs: [], log: log, tags: tags)
    }

    /// Where each way stands on `ladder`, by card in the order Lucas approved
    /// them, after the review log.
    func standings(on ladder: Ladder) throws(UnexpectedReviewLog) -> [(way: CardWay, standing: LadderStanding)] {
        try ladder.standings(of: ways, after: log)
    }

    /// `ways` split into those of priority cards and the others, each group
    /// in the order it had.
    func splitByPriority(_ ways: [CardWay]) -> (priority: [CardWay], others: [CardWay]) {
        (ways.filter { priorityIDs.contains($0.cardID) }, ways.filter { !priorityIDs.contains($0.cardID) })
    }
}
