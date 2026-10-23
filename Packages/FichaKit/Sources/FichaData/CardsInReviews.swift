import FichaCore
internal import GRDB

// Which cards are in Lucas's reviews, as their standing says: the only ones
// the review panel brings, and takes an answer or a flag for. They decide
// which cards show up, so the merge gate (`.claude/hooks/merge-gate.sh`)
// watches this file: changing it makes a pull request risk:high.

/// The cards that show up, as the engine reads them for the planners: the
/// cards in Lucas's reviews, which the planners pick from, and every card, by
/// id, which what they pick maps back to.
struct CardsThatShowUp {
    /// The cards in Lucas's reviews, with the whole review log, as the
    /// planners take them: `CardsInReviews` keeps only the cards whose
    /// standing is in his reviews.
    let inReviews: CardsInReviews
    /// Every card, by id.
    private let cards: [Int64: Card]

    /// The cards that show up out of `cards`, every card in the order Lucas
    /// approved them, and `log`, the whole review log, in the order it was
    /// written.
    fileprivate init(_ cards: [Card], log: [ReviewLogEntry]) {
        inReviews = CardsInReviews(cards.map { ($0.id, $0.standing) }, log: log)
        self.cards = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
    }

    /// The cards the review panel brings, as a planner picked them by id, in
    /// the order it shows them: the cards to review, the cards to review
    /// ahead, and then the new card.
    func panelCards(_ picked: PanelCardIDs) throws -> [PanelCard] {
        var panelCards = try picked.reviews.map { PanelCard.review(try card($0)) }
        panelCards += try picked.reviewsAhead.map { PanelCard.reviewAhead(try card($0)) }
        if let id = picked.firstView {
            panelCards.append(.firstView(try card(id)))
        }
        return panelCards
    }

    /// The card with this id.
    private func card(_ id: Int64) throws -> Card {
        guard let card = cards[id] else {
            throw EngineError.cardNotFound(id)
        }
        return card
    }
}

/// The cards that show up, out of every card and the whole review log: the
/// one way in to them, which every entry point that picks cards reads,
/// never gathering them again.
func cardsThatShowUp(in db: Database) throws -> CardsThatShowUp {
    CardsThatShowUp(try allCards(in: db), log: try logEntries(in: db))
}

/// The card with this id, while it's in Lucas's reviews, or an error that
/// says it's buried, flagged or set aside, or that there's no such card.
func cardInReviews(_ cardID: Int64, in db: Database) throws -> Card {
    let card = try existingCard(cardID, in: db)
    switch card.standing {
    case .inReviews: return card
    case .inInbox: throw EngineError.cardFlagged(cardID)
    case .buried: throw EngineError.cardBuried(cardID)
    case .setAside(let tags): throw EngineError.cardSetAside(cardID, tags: tags)
    }
}
