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
            let cards = try cardsThatShowUp(in: db)
            let picked = try settings.reviewNowCards(cards: cards.inReviews, now: now, calendar: calendar)
            return try cards.panelCards(picked)
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
        try write { db in
            try recordAnswer(
                kind, of: cardID, at: answeredAt, responseTime: responseTime, trigger: trigger, settings: settings,
                reviewingAhead: reviewingAhead, in: db)
        }
    }

    /// What the menu shows of Lucas's progress: how many cards in his reviews
    /// are due, how many he learned, and how many captures and flagged cards
    /// wait in the inbox.
    public func progress(_ settings: ReviewSettings) throws(EngineError) -> ProgressCounts {
        let now = time.now
        return try read { db in
            let counts = try settings.ladder.counts(of: cardsThatShowUp(in: db).inReviews, at: now)
            return ProgressCounts(
                due: counts.due, learned: counts.learned,
                inInbox: try capturesInInbox.fetchCount(db) + flaggedCardsWaiting(in: db).count)
        }
    }

    /// The cards "See more" brings once Lucas went through the review panel's
    /// cards, which `trigger` brought: the due cards that didn't fit, and then
    /// the cards closest to being due, as reviews ahead, out of the cards in
    /// his reviews but those in `shown`, the panel's. Never a new card. For an
    /// appearance, a card due within the look-ahead counts as due.
    func seeMoreCards(after shown: Set<Int64>, from trigger: Trigger, settings: ReviewSettings) throws(EngineError)
        -> [PanelCard]
    {
        let horizon = time.now.adding(trigger.lookAhead(in: settings))
        return try read { db in
            let cards = try cardsThatShowUp(in: db)
            let picked = try settings.seeMoreCards(cards: cards.inReviews, leavingOut: shown, dueBy: horizon)
            return try cards.panelCards(picked)
        }
    }

    /// Every first view, review and placement, in the order they happened.
    public func reviewLog() throws(EngineError) -> [ReviewLogEntry] {
        try read(logEntries(in:))
    }

    /// Where a card stands on `ladder`: new, or on a step until it's due,
    /// worked out from its review log, also while it's flagged, buried or set
    /// aside.
    public func standing(of cardID: Int64, on ladder: Ladder) throws(EngineError) -> LadderStanding {
        try read { db in
            try ladder.standing(after: logEntries(ofExisting: cardID, in: db))
        }
    }
}

/// The review log's entries, in the order they happened.
func logEntries(in db: Database) throws -> [ReviewLogEntry] {
    try Row.fetchAll(db, sql: "SELECT * FROM reviewLog ORDER BY id").map(ReviewLogEntry.init(row:))
}

/// A card's entries in the review log, in the order they happened, or an
/// error when there's no such card.
func logEntries(ofExisting cardID: Int64, in db: Database) throws -> [ReviewLogEntry] {
    guard try Row.fetchOne(db, sql: "SELECT id FROM card WHERE id = ?", arguments: [cardID]) != nil else {
        throw EngineError.cardNotFound(cardID)
    }
    return try Row.fetchAll(db, sql: "SELECT * FROM reviewLog WHERE cardId = ? ORDER BY id", arguments: [cardID])
        .map(ReviewLogEntry.init(row:))
}

/// Adds Lucas's answer to a card in his reviews, given at `answeredAt`, at the
/// end of the review log, as `Engine.record` says, with how long he took when
/// something measured it, or throws when the card can't take the answer.
func recordAnswer(
    _ kind: ReviewLogEntry.Kind,
    of cardID: Int64,
    at answeredAt: Date,
    responseTime: Duration?,
    trigger: Trigger,
    settings: ReviewSettings,
    reviewingAhead: Bool,
    in db: Database
) throws {
    let lookAhead = trigger.lookAhead(in: settings)
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

/// Adds `placement` to the review log of the card with this id, which an
/// import brings in at `placedAt` with its progress from another app, in
/// place of a first view (ADR 0013). The card has no entry yet: it's coming
/// in in the same write.
func place(_ cardID: Int64, on placement: Placement, at placedAt: Date, in db: Database) throws {
    try insert(ReviewLogEntry(placing: cardID, on: placement, at: placedAt), in: db)
}

/// Adds an entry at the end of the review log.
private func insert(_ entry: ReviewLogEntry, in db: Database) throws {
    let columns = entry.kind.columns
    try db.execute(
        sql: """
            INSERT INTO reviewLog (cardId, kind, rating, step, due, answeredAt, responseTime, trigger, isAhead)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            entry.cardID, columns.kind, columns.rating, columns.step, columns.due, entry.answeredAt,
            entry.responseTime.map { $0 / .seconds(1) }, entry.trigger?.rawValue, entry.isAhead,
        ]
    )
}

extension ReviewLogEntry {
    /// An entry read from a row of the `reviewLog` table.
    init(row: Row) throws {
        let cardID: Int64 = try row.decode(forColumn: "cardId")
        guard
            let kind = Kind(
                kind: try row.decode(forColumn: "kind"), rating: try row.decode(forColumn: "rating"),
                step: try row.decode(forColumn: "step"), due: try row.decode(forColumn: "due"))
        else {
            throw unreadable("Card \(cardID) has a review log entry of an unknown kind, rating or step")
        }
        let answeredAt: Date = try row.decode(forColumn: "answeredAt")
        let triggerName: String? = try row.decode(forColumn: "trigger")
        switch (kind, triggerName) {
        case (.placement(let placement), nil):
            self.init(placing: cardID, on: placement, at: answeredAt)
        case (.firstView, let triggerName?), (.review, let triggerName?):
            guard let trigger = Trigger(rawValue: triggerName) else {
                throw unreadable("Card \(cardID) has a review log entry with an unknown trigger")
            }
            let responseTime: Double? = try row.decode(forColumn: "responseTime")
            self.init(
                cardID: cardID,
                kind: kind,
                answeredAt: answeredAt,
                responseTime: responseTime.map { .seconds($0) },
                trigger: trigger,
                isAhead: try row.decode(forColumn: "isAhead")
            )
        case (.placement, _?), (.firstView, nil), (.review, nil):
            throw unreadable("Card \(cardID) has a review log entry whose trigger doesn't go with its kind")
        }
    }
}

extension ReviewLogEntry.Kind {
    /// The kind of entry that the `reviewLog` table's `kind`, `rating`,
    /// `step` and `due` columns name, or nil when this version of Ficha
    /// doesn't know it.
    fileprivate init?(kind: String, rating: String?, step: Int?, due: Date?) {
        switch (kind, rating, step, due) {
        case ("firstView", nil, nil, nil):
            self = .firstView
        case ("review", let rating?, nil, nil):
            guard let rating = Rating(rawValue: rating) else {
                return nil
            }
            self = .review(rating)
        case ("placement", nil, let step?, let due?):
            self = .placement(Placement(step: step, due: due))
        default:
            return nil
        }
    }

    /// The values of the `reviewLog` table's `kind`, `rating`, `step` and
    /// `due` columns that name this kind of entry.
    fileprivate var columns: (kind: String, rating: String?, step: Int?, due: Date?) {
        switch self {
        case .firstView: ("firstView", nil, nil, nil)
        case .review(let rating): ("review", rating.rawValue, nil, nil)
        case .placement(let placement): ("placement", nil, placement.step, placement.due)
        }
    }
}
