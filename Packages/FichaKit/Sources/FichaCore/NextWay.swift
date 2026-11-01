import Foundation

/// What the widget shows of the cards in Lucas's reviews at a time (#171):
/// the way review now would start with, or when the next one comes.
public enum NextWay: Sendable, Equatable {
    /// The way review now would start with: the first due way, or else the
    /// new way, for its first review.
    case waiting(CardWay, isNew: Bool)
    /// No way waits, and the next one comes at this time.
    case comesAt(Date)
    /// No way waits, and none comes as time passes: Lucas has to do
    /// something first, such as approve cards or set a deck aside no longer.
    case noneComing
}

/// What the widget shows from a time on, as if Lucas rated nothing in
/// between: an entry at that time, and one at the very time what it shows
/// changes, each time it does. WidgetKit takes them at least 5 minutes apart,
/// which the widget's own timeline sees to.
public struct NextWayTimeline: Sendable, Equatable {
    /// What the widget shows from a time on, until the next entry.
    public struct Entry: Sendable, Equatable {
        public let date: Date
        public let nextWay: NextWay
    }

    /// The entries, the first at the time the timeline starts.
    public let entries: [Entry]
    /// When to work the timeline out again, as it stopped before what the
    /// widget shows stops changing, or nil when only a change to the cards
    /// changes it.
    public let refreshAt: Date?
}

extension ReviewSettings {
    /// The most entries the widget's timeline has, and the most times it
    /// looks at, so the widget's extension works it out in a moment, however
    /// many cards Lucas has: a timeline that stops at them is worked out again
    /// from where it stopped.
    static let mostWidgetEntries = 30
    static let mostWidgetLooks = 200

    /// What the widget shows from `now` on, out of `cards`, by `calendar`'s
    /// days, as `NextWayTimeline` says: the way review now would start with,
    /// as `pickCards` picks it, or when the next way comes. What it shows
    /// changes only as a way comes due, and, while new ways wait for the next
    /// day's new cards, at the next midnight.
    public func nextWayTimeline(
        cards: CardsInReviews,
        from now: Date,
        calendar: Calendar
    ) throws(SchedulingError) -> NextWayTimeline {
        let standings = try cards.standings(with: scheduler)
        let newWaysWait = standings.contains { $0.standing == .new } && bringsNewCard(after: 0, metToday: 0)
        let changes = WidgetChanges(
            dueTimes: standings.compactMap(\.standing.due),
            nextDay: newWaysWait ? calendar.dateInterval(of: .day, for: now)?.end : nil)
        func nextWay(at time: Date) -> NextWay {
            let picked = pickCards(after: standings, of: cards, dueBy: time, now: time, calendar: calendar)
            if let due = picked.reviews.first {
                return .waiting(due, isNew: false)
            }
            if let new = picked.newWay {
                return .waiting(new, isNew: true)
            }
            return changes.first(after: time).map(NextWay.comesAt) ?? .noneComing
        }
        var entries = [NextWayTimeline.Entry(date: now, nextWay: nextWay(at: now))]
        var time = now
        for _ in 0..<Self.mostWidgetLooks {
            guard let change = changes.first(after: time) else {
                return NextWayTimeline(entries: entries, refreshAt: nil)
            }
            time = change
            let shown = nextWay(at: time)
            if shown != entries.last?.nextWay {
                entries.append(NextWayTimeline.Entry(date: time, nextWay: shown))
                if entries.count == Self.mostWidgetEntries {
                    break
                }
            }
        }
        return NextWayTimeline(entries: entries, refreshAt: time)
    }
}

/// The times what the widget shows may change on its own: as a way comes
/// due, and at the next midnight, when new ways wait for the next day's new
/// cards. Only that midnight: from then on Lucas has met no new card on any
/// day, since the timeline has him rate nothing, so the days after it change
/// nothing.
private struct WidgetChanges {
    /// When each started way is due, in order, each time once.
    let dueTimes: [Date]
    /// The next midnight, when new ways wait, or nil.
    let nextDay: Date?

    init(dueTimes: [Date], nextDay: Date?) {
        self.dueTimes = Set(dueTimes).sorted()
        self.nextDay = nextDay
    }

    /// The first time after `time` that what the widget shows may change, or
    /// nil when it no longer changes on its own.
    func first(after time: Date) -> Date? {
        let nextDue = dueTimes.first { $0 > time }
        let nextDay = nextDay.flatMap { $0 > time ? $0 : nil }
        return [nextDue, nextDay].compactMap(\.self).min()
    }
}
