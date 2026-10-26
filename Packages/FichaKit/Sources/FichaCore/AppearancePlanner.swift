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
/// shows up on its own, with which cards, each by id and the way it shows, or
/// why not (ADR 0003).
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

/// An appearance planned ahead, as the iPhone schedules it (ADR 0010): when it
/// comes, and the cards it brings, each by id and the way it shows.
public struct PlannedAppearance: Sendable, Equatable {
    public let time: Date
    public let cardIDs: PanelCardIDs
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
    /// Whether the review panel shows up on its own at `now`, out of `cards`,
    /// given when the last appearance or review now closed, if any did, and
    /// what `signals` says of the device. While it's awake, within active
    /// hours, by `calendar`'s clock, and once `separation` has passed since
    /// that closing and `waitAfterWaking` since the device woke, it shows up
    /// once a card is due, or, with nothing due, once a new card may come in
    /// as it would without priority tags, which never move an appearance,
    /// unless one of `suppressionsThatApply` holds it back, or one of them
    /// ended less than `waitAfterSuppression` ago. It brings the cards review
    /// now would, along with those due within `lookAhead`.
    public func appearance(
        cards: CardsInReviews,
        lastClosing: Date?,
        signals: some DeviceSignals,
        now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> AppearancePlan {
        guard !signals.isAsleep else {
            return .notNow(.asleep)
        }
        guard activeHours.contains(calendar.component(.hour, from: now)) else {
            return .notNow(.outsideActiveHours)
        }
        if let until = lastClosing?.adding(separation), now < until {
            return .notNow(.tooSoonAfterLastOne(until: until))
        }
        if let until = signals.lastWake?.adding(waitAfterWaking), now < until {
            return .notNow(.tooSoonAfterWaking(until: until))
        }
        let standings = try cards.standings(on: ladder)
        let horizon = now.adding(lookAhead)
        let picked = pickCards(after: standings, of: cards, dueBy: horizon, now: now, calendar: calendar)
        let isAnyCardDue = standings.contains { $0.standing.isDue(at: now) }
        // Priority tags change which cards come, never when an appearance
        // does: a new priority card fits beside the cards due within the
        // look-ahead where another new card wouldn't, so whether a new card
        // may come in is asked as without them.
        let mayMeetNewCard =
            pickCards(after: standings, of: cards.withoutPriority, dueBy: horizon, now: now, calendar: calendar)
            .firstView != nil
        guard isAnyCardDue || mayMeetNewCard else {
            return .notNow(.nothingDue)
        }
        let applying = Suppression.allCases.filter(suppressionsThatApply.contains)
        if let suppression = applying.first(where: signals.suppressions.contains) {
            return .notNow(.suppressed(suppression))
        }
        if let lastEnd = applying.compactMap({ signals.suppressionEnds[$0] }).max(),
            case let until = lastEnd.adding(waitAfterSuppression), now < until
        {
            return .notNow(.tooSoonAfterSuppression(until: until))
        }
        return .show(picked)
    }

    /// The appearances that come from `now` on, as if Lucas rated nothing in
    /// between, up to `count`, for the iPhone to schedule as notifications
    /// (ADR 0010). Out of `cards`, given when the last appearance or review
    /// now closed, if any did. Walking time forward from `now`, each
    /// appearance comes at the first time `appearance` says it shows up, on a
    /// device that never holds one back, with the cards it says. Left alone, a
    /// planned appearance closes as it shows, and its cards stay as they were,
    /// so the next one comes once `separation` passed. The plan ends after
    /// `count`, or once no appearance would come without Lucas doing
    /// something.
    public func plannedAppearances(
        cards: CardsInReviews,
        lastClosing: Date?,
        from now: Date,
        calendar: Calendar,
        upTo count: Int
    ) throws(UnexpectedReviewLog) -> [PlannedAppearance] {
        // With nothing rated, the cards keep their due times, and a new card
        // waits for a day whose new cards Lucas hasn't met, if one ever comes
        // in: when none may, a new day changes nothing, and the plan ends.
        let standings = try cards.standings(on: ladder).map(\.standing)
        let dueTimes = standings.compactMap(\.due)
        let mayMeetNewCards = standings.contains(.new) && bringsNewCard(after: 0, metToday: 0)
        var plan: [PlannedAppearance] = []
        var lastClosing = lastClosing
        var next: Date? = now
        while plan.count < count, let time = next {
            switch try appearance(
                cards: cards, lastClosing: lastClosing, signals: PhoneSignals(), now: time, calendar: calendar)
            {
            case .show(let picked):
                plan.append(PlannedAppearance(time: time, cardIDs: picked))
                // Left alone, it closes as it shows.
                lastClosing = time
                next = time.adding(separation)
            case .notNow(.outsideActiveHours):
                next = startOfActiveHours(after: time, calendar: calendar)
            case .notNow(.nothingDue):
                var changes = dueTimes.filter { $0 > time }
                if mayMeetNewCards, let nextDay = calendar.dateInterval(of: .day, for: time)?.end {
                    changes.append(nextDay)
                }
                next = changes.min()
            case .notNow(let reason):
                next = reason.until
            }
        }
        return plan
    }

    /// The way that comes after `way` in an appearance on the iPhone, which
    /// brought the ways in `appearance`, in the order they show, once Lucas
    /// answered it from its card notification (ADR 0010): the first of the
    /// ways after it that he can still answer at `now`, out of `cards`. As in
    /// any appearance, a new way comes for its first view, and one due within
    /// `lookAhead` for a review, so one he rated meanwhile, or whose card left
    /// his reviews, is skipped. None comes once none is left.
    public func nextCard(
        after way: CardWay,
        in appearance: [CardWay],
        cards: CardsInReviews,
        now: Date
    ) throws(UnexpectedReviewLog) -> PanelCardIDs {
        let inReviews = Set(cards.ways)
        let later = appearance.drop { $0 != way }.dropFirst().filter(inReviews.contains)
        for (laterWay, standing) in try ladder.standings(of: later, after: cards.log) {
            switch standing {
            case .new:
                return PanelCardIDs(reviews: [], reviewsAhead: [], firstView: laterWay)
            case .onLadder where standing.isDue(at: now.adding(lookAhead)):
                return PanelCardIDs(reviews: [laterWay], reviewsAhead: [], firstView: nil)
            case .onLadder:
                continue
            }
        }
        return PanelCardIDs(reviews: [], reviewsAhead: [], firstView: nil)
    }

    /// When active hours start after `time`, a time outside them: the start
    /// of the next hour within them, by `calendar`'s clock, or nil when none
    /// of a day's hours is.
    private func startOfActiveHours(after time: Date, calendar: Calendar) -> Date? {
        var hour = time
        // A day has 25 hours at most, on the day the clock goes back.
        for _ in 0..<25 {
            guard let nextHour = calendar.dateInterval(of: .hour, for: hour)?.end else {
                return nil
            }
            if activeHours.contains(calendar.component(.hour, from: nextHour)) {
                return nextHour
            }
            hour = nextHour
        }
        return nil
    }
}

/// What the iPhone tells Ficha, which never holds an appearance back: waking,
/// idle time and suppressions don't apply there, and iOS's Focus silences
/// notifications on its own (#97).
private struct PhoneSignals: DeviceSignals {
    let isAsleep = false
    let lastWake: Date? = nil
    let idleTime: Duration? = nil
    let suppressions: Set<Suppression> = []
    let suppressionEnds: [Suppression: Date] = [:]
}
