import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// The cards review now brings, in the order the review panel shows them:
    /// the due ones, lowest step first and then the longest overdue, and then
    /// a new card, when there's room and Lucas hasn't met the day's new cards
    /// yet.
    public func reviewNow(_ settings: ReviewSettings) throws(EngineError) -> [PanelCard] {
        let now = time.now
        return try read { db in
            let cards = try cardsInReviews(in: db)
            let picked = try settings.reviewNowCards(
                cardIDs: cards.map(\.id), log: logEntries(in: db), now: now, calendar: calendar)
            return try panelCards(picked, from: cards)
        }
    }

    /// Records Lucas's answer to a card in his reviews in the review log: the
    /// end of its first view, which puts it on the ladder's first step, or a
    /// review with his rating, which moves it on the ladder of `settings`. A
    /// first view is only for a new card, and a review only for a due one, or,
    /// in an appearance, for one due within the look-ahead, which it brings
    /// along. When Lucas asked to review ahead, a review of a card that isn't
    /// due yet goes into the log as a review ahead, of which only again
    /// counts; one of a card that came due by then is on time.
    public func record(
        _ kind: ReviewLogEntry.Kind,
        of cardID: Int64,
        responseTime: Duration,
        trigger: Trigger,
        settings: ReviewSettings,
        reviewingAhead: Bool = false
    ) throws(EngineError) {
        let answeredAt = time.now
        let lookAhead = trigger.lookAhead(in: settings)
        try write { db in
            _ = try cardInReviews(cardID, in: db)
            let standing = try settings.ladder.standing(after: logEntries(ofExisting: cardID, in: db))
            let isAhead = reviewingAhead && standing.isReviewAhead(kind, at: answeredAt, lookingAhead: lookAhead)
            if !isAhead {
                do throws(RefusedAnswer) {
                    try standing.check(kind, at: answeredAt, lookingAhead: lookAhead)
                } catch {
                    throw EngineError(refused: error, cardID: cardID)
                }
            }
            try insert(
                ReviewLogEntry(
                    cardID: cardID, kind: kind, answeredAt: answeredAt, responseTime: responseTime, trigger: trigger,
                    isAhead: isAhead),
                in: db)
        }
    }

    /// What the menu shows of Lucas's progress: how many cards in his reviews
    /// are due, how many he learned, and how many captures and flagged cards
    /// wait in the inbox.
    public func progress(_ settings: ReviewSettings) throws(EngineError) -> ProgressCounts {
        let now = time.now
        return try read { db in
            let cardIDs = try cardsInReviews(in: db).map(\.id)
            let counts = try settings.ladder.counts(of: cardIDs, after: logEntries(in: db), at: now)
            return ProgressCounts(
                due: counts.due, learned: counts.learned,
                inInbox: try capturesInInbox.fetchCount(db) + flaggedCardsInInbox.fetchCount(db))
        }
    }

    /// The cards "See more" brings once Lucas went through the review panel's
    /// cards, which `trigger` brought: the due cards that didn't fit, and then
    /// the cards closest to being due, as reviews ahead, out of the cards in
    /// his reviews but those in `shown`, the panel's. Never a new card. For an
    /// appearance, a card due within the look-ahead counts as due.
    func seeMore(after shown: Set<Int64>, from trigger: Trigger, settings: ReviewSettings) throws(EngineError)
        -> [PanelCard]
    {
        let horizon = time.now.adding(trigger.lookAhead(in: settings))
        return try read { db in
            let cards = try cardsInReviews(in: db).filter { !shown.contains($0.id) }
            let picked = try settings.seeMoreCards(cardIDs: cards.map(\.id), log: logEntries(in: db), dueBy: horizon)
            return try panelCards(picked, from: cards)
        }
    }

    /// Every first view and review, in the order they happened.
    public func reviewLog() throws(EngineError) -> [ReviewLogEntry] {
        try read(logEntries(in:))
    }

    /// Where a card stands: new, or on a step of `ladder` until it's due,
    /// worked out from its review log.
    public func standing(of cardID: Int64, on ladder: Ladder) throws(EngineError) -> CardStanding {
        try read { db in
            try ladder.standing(after: logEntries(ofExisting: cardID, in: db))
        }
    }
}

/// The cards the review panel brings, picked by id out of `cards`, in the
/// order it shows them: the cards to review, the cards to review ahead, and
/// then the new card.
func panelCards(_ picked: PanelCardIDs, from cards: [Card]) throws -> [PanelCard] {
    let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
    var panelCards = try picked.reviews.map { PanelCard.review(try card($0, in: cardsByID)) }
    panelCards += try picked.reviewsAhead.map { PanelCard.reviewAhead(try card($0, in: cardsByID)) }
    if let id = picked.firstView {
        panelCards.append(.firstView(try card(id, in: cardsByID)))
    }
    return panelCards
}

/// The card with this id, out of `cards`.
private func card(_ id: Int64, in cards: [Int64: Card]) throws -> Card {
    guard let card = cards[id] else {
        throw EngineError.cardNotFound(id)
    }
    return card
}

/// The review log's entries, in the order they happened.
func logEntries(in db: Database) throws -> [ReviewLogEntry] {
    try Row.fetchAll(db, sql: "SELECT * FROM reviewLog ORDER BY id").map(ReviewLogEntry.init(row:))
}

/// A card's entries in the review log, in the order they happened, or an
/// error when there's no such card.
private func logEntries(ofExisting cardID: Int64, in db: Database) throws -> [ReviewLogEntry] {
    guard try Row.fetchOne(db, sql: "SELECT id FROM card WHERE id = ?", arguments: [cardID]) != nil else {
        throw EngineError.cardNotFound(cardID)
    }
    return try Row.fetchAll(db, sql: "SELECT * FROM reviewLog WHERE cardId = ? ORDER BY id", arguments: [cardID])
        .map(ReviewLogEntry.init(row:))
}

/// Adds an entry at the end of the review log.
private func insert(_ entry: ReviewLogEntry, in db: Database) throws {
    let (kind, rating) = entry.kind.columns
    try db.execute(
        sql: """
            INSERT INTO reviewLog (cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            entry.cardID, kind, rating, entry.answeredAt, entry.responseTime / .seconds(1), entry.trigger.rawValue,
            entry.isAhead,
        ]
    )
}

extension ReviewLogEntry {
    /// An entry read from a row of the `reviewLog` table.
    init(row: Row) throws {
        let cardID: Int64 = try row.decode(forColumn: "cardId")
        guard let kind = Kind(kind: try row.decode(forColumn: "kind"), rating: try row.decode(forColumn: "rating"))
        else {
            throw unreadable("Card \(cardID) has a review log entry of an unknown kind or rating")
        }
        let triggerName: String = try row.decode(forColumn: "trigger")
        guard let trigger = Trigger(rawValue: triggerName) else {
            throw unreadable("Card \(cardID) has a review log entry with an unknown trigger")
        }
        let responseTime: Double = try row.decode(forColumn: "responseTime")
        self.init(
            cardID: cardID,
            kind: kind,
            answeredAt: try row.decode(forColumn: "answeredAt"),
            responseTime: .seconds(responseTime),
            trigger: trigger,
            isAhead: try row.decode(forColumn: "isAhead")
        )
    }
}

extension ReviewLogEntry.Kind {
    /// The kind of entry that the `reviewLog` table's `kind` and `rating`
    /// columns name, or nil when this version of Ficha doesn't know it.
    fileprivate init?(kind: String, rating: String?) {
        switch (kind, rating) {
        case ("firstView", nil):
            self = .firstView
        case ("review", let rating?):
            guard let rating = Rating(rawValue: rating) else {
                return nil
            }
            self = .review(rating)
        default:
            return nil
        }
    }

    /// The values of the `reviewLog` table's `kind` and `rating` columns
    /// that name this kind of entry.
    fileprivate var columns: (kind: String, rating: String?) {
        switch self {
        case .firstView: ("firstView", nil)
        case .review(let rating): ("review", rating.rawValue)
        }
    }
}
