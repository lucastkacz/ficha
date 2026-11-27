import FichaCore
import Foundation

// How the app says a finish date (ADR 0034, #491), as the mocks'
// `formatFinish` says it: within the week, by its days, and further on, by
// the thirds of their months. Which words is the window's decision, so
// FichaData works them out here, and the app's views write them from the
// String Catalog, with each day's weekday or month as the system's date
// formats name it, so no name is looked up by a number.

extension FinishDate {
    /// How the app says a finish date, from today: by its days when the
    /// latest is less than 7 days from today's start, and else by the third
    /// of its month each end falls in.
    public enum Wording: Sendable, Hashable {
        /// A day, as the app names it from today.
        public enum Day: Sendable, Hashable {
            case today
            case tomorrow
            /// Another day of the week, the start of it in the engine's
            /// calendar, which the app names by its weekday: "Friday".
            case weekday(Date)
        }

        /// The third of its month a day falls in: days 1 to 10 early, 11 to
        /// 20 mid, and 21 on late.
        public enum Third: Sendable, Hashable {
            case early
            case mid
            case late
        }

        /// A third of a month: "early December", "mid-December".
        public struct MonthThird: Sendable, Hashable {
            public let third: Third
            /// The day it's the third of, an end of the finish date, the
            /// start of it in the engine's calendar, which the app names by
            /// its month: "December".
            public let day: Date

            public init(_ third: Third, of day: Date) {
                self.third = third
                self.day = day
            }
        }

        /// One day, when soonest and latest are the same: "today",
        /// "tomorrow", "Friday".
        case day(Day)
        /// Two days in a row, joined by "or": "today or tomorrow", "Wednesday
        /// or Thursday".
        case dayOrNext(Day, Day)
        /// Two days further apart, joined by "to": "Wednesday to Saturday".
        case days(Day, to: Day)
        /// Both ends in the same third of the same month: "early December",
        /// "mid-December".
        case third(MonthThird)
        /// Both ends in the same month, in two of its thirds: "early to
        /// mid-December".
        case thirds(Third, to: MonthThird)
        /// The ends in two months: "late November to early December".
        case months(MonthThird, to: MonthThird)

        /// Whether it starts with today, as "today" and "today or tomorrow"
        /// do: How fast? then says "all met today", and else "all met by
        /// mid-December".
        public var startsToday: Bool {
            switch self {
            case .day(let day), .dayOrNext(let day, _), .days(let day, _): day == .today
            case .third, .thirds, .months: false
            }
        }
    }

    /// How the app says this finish date on `now`'s day, by `calendar`, the
    /// engine's: when the latest day is less than 7 days from the start of
    /// today, one day when soonest and latest are the same day, and else both
    /// ends, joined by "or" when they're one day apart and by "to" otherwise;
    /// and else each end by the third of its month it falls in, one third
    /// when both are in the same one, two of one month, or two months.
    public func wording(now: Date, calendar: Calendar) -> Wording {
        let today = calendar.startOfDay(for: now)
        let daysFromToday = { (date: Date) in
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        }
        let fromToday = daysFromToday(soonest)
        let toToday = daysFromToday(latest)
        guard toToday >= 7 else {
            let first = Wording.Day(soonest, daysFromToday: fromToday, in: calendar)
            let last = Wording.Day(latest, daysFromToday: toToday, in: calendar)
            if toToday <= fromToday {
                return .day(last)
            }
            return toToday - fromToday == 1 ? .dayOrNext(first, last) : .days(first, to: last)
        }
        let start = Wording.MonthThird(of: soonest, in: calendar)
        let end = Wording.MonthThird(of: latest, in: calendar)
        guard calendar.isDate(soonest, equalTo: latest, toGranularity: .month) else {
            return .months(start, to: end)
        }
        return start.third == end.third ? .third(end) : .thirds(start.third, to: end)
    }
}

extension FinishDate.Wording.Day {
    /// `date`, `days` days after today's, as the app names it, by `calendar`:
    /// today, or a day before, which a finish date never is, tomorrow, or
    /// its weekday.
    fileprivate init(_ date: Date, daysFromToday days: Int, in calendar: Calendar) {
        switch days {
        case ...0: self = .today
        case 1: self = .tomorrow
        default: self = .weekday(calendar.startOfDay(for: date))
        }
    }
}

extension FinishDate.Wording.MonthThird {
    /// The third of its month `date` falls in, by `calendar`.
    fileprivate init(of date: Date, in calendar: Calendar) {
        let third: FinishDate.Wording.Third =
            switch calendar.component(.day, from: date) {
            case ...10: .early
            case 11...20: .mid
            default: .late
            }
        self.init(third, of: calendar.startOfDay(for: date))
    }
}
