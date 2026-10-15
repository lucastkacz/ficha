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
    /// The Mac or its screens are asleep.
    case asleep
    /// It's outside active hours.
    case outsideActiveHours
    /// The last appearance or review now closed less than the separation
    /// ago, so the next appearance waits until this time.
    case tooSoonAfterLastOne(until: Date)
    /// The Mac or its screens woke a moment ago, so an appearance waits until
    /// this time.
    case tooSoonAfterWaking(until: Date)
    /// No card is due, and no new card may come in.
    case nothingDue
}

extension NoAppearance {
    /// When an appearance may come, when it's known: once the separation, or
    /// the wait after waking, is over.
    public var until: Date? {
        switch self {
        case .tooSoonAfterLastOne(let until), .tooSoonAfterWaking(let until): until
        case .asleep, .outsideActiveHours, .nothingDue: nil
        }
    }
}

extension ReviewSettings {
    /// Whether the review panel shows up on its own at `now`, out of the cards
    /// in Lucas's reviews, neither flagged nor buried, by id in the order he
    /// approved them, the whole review log, in the order it was written, when
    /// the last appearance or review now closed, if any did, and what `mac`
    /// says. While the Mac and its screens are awake, within active hours, by
    /// `calendar`'s clock, and once `separation` has passed since that closing
    /// and `waitAfterWaking` since the Mac woke, it shows up once a card is
    /// due, or, with nothing due, once a new card may come in. It brings the
    /// cards review now would, along with those due within `lookAhead`.
    public func appearance(
        cardIDs: [Int64],
        log: [ReviewLogEntry],
        lastClosing: Date?,
        mac: some MacSignals,
        now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> AppearancePlan {
        guard !mac.isAsleep else {
            return .notNow(.asleep)
        }
        guard activeHours.contains(calendar.component(.hour, from: now)) else {
            return .notNow(.outsideActiveHours)
        }
        if let until = lastClosing?.adding(separation), now < until {
            return .notNow(.tooSoonAfterLastOne(until: until))
        }
        if let until = mac.lastWake?.adding(waitAfterWaking), now < until {
            return .notNow(.tooSoonAfterWaking(until: until))
        }
        let standings = try ladder.standings(of: cardIDs, after: log)
        let picked = pickCards(after: standings, log: log, dueBy: now.adding(lookAhead), now: now, calendar: calendar)
        let isAnyCardDue = standings.contains { $0.standing.isDue(at: now) }
        guard isAnyCardDue || picked.firstView != nil else {
            return .notNow(.nothingDue)
        }
        return .show(picked)
    }
}
