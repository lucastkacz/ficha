import Foundation

/// What the appearance planner decides at a moment: whether the review panel
/// shows up on its own, with which cards, by id, or why not (ADR 0003).
public enum AppearancePlan: Sendable, Equatable {
    /// The panel shows up now with these cards.
    case show(PanelCardIDs)
    /// It doesn't show up now, for this reason.
    case notNow(NoAppearance)
}

/// Why the review panel doesn't show up on its own at a moment.
public enum NoAppearance: Sendable, Equatable {
    /// It's outside active hours.
    case outsideActiveHours
    /// The last appearance or review now closed less than the separation
    /// ago, so the next appearance waits until this time.
    case tooSoonAfterLastOne(until: Date)
    /// The Mac woke a moment ago, so an appearance waits until this time.
    case tooSoonAfterWaking(until: Date)
    /// No card is due, and no new card may come in.
    case nothingDue
}

extension ReviewSettings {
    /// Whether the review panel shows up on its own at `now`, out of every
    /// card, by id in the order Lucas approved them, the whole review log, in
    /// the order it was written, when the last appearance or review now
    /// closed, if any did, and when the Mac last woke, if it slept. Within
    /// active hours, by `calendar`'s clock, once `separation` has passed
    /// since that closing and `waitAfterWaking` since the Mac woke, it shows
    /// up once a card is due, or, with nothing due, once a new card may come
    /// in. It brings the cards review now would, along with those due within
    /// `lookAhead`.
    public func appearance(
        cardIDs: [Int64],
        log: [ReviewLogEntry],
        lastClosing: Date?,
        lastWake: Date?,
        now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> AppearancePlan {
        guard activeHours.contains(calendar.component(.hour, from: now)) else {
            return .notNow(.outsideActiveHours)
        }
        if let lastClosing, now < lastClosing + separation / .seconds(1) {
            return .notNow(.tooSoonAfterLastOne(until: lastClosing + separation / .seconds(1)))
        }
        if let lastWake, now < lastWake + waitAfterWaking / .seconds(1) {
            return .notNow(.tooSoonAfterWaking(until: lastWake + waitAfterWaking / .seconds(1)))
        }
        let standings = try ladder.standings(of: cardIDs, after: log)
        let cards = panelCards(
            after: standings, log: log, dueBy: now + lookAhead / .seconds(1), now: now, calendar: calendar)
        let isAnyCardDue = standings.contains { $0.standing.isDue(at: now) }
        guard isAnyCardDue || cards.firstView != nil else {
            return .notNow(.nothingDue)
        }
        return .show(cards)
    }
}
