import Foundation

/// The cards in Lucas's reviews, the only ones that show up, as the planners
/// pick from them: out of every card, the ways of those whose standing is in
/// his reviews, by card in the order he approved them, with which cards are
/// priority cards, and the whole review log. The planners take nothing else,
/// so which ways can show up, and which come first, is decided here, from
/// where each card stands and its deck, and the merge gate watches it.
public struct CardsInReviews: Sendable, Equatable {
    /// The ways in Lucas's reviews, by card in the order he approved them:
    /// each card's front-first way, and then its back-first way, when it has
    /// one.
    let ways: [CardWay]
    /// The cards in Lucas's reviews that live in a priority deck, or in a deck
    /// inside one, by id, whose ways come first when cards show up (ADR 0011,
    /// ADR 0024).
    let priorityIDs: Set<Int64>
    /// The whole review log, in the order it was written.
    let log: [ReviewLogEntry]

    /// The cards in Lucas's reviews out of `cards`, every card by id with
    /// where it stands, its deck, by its whole name, and whether it goes both
    /// ways, in the order he approved them, those that live in one of
    /// `priorityDecks`, or in a deck inside one, as `TagPath` reads a deck's
    /// levels, as priority cards, along with `log`, the whole review log, in
    /// the order it was written. A card's tags never make it one.
    /// Each card in his reviews brings its front-first way, and, when it goes
    /// both ways, its back-first way, once its front-first way had its first
    /// view or a placement (ADR 0016): the card's standing is both ways'.
    public init(
        _ cards: [(id: Int64, standing: CardStanding, deck: String, bothWays: Bool)],
        priorityDecks: Set<String>,
        log: [ReviewLogEntry]
    ) {
        let inReviews = cards.filter { $0.standing == .inReviews }
        let metFrontFirst = Set(log.filter { $0.way == .frontFirst }.map(\.cardID))
        ways = inReviews.flatMap { card in
            let frontFirst = CardWay(cardID: card.id, way: .frontFirst)
            guard card.bothWays, metFrontFirst.contains(card.id) else {
                return [frontFirst]
            }
            return [frontFirst, CardWay(cardID: card.id, way: .backFirst)]
        }
        priorityIDs = Set(
            inReviews.filter { !priorityDecks.isDisjoint(with: TagPath.lineage(of: $0.deck)) }.map(\.id))
        self.log = log
    }

    /// These ways in Lucas's reviews, these cards as priority cards and this
    /// review log.
    private init(ways: [CardWay], priorityIDs: Set<Int64>, log: [ReviewLogEntry]) {
        self.ways = ways
        self.priorityIDs = priorityIDs
        self.log = log
    }

    /// The same cards as if no deck were a priority deck.
    var withoutPriority: CardsInReviews {
        CardsInReviews(ways: ways, priorityIDs: [], log: log)
    }

    /// The same cards as if none went both ways: their front-first ways
    /// alone.
    var frontFirstOnly: CardsInReviews {
        CardsInReviews(ways: ways.filter { $0.way == .frontFirst }, priorityIDs: priorityIDs, log: log)
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
