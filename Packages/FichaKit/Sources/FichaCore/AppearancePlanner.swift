import Foundation

/// A situation in which Ficha holds appearances back so as not to interrupt
/// Lucas. Each raw value is how the appearance log names it.
public enum Suppression: String, CaseIterable, Sendable {
    /// A meeting: the camera or the microphone is in use.
    case meeting
    /// A video is playing.
    case video
    /// The app in front is in full screen.
    case fullScreen
}

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
    /// An appearance would show up, but this suppression holds it back: the
    /// first of those on, in `Suppression`'s order, when there are several.
    case suppressed(Suppression)
    /// A suppression ended a moment ago, so an appearance waits until this
    /// time.
    case tooSoonAfterSuppression(until: Date)
}

extension NoAppearance {
    /// When an appearance may come, when it's known: once the separation, or
    /// the wait after waking or after a suppression, is over.
    public var until: Date? {
        switch self {
        case .tooSoonAfterLastOne(let until), .tooSoonAfterWaking(let until), .tooSoonAfterSuppression(let until):
            until
        case .asleep, .outsideActiveHours, .nothingDue, .suppressed: nil
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
    /// due, or, with nothing due, once a new card may come in, unless one of
    /// `suppressionsThatApply` holds it back, or one of them ended less than
    /// `waitAfterSuppression` ago. It brings the cards review now would, along
    /// with those due within `lookAhead`.
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
        let applying = Suppression.allCases.filter(suppressionsThatApply.contains)
        if let suppression = applying.first(where: mac.suppressions.contains) {
            return .notNow(.suppressed(suppression))
        }
        if let lastEnd = applying.compactMap({ mac.suppressionEnds[$0] }).max(),
            case let until = lastEnd.adding(waitAfterSuppression), now < until
        {
            return .notNow(.tooSoonAfterSuppression(until: until))
        }
        return .show(picked)
    }
}
