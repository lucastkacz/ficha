import FichaCore
internal import GRDB

// Which cards are in Lucas's reviews, as their standing says: the only ones
// the review panel brings, and takes an answer for. They decide which cards
// show up, so `make upload` lists each change to this file among those
// that reach Lucas's cards (`scripts/data-changes.sh`).

/// The cards that show up, as the engine reads them for the planners: the
/// cards in Lucas's reviews, whose ways the planners pick from, and every
/// card, by id, which what they pick maps back to.
struct CardsThatShowUp {
    /// The cards in Lucas's reviews, with the whole review log, as the
    /// planners take them: `CardsInReviews` keeps only the ways of the cards
    /// whose standing is in his reviews.
    let inReviews: CardsInReviews
    /// Every card, by id.
    private let cards: [Int64: Card]

    /// The cards that show up out of `cards`, every card in the order Lucas
    /// approved them, those that live in one of `priorityDecks`, or in a deck
    /// inside one, as priority cards, the decks the user moved in the queue
    /// new cards come from at `queuePlaces`, and `log`, the whole review log,
    /// in the order it was written.
    fileprivate init(
        _ cards: [Card], priorityDecks: Set<String>, queuePlaces: [String: Date], log: [ReviewLogEntry]
    ) {
        inReviews = CardsInReviews(
            cards.map { ($0.id, $0.standing, $0.deck, $0.bothWays, $0.createdAt) }, priorityDecks: priorityDecks,
            queuePlaces: queuePlaces, log: log)
        self.cards = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
    }

    /// The cards the review panel brings, each the way a planner picked it, in
    /// the order it shows them: the ways to review, the ways to review ahead,
    /// and then the new way, but for the one the planner said comes first.
    func panelCards(_ picked: PanelCardIDs) throws -> [PanelCard] {
        var panelCards = try picked.reviews.map { PanelCard.review(try card($0.cardID), $0.way) }
        panelCards += try picked.reviewsAhead.map { PanelCard.reviewAhead(try card($0.cardID), $0.way) }
        if let newWay = picked.newWay {
            panelCards.append(.new(try card(newWay.cardID), newWay.way))
        }
        if let shownFirst = picked.shownFirst, let index = panelCards.firstIndex(where: { $0.cardWay == shownFirst }) {
            panelCards.insert(panelCards.remove(at: index), at: 0)
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

/// The cards that show up, out of every card, the priority decks, the
/// places of the decks the user moved in the queue new cards come from and
/// the whole review log: the one way in to them, which every entry point
/// that picks cards reads, never gathering them again.
func cardsThatShowUp(in db: Database) throws -> CardsThatShowUp {
    CardsThatShowUp(
        try allCards(in: db), priorityDecks: try decks(switchedOn: .priority, in: db),
        queuePlaces: try queuePlaces(in: db), log: try logEntries(in: db))
}

/// The place in the queue new cards come from of each deck the user moved
/// in it (ADR 0034), by name.
func queuePlaces(in db: Database) throws -> [String: Date] {
    var places: [String: Date] = [:]
    for row in try Row.fetchAll(db, sql: "SELECT name, queuePlace FROM deck WHERE queuePlace IS NOT NULL") {
        let name: String = try row.decode(forColumn: "name")
        places[name] = try row.decode(forColumn: "queuePlace") as Date
    }
    return places
}

/// The decks that are set aside: every card that lives in one of them, or in
/// a deck inside one, is set aside, unless it's buried or flagged, as its
/// standing says. A tag's switch, kept from before decks for the conversion
/// of Lucas's tags (ADR 0024), sets no card aside.
func setAsideDecks(in db: Database) throws -> Set<String> {
    try decks(switchedOn: .setAside, in: db)
}

/// The decks that have `deckSwitch` on.
func decks(switchedOn deckSwitch: DeckSwitch, in db: Database) throws -> Set<String> {
    Set(try String.fetchAll(db, sql: "SELECT name FROM deck WHERE switchedOn = ?", arguments: [deckSwitch.rawValue]))
}

/// The card with this id, while it's in Lucas's reviews, or an error that
/// says it's buried, flagged or set aside, or that there's no such card.
func cardInReviews(_ cardID: Int64, in db: Database) throws -> Card {
    let card = try existingCard(cardID, in: db)
    switch card.standing {
    case .inReviews: return card
    case .inInbox: throw EngineError.cardFlagged(cardID)
    case .buried: throw EngineError.cardBuried(cardID)
    case .setAside(let decks): throw EngineError.cardSetAside(cardID, decks: decks)
    }
}
