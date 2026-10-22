import FichaCore
import Foundation
internal import GRDB

/// What the engine decides at a moment: whether the review panel shows up on
/// its own, with which cards, or why not (ADR 0003).
public enum AppearanceDecision: Sendable, Equatable {
    /// The panel shows up now with these cards, in this order.
    case show([PanelCard])
    /// It doesn't show up now, for this reason.
    case notNow(NoAppearance)
}

extension Engine {
    /// Whether the review panel shows up on its own now, by what `mac` says,
    /// and with which cards, or why not. An appearance a suppression holds
    /// back goes into the appearance log once, as the hold starts: checked
    /// again while a suppression, or the wait after one, goes on, it's the
    /// same appearance. Its hold ends, in its entry, at the first check that
    /// decides anything else: the panel shows, or it can't come any more.
    public func checkAppearance(_ settings: ReviewSettings, mac: some DeviceSignals) throws(EngineError)
        -> AppearanceDecision
    {
        let decision = try decideAppearance(settings, mac: mac)
        try noteHold(as: decision)
        return decision
    }

    /// Whether the review panel shows up on its own now, as
    /// `checkAppearance` says.
    private func decideAppearance(_ settings: ReviewSettings, mac: some DeviceSignals) throws(EngineError)
        -> AppearanceDecision
    {
        let now = time.now
        return try read { db in
            let cards = try cardsInReviews(in: db)
            switch try settings.appearance(
                cardIDs: cards.map(\.id), log: logEntries(in: db), lastClosing: lastClosing(in: db), signals: mac,
                now: now, calendar: calendar)
            {
            case .show(let picked):
                return .show(try panelCards(picked, from: cards))
            case .notNow(let reason):
                return .notNow(reason)
            }
        }
    }

    /// Every appearance, and every review now that brought cards, and every
    /// appearance a suppression held back, in the order each went in: as the
    /// review panel closed; on the iPhone, at Lucas's first answer from one of
    /// its card notifications or as he swiped one away, or, when he never
    /// touched them, the next time the engine planned; or as its hold
    /// started.
    public func appearanceLog() throws(EngineError) -> [AppearanceLogEntry] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM appearanceLog ORDER BY id").map(AppearanceLogEntry.init(row:))
        }
    }

    /// Records an appearance or a review now in the appearance log as the
    /// review panel closes: what opened it, when it showed and how it closed.
    /// A hold that was on ended as the panel showed. The next appearance
    /// waits from now.
    func recordClosing(of trigger: Trigger, shownAt: Date, outcome: AppearanceLogEntry.Outcome) throws(EngineError) {
        let closedAt = time.now
        try write { db in
            if let hold = try holdThatIsOn(in: db) {
                try db.execute(sql: "UPDATE appearanceLog SET closedAt = ? WHERE id = ?", arguments: [shownAt, hold])
            }
            try insert(
                AppearanceLogEntry(trigger: trigger, shownAt: shownAt, closedAt: closedAt, outcome: outcome), in: db)
        }
    }

    /// Keeps the appearance log's holds as `decision` says: a hold starts
    /// when a suppression holds an appearance back and none is on, goes on
    /// through the suppression and the wait after it, and ends at any other
    /// decision. It writes only when a hold starts or ends.
    private func noteHold(as decision: AppearanceDecision) throws(EngineError) {
        let now = time.now
        let holdOn = try read(holdThatIsOn(in:))
        switch (decision, holdOn) {
        case (.notNow(.suppressed(let suppression)), nil):
            try write { db in
                try insert(
                    AppearanceLogEntry(
                        trigger: .appearance, shownAt: now, closedAt: now, outcome: .heldBack(suppression)),
                    in: db)
            }
        case (.notNow(.suppressed), _?), (.notNow(.tooSoonAfterSuppression), _):
            return
        case (_, let id?):
            try write { db in
                try db.execute(sql: "UPDATE appearanceLog SET closedAt = ? WHERE id = ?", arguments: [now, id])
            }
        case (_, nil):
            return
        }
    }
}

/// When the last appearance or review now closed, if any did, by the
/// appearance log: its latest closing, which on the iPhone may be an older
/// entry's, since an answer from a card notification left on the lock screen
/// moves its appearance's closing past later ones. A held-back appearance
/// never showed, so it never closed.
func lastClosing(in db: Database) throws -> Date? {
    try Date.fetchOne(
        db, sql: "SELECT closedAt FROM appearanceLog WHERE outcome != ? ORDER BY closedAt DESC LIMIT 1",
        arguments: [OutcomeName.heldBack.rawValue])
}

/// Notes in the appearance log that `appearance`, on the iPhone, closes at
/// `closedAt`, as Lucas answers one of its card notifications or swipes one
/// away: as finished once he went through its cards, and as a snooze
/// otherwise. The first adds its entry, and each one after it moves the
/// entry's closing on.
func noteClosing(of appearance: NotifiedAppearance, at closedAt: Date, finished: Bool, in db: Database) throws {
    let outcome: AppearanceLogEntry.Outcome = finished ? .finished : .snoozed
    guard let entry = try entryOfAppearance(shownAt: appearance.shownAt, in: db) else {
        try insert(
            AppearanceLogEntry(trigger: .appearance, shownAt: appearance.shownAt, closedAt: closedAt, outcome: outcome),
            in: db)
        return
    }
    try db.execute(
        sql: "UPDATE appearanceLog SET closedAt = ?, outcome = ? WHERE id = ?",
        arguments: [closedAt, outcome.columns.outcome, entry])
}

/// Notes in the appearance log, as snoozes, the appearances of the last plan
/// the engine handed out whose time came by `now` and that Lucas never
/// touched, which have no entry: none of their card notifications' answers
/// gave them one. Each closes as it showed, its cards left as they were
/// (#97).
func noteUntouchedAppearances(by now: Date, in db: Database) throws {
    let times = try Date.fetchAll(
        db, sql: "SELECT time FROM plannedAppearance WHERE time <= ? ORDER BY time", arguments: [now])
    for time in times where try entryOfAppearance(shownAt: time, in: db) == nil {
        try insert(AppearanceLogEntry(trigger: .appearance, shownAt: time, closedAt: time, outcome: .snoozed), in: db)
    }
}

/// The appearance log's entry of the appearance on the iPhone that showed at
/// `shownAt`, by its id, once it has one. An entry that showed within a
/// second of it is its own, since its card notifications carry the time in
/// seconds since 1970, which can come back a hair off, and the plan keeps it
/// as the database rounds it: a second is our own pick, far below any
/// separation.
private func entryOfAppearance(shownAt: Date, in db: Database) throws -> Int64? {
    try Int64.fetchOne(
        db,
        sql: """
            SELECT id FROM appearanceLog
            WHERE trigger = ? AND outcome != ? AND shownAt BETWEEN ? AND ?
            ORDER BY id DESC LIMIT 1
            """,
        arguments: [
            Trigger.appearance.rawValue, OutcomeName.heldBack.rawValue, shownAt.addingTimeInterval(-1),
            shownAt.addingTimeInterval(1),
        ])
}

/// The appearance log's hold that's on, by its entry's id, if one is: the
/// last entry, when it's an appearance held back whose hold hasn't ended, as
/// its closedAt still being its shownAt says.
private func holdThatIsOn(in db: Database) throws -> Int64? {
    guard
        let last = try Row.fetchOne(
            db, sql: "SELECT id, outcome, shownAt, closedAt FROM appearanceLog ORDER BY id DESC LIMIT 1"),
        try last.decode(forColumn: "outcome") as String == OutcomeName.heldBack.rawValue,
        try last.decode(forColumn: "shownAt") as Date == last.decode(forColumn: "closedAt") as Date
    else {
        return nil
    }
    return try last.decode(forColumn: "id")
}

/// Adds an entry at the end of the appearance log.
private func insert(_ entry: AppearanceLogEntry, in db: Database) throws {
    let (outcome, heldBackBy) = entry.outcome.columns
    try db.execute(
        sql: "INSERT INTO appearanceLog (trigger, shownAt, closedAt, outcome, heldBackBy) VALUES (?, ?, ?, ?, ?)",
        arguments: [entry.trigger.rawValue, entry.shownAt, entry.closedAt, outcome, heldBackBy]
    )
}
