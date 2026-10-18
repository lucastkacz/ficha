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
    /// back goes into the appearance log, once: checked again, it's the same
    /// appearance until the panel shows.
    public func checkAppearance(_ settings: ReviewSettings, mac: some MacSignals) throws(EngineError)
        -> AppearanceDecision
    {
        let decision = try decideAppearance(settings, mac: mac)
        if case .notNow(.suppressed(let suppression)) = decision {
            try recordHeldBack(by: suppression)
        }
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
                db, sql: "SELECT closedAt FROM appearanceLog WHERE outcome != 'heldBack' ORDER BY id DESC LIMIT 1")
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
    /// order the review panel closed.
    public func appearanceLog() throws(EngineError) -> [AppearanceLogEntry] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM appearanceLog ORDER BY id").map(AppearanceLogEntry.init(row:))
        }
    }

    /// Records an appearance or a review now in the appearance log as the
    /// review panel closes: what opened it, when it showed and how it closed.
    /// The next appearance waits from now.
    func recordClosing(of trigger: Trigger, shownAt: Date, outcome: AppearanceLogEntry.Outcome) throws(EngineError) {
        let closedAt = time.now
        try write { db in
            try insert(
                AppearanceLogEntry(trigger: trigger, shownAt: shownAt, closedAt: closedAt, outcome: outcome), in: db)
        }
    }

    /// Records an appearance that `suppression` holds back now in the
    /// appearance log, unless it's already there: unless the last entry is an
    /// appearance held back, which no panel has closed after.
    private func recordHeldBack(by suppression: Suppression) throws(EngineError) {
        let heldBackAt = time.now
        try write { db in
            let last = try String.fetchOne(db, sql: "SELECT outcome FROM appearanceLog ORDER BY id DESC LIMIT 1")
            guard last != "heldBack" else { return }
            try insert(
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: heldBackAt, closedAt: heldBackAt, outcome: .heldBack(suppression)),
                in: db)
        }
    }
}

/// Adds an entry at the end of the appearance log.
private func insert(_ entry: AppearanceLogEntry, in db: Database) throws {
    let (outcome, heldBackBy) = entry.outcome.columns
    try db.execute(
        sql: "INSERT INTO appearanceLog (trigger, shownAt, closedAt, outcome, heldBackBy) VALUES (?, ?, ?, ?, ?)",
        arguments: [entry.trigger.rawValue, entry.shownAt, entry.closedAt, outcome, heldBackBy]
    )
}
