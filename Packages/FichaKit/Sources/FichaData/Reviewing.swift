import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// The cards review now brings, each the way it shows, in the order the
    /// review panel shows them: the due ways, shortest interval first and
    /// then the longest overdue, and then a new way, when there's room and
    /// Lucas hasn't met the day's new cards yet. A click on the widget starts
    /// it with `first`, the card the widget showed, while review now brings
    /// it.
    public func reviewNow(_ settings: ReviewSettings, startingWith first: CardWay? = nil) throws(EngineError)
        -> [PanelCard]
    {
        let now = time.now
        return try read { db in
            let cards = try cardsThatShowUp(in: db)
            let picked = try settings.reviewNowCards(
                cards: cards.inReviews, now: now, calendar: calendar, startingWith: first)
            return try cards.panelCards(picked)
        }
    }

    /// Records Lucas's answer to one of the ways of a card in his reviews,
    /// front first unless it's said to go back first, in the review log: a
    /// review with his rating, which moves that way as the scheduler of
    /// `settings` says, keeping the interval its preview gives the rating.
    /// Each way moves on its own (ADR 0016). A new way takes any rating, in
    /// its first review, and a started way a review once it's due, or, in an
    /// appearance, once it's due within the look-ahead, which it brings
    /// along. When Lucas asked to review ahead, a review of a way that isn't
    /// due yet goes into the log marked as ahead, and counts as FSRS reckons
    /// it, from the time the way really waited; one of a way that came due by
    /// then is on time. It returns how many times he forgot the card that way
    /// when a lapse, a rating of again of a graduated way, makes it forgotten
    /// often, as `settings` say, each way counted apart, for the review panel
    /// to offer to flag it, or nil.
    @discardableResult
    public func record(
        _ kind: ReviewLogEntry.Kind,
        of cardID: Int64,
        way: Way = .frontFirst,
        responseTime: Duration,
        trigger: Trigger,
        settings: ReviewSettings,
        reviewingAhead: Bool = false
    ) throws(EngineError) -> ForgottenOften? {
        try record(
            kind, of: cardID, way: way, responseTime: responseTime, trigger: trigger, settings: settings,
            reviewingAhead: reviewingAhead, intervalsWorkedOutAt: nil)
    }

    /// Records Lucas's answer as `record(_:of:way:responseTime:trigger:settings:reviewingAhead:)`
    /// does, a review keeping the interval its rating would set as the
    /// scheduler works it out at `previewedAt`, when the review panel showed
    /// the intervals on its buttons (`ReviewPanelState.intervals`), or at the
    /// answer when it's nil.
    func record(
        _ kind: ReviewLogEntry.Kind,
        of cardID: Int64,
        way: Way,
        responseTime: Duration,
        trigger: Trigger,
        settings: ReviewSettings,
        reviewingAhead: Bool,
        intervalsWorkedOutAt previewedAt: Date?
    ) throws(EngineError) -> ForgottenOften? {
        let answeredAt = time.now
        return try write { db in
            try recordAnswer(
                kind, of: CardWay(cardID: cardID, way: way), at: answeredAt, responseTime: responseTime,
                trigger: trigger, settings: settings, reviewingAhead: reviewingAhead, intervalsWorkedOutAt: previewedAt,
                ids: ids, in: db)
        }
    }

    /// The interval each rating would set for a review of `cardWay`, a way
    /// of a card, at `time`, as the scheduler of `settings` works it out
    /// from that way's review log.
    func intervals(of cardWay: CardWay, at time: Date, settings: ReviewSettings) throws(EngineError)
        -> IntervalPreview
    {
        try read { db in
            let wayLog = try logEntries(ofExisting: cardWay.cardID, in: db).filter { $0.way == cardWay.way }
            return try settings.scheduler.preview(of: cardWay, after: wayLog, at: time)
        }
    }

    /// Takes back Lucas's last answer to one of a card's ways on this device,
    /// the last entry this device recorded in that way's review log, as the
    /// review panel's ⌘Z does: it leaves the log, as an answer undone never
    /// happened, the way Anki's undo deletes it too, and the way stands where
    /// it would without it, while the card's other way stays where it is. An
    /// answer another device synced since stays. When the way has no entry
    /// of this device left, nothing is taken back, and ⌘Z can't undo it.
    public func takeBackAnswer(of cardID: Int64, way: Way) throws(EngineError) {
        try write { db in
            try deleteLastEntry(of: CardWay(cardID: cardID, way: way), in: db)
        }
    }

    /// What the menu shows of Lucas's progress: how many ways of the cards in
    /// his reviews are due, how many of the cards he learned, and how many
    /// captures and flagged cards wait in the inbox.
    public func progress(_ settings: ReviewSettings) throws(EngineError) -> ProgressCounts {
        let now = time.now
        return try read { db in
            let counts = try settings.scheduler.counts(of: cardsThatShowUp(in: db).inReviews, at: now)
            return ProgressCounts(
                due: counts.due, learned: counts.learned,
                inInbox: try capturesInInbox.fetchCount(db) + flaggedCardsWaiting(in: db).count)
        }
    }

    /// The cards "See more" brings once Lucas went through the review panel's
    /// cards, which `trigger` brought: the due ways that didn't fit, and then
    /// the ways closest to being due, as reviews ahead, out of the ways in
    /// his reviews but those in `shown`, the panel's. Never a new way. For an
    /// appearance, a way due within the look-ahead counts as due.
    func seeMoreCards(after shown: Set<CardWay>, from trigger: Trigger, settings: ReviewSettings) throws(EngineError)
        -> [PanelCard]
    {
        let horizon = time.now.adding(trigger.lookAhead(in: settings))
        return try read { db in
            let cards = try cardsThatShowUp(in: db)
            let picked = try settings.seeMoreCards(cards: cards.inReviews, leavingOut: shown, dueBy: horizon)
            return try cards.panelCards(picked)
        }
    }

    /// Every review and placement, in the order this device recorded them:
    /// those another device synced come when they came, which needn't be
    /// when they happened.
    public func reviewLog() throws(EngineError) -> [ReviewLogEntry] {
        try read(logEntries(in:))
    }

    /// Where one of a card's ways stands with `scheduler`'s settings, front
    /// first unless it's said to go back first: new, or waiting its interval
    /// until it's due, worked out from that way's review log, also while the
    /// card is flagged, buried or set aside, or doesn't go both ways.
    public func standing(of cardID: Int64, way: Way = .frontFirst, with scheduler: Scheduler) throws(EngineError)
        -> WayStanding
    {
        try read { db in
            try scheduler.standing(after: logEntries(ofExisting: cardID, in: db).filter { $0.way == way })
        }
    }
}

/// The review log's entries, in the order this device recorded them, as
/// `Engine.reviewLog()` says.
func logEntries(in db: Database) throws -> [ReviewLogEntry] {
    try Row.fetchAll(db, sql: "SELECT * FROM reviewLog ORDER BY id").map(ReviewLogEntry.init(row:))
}

/// A card's entries in the review log, in the order this device recorded
/// them, or an error when there's no such card.
func logEntries(ofExisting cardID: Int64, in db: Database) throws -> [ReviewLogEntry] {
    guard try Row.fetchOne(db, sql: "SELECT id FROM card WHERE id = ?", arguments: [cardID]) != nil else {
        throw EngineError.cardNotFound(cardID)
    }
    return try Row.fetchAll(db, sql: "SELECT * FROM reviewLog WHERE cardId = ? ORDER BY id", arguments: [cardID])
        .map(ReviewLogEntry.init(row:))
}

/// Adds Lucas's answer to `answered`, one of the ways of a card in his
/// reviews, given at `answeredAt`, at the end of the review log, as
/// `Engine.record` says, with how long he took when something measured it,
/// and returns whether the card is now forgotten often that way, or throws
/// when the way can't take the answer. A review keeps the interval its
/// rating would set as the scheduler works it out at `previewedAt`, when the
/// review panel showed it, or else at `answeredAt`, and its ID comes from
/// `ids`. A back-first way takes
/// it also when the card no longer goes both ways, as when Lucas switched it
/// off while the review panel showed that way: the way keeps its progress
/// for when it's switched on again.
@discardableResult
func recordAnswer(
    _ kind: ReviewLogEntry.Kind,
    of answered: CardWay,
    at answeredAt: Date,
    responseTime: Duration?,
    trigger: Trigger,
    settings: ReviewSettings,
    reviewingAhead: Bool,
    intervalsWorkedOutAt previewedAt: Date? = nil,
    ids: any IDSource,
    in db: Database
) throws -> ForgottenOften? {
    let lookAhead = trigger.lookAhead(in: settings)
    let card = try cardInReviews(answered.cardID, in: db)
    let log = try logEntries(ofExisting: answered.cardID, in: db)
    let wayLog = log.filter { $0.way == answered.way }
    let scheduler = settings.scheduler
    let standing = try scheduler.standing(after: wayLog)
    let isAhead = reviewingAhead && standing.isReviewAhead(kind, at: answeredAt, lookingAhead: lookAhead)
    if !isAhead {
        do throws(RefusedAnswer) {
            try standing.check(kind, at: answeredAt, lookingAhead: lookAhead)
        } catch {
            throw EngineError(refused: error, cardID: answered.cardID)
        }
    }
    guard case .review(let rating) = kind else {
        throw EngineError(refused: .notAnAnswer, cardID: answered.cardID)
    }
    // A review answers the way's last entry, which its interval came from:
    // the last the scheduler replays, by when it was answered, not the last
    // written, which another device's or a clock set back can make an
    // earlier one. A new way's first review answers none.
    let answer = ReviewLogEntry(
        cardID: answered.cardID, way: answered.way, kind: kind, answeredAt: answeredAt, responseTime: responseTime,
        trigger: trigger, isAhead: isAhead, uuid: ids.newID(), answeredEntry: wayLog.max { $0.precedes($1) }?.uuid,
        interval: try scheduler.preview(of: answered, after: wayLog, at: previewedAt ?? answeredAt)[rating])
    try insert(answer, ids: ids, in: db)
    return try settings.forgottenOften(after: log + [answer], editedAt: card.editedAt)
}

/// Deletes the last entry this device recorded in the review log of
/// `cardWay`, one of a card's ways, which takes back Lucas's last answer to
/// it, as `Engine.takeBackAnswer` says, or throws when the way has none or
/// the card doesn't exist. An entry that came from another device since is
/// never taken back.
private func deleteLastEntry(of cardWay: CardWay, in db: Database) throws {
    _ = try existingCard(cardWay.cardID, in: db)
    try db.execute(
        sql: """
            DELETE FROM reviewLog WHERE id = (
                SELECT max(id) FROM reviewLog WHERE cardId = ? AND way = ? AND NOT isFromAnotherDevice)
            """,
        arguments: [cardWay.cardID, cardWay.way.rawValue]
    )
    guard db.changesCount == 1 else {
        throw EngineError.cannotUndo(cardWay.cardID)
    }
}

/// Adds an entry at the end of the review log, with its ID unique across
/// devices, or a new one from `ids` when it has none yet, the entry it
/// answered, and the interval it set, in seconds: a review's own, or a
/// placement's, with its due time and ease. A review keeps one: the table
/// refuses it without.
func insert(_ entry: ReviewLogEntry, ids: any IDSource, in db: Database) throws {
    let columns = entry.kind.columns
    try db.execute(
        sql: """
            INSERT INTO reviewLog (
                uuid, cardId, way, kind, rating, due, ease, answeredAt, responseTime, trigger, isAhead,
                answeredEntryUuid, interval)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            (entry.uuid ?? ids.newID()).uuidString, entry.cardID, entry.way.rawValue, columns.kind, columns.rating,
            columns.due, columns.ease, entry.answeredAt, entry.responseTime.map(\.timeInterval),
            entry.trigger?.rawValue, entry.isAhead, entry.answeredEntry?.uuidString,
            (columns.interval ?? entry.interval).map(\.timeInterval),
        ]
    )
}

extension ReviewLogEntry {
    /// An entry read from a row of the `reviewLog` table.
    init(row: Row) throws {
        let cardID: Int64 = try row.decode(forColumn: "cardId")
        guard let way = Way(rawValue: try row.decode(forColumn: "way")) else {
            throw unreadable("Card \(cardID) has a review log entry that went an unknown way")
        }
        let interval: Double? = try row.decode(forColumn: "interval")
        guard
            let kind = Kind(
                kind: try row.decode(forColumn: "kind"), rating: try row.decode(forColumn: "rating"),
                interval: interval.map { .seconds($0) }, due: try row.decode(forColumn: "due"),
                ease: try row.decode(forColumn: "ease"))
        else {
            throw unreadable(
                "Card \(cardID) has a review log entry of an unknown kind or rating, or a placement without its interval or due time"
            )
        }
        let answeredAt: Date = try row.decode(forColumn: "answeredAt")
        let uuidName: String = try row.decode(forColumn: "uuid")
        guard let uuid = UUID(uuidString: uuidName) else {
            throw unreadable("Card \(cardID) has a review log entry whose ID, \(uuidName), isn't a UUID")
        }
        let answeredEntryName: String? = try row.decode(forColumn: "answeredEntryUuid")
        let answeredEntry = try answeredEntryName.map { name in
            guard let answeredEntry = UUID(uuidString: name) else {
                throw unreadable(
                    "Card \(cardID)'s review log entry \(uuid) answered an entry, \(name), not named by a UUID")
            }
            return answeredEntry
        }
        let triggerName: String? = try row.decode(forColumn: "trigger")
        let trigger = try triggerName.map { name in
            guard let trigger = Trigger(rawValue: name) else {
                throw unreadable("Card \(cardID) has a review log entry with an unknown trigger")
            }
            return trigger
        }
        switch (kind, trigger) {
        case (.placement(let placement), nil):
            self.init(placing: cardID, way: way, on: placement, at: answeredAt, uuid: uuid)
        // A review with no trigger is one of Anki's, which an import brings
        // (#409), and nothing brought; the table allows it since
        // "v33 the scheduler replaces the ladder".
        case (.review, _):
            let responseTime: Double? = try row.decode(forColumn: "responseTime")
            self.init(
                cardID: cardID,
                way: way,
                kind: kind,
                answeredAt: answeredAt,
                responseTime: responseTime.map { .seconds($0) },
                trigger: trigger,
                isAhead: try row.decode(forColumn: "isAhead"),
                uuid: uuid,
                answeredEntry: answeredEntry,
                interval: interval.map { .seconds($0) }
            )
        case (.placement, _?):
            throw unreadable("Card \(cardID) has a placement in its review log with a trigger")
        }
    }
}

extension ReviewLogEntry.Kind {
    /// The kind of entry that the `reviewLog` table's `kind`, `rating`,
    /// `interval`, `due` and `ease` columns name, or nil when this version
    /// of Ficha doesn't know it, or a placement lacks its interval or due
    /// time.
    fileprivate init?(kind: String, rating: String?, interval: Duration?, due: Date?, ease: Double?) {
        switch (kind, rating, due) {
        case ("review", let rating?, nil):
            guard let rating = Rating(rawValue: rating), ease == nil else {
                return nil
            }
            self = .review(rating)
        case ("placement", nil, let due?):
            guard let interval else {
                return nil
            }
            self = .placement(Placement(interval: interval, due: due, ease: ease))
        default:
            return nil
        }
    }

    /// The values of the `reviewLog` table's `kind`, `rating`, `due` and
    /// `ease` columns that name this kind of entry, and, for a placement,
    /// its `interval`: a review's is the entry's own.
    fileprivate var columns: (kind: String, rating: String?, due: Date?, ease: Double?, interval: Duration?) {
        switch self {
        case .review(let rating): ("review", rating.rawValue, nil, nil, nil)
        case .placement(let placement): ("placement", nil, placement.due, placement.ease, placement.interval)
        }
    }
}
