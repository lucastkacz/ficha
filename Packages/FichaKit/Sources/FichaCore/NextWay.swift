import Foundation

/// What the widget shows of the cards in Lucas's reviews at a time (#171):
/// the way review now would start with, or when the next one comes.
public enum NextWay: Sendable, Equatable {
    /// The way review now would start with: the first due way, or else the
    /// new way, for its first view.
    case waiting(CardWay, isNew: Bool)
    /// No way waits, and the next one comes at this time.
    case comesAt(Date)
    /// No way waits, and none comes as time passes: Lucas has to do
    /// something first, such as approve cards or set a tag aside no longer.
    case noneComing
}

/// What the widget shows from a time on, as if Lucas rated nothing in
/// between: an entry at that time, and one at each later time what it shows
/// changes, as WidgetKit asks of a timeline it can predict.
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
    /// The least time between two entries of the widget's timeline: WidgetKit
    /// asks for entries "at least about 5 minutes apart" ("Keeping a widget
    /// up to date"), so what changes sooner after an entry shows 5 minutes
    /// after it.
    public static let widgetEntrySpacing: TimeInterval = 5 * 60
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
    /// day's new cards, as the day changes.
    public func nextWayTimeline(
        cards: CardsInReviews,
        from now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> NextWayTimeline {
        let standings = try cards.standings(on: ladder)
        let changes = WidgetChanges(
            dueTimes: standings.compactMap(\.standing.due),
            newWaysComeEachDay: standings.contains { $0.standing == .new } && bringsNewCard(after: 0, metToday: 0),
            calendar: calendar)
        func nextWay(at time: Date) -> NextWay {
            let picked = pickCards(after: standings, of: cards, dueBy: time, now: time, calendar: calendar)
            if let due = picked.reviews.first {
                return .waiting(due, isNew: false)
            }
            if let new = picked.firstView {
                return .waiting(new, isNew: true)
            }
            return changes.first(after: time).map(NextWay.comesAt) ?? .noneComing
        }
        var entries = [NextWayTimeline.Entry(date: now, nextWay: nextWay(at: now))]
        var time = now
        for _ in 0..<Self.mostWidgetLooks {
            guard let change = changes.first(after: time), let last = entries.last else {
                return NextWayTimeline(entries: entries, refreshAt: nil)
            }
            time = max(change, last.date.addingTimeInterval(Self.widgetEntrySpacing))
            let shown = nextWay(at: time)
            if shown != last.nextWay {
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
/// due, and as the day changes, when new ways come each day.
private struct WidgetChanges {
    /// When each way on the ladder is due, in order, each time once.
    let dueTimes: [Date]
    /// Whether new ways wait, which the day's new cards bring in.
    let newWaysComeEachDay: Bool
    let calendar: Calendar

    init(dueTimes: [Date], newWaysComeEachDay: Bool, calendar: Calendar) {
        self.dueTimes = Set(dueTimes).sorted()
        self.newWaysComeEachDay = newWaysComeEachDay
        self.calendar = calendar
    }

    /// The first time after `time` that what the widget shows may change, or
    /// nil when it no longer changes on its own.
    func first(after time: Date) -> Date? {
        let nextDue = dueTimes.first { $0 > time }
        let nextDay = newWaysComeEachDay ? calendar.dateInterval(of: .day, for: time)?.end : nil
        return [nextDue, nextDay].compactMap(\.self).min()
    }
}
