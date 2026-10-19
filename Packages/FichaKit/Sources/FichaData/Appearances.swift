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
    public func checkAppearance(_ settings: ReviewSettings, mac: some MacSignals) throws(EngineError)
        -> AppearanceDecision
    {
        let decision = try decideAppearance(settings, mac: mac)
        try noteHold(as: decision)
        return decision
    }

    /// Whether the review panel shows up on its own now, as
    /// `checkAppearance` says.
    private func decideAppearance(_ settings: ReviewSettings, mac: some MacSignals) throws(EngineError)
        -> AppearanceDecision
    {
        let now = time.now
        return try read { db in
            let cards = try cardsInReviews(in: db)
            // A held-back appearance never showed, so it never closed.
            let lastClosing = try Date.fetchOne(
                db, sql: "SELECT closedAt FROM appearanceLog WHERE outcome != ? ORDER BY id DESC LIMIT 1",
                arguments: [OutcomeName.heldBack.rawValue])
            switch try settings.appearance(
                cardIDs: cards.map(\.id), log: logEntries(in: db), lastClosing: lastClosing, mac: mac, now: now,
                calendar: calendar)
            {
            case .show(let picked):
                return .show(try panelCards(picked, from: cards))
            case .notNow(let reason):
                return .notNow(reason)
            }
        }
    }

    /// Every appearance, and every review now that brought cards, in the
    /// order the review panel closed, and every appearance a suppression held
    /// back, as its hold started.
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
