import FichaCore
import Foundation

// How the app says a finish date (ADR 0034, #491), as the mocks'
// `formatFinish` says it: within the week, by its days, and further on, by
// the thirds of their months. Which words is the window's decision, so
// FichaData works them out here, and the app's views write them from the
// String Catalog, with the month and weekday names of the system's
// formatters.

extension FinishDate {
    /// How the app says a finish date, from today: by its days when the
    /// latest is less than 7 days from today's start, and else by the third
    /// of its month each end falls in.
    public enum Wording: Sendable, Hashable {
        /// A day, as the app names it from today.
        public enum Day: Sendable, Hashable {
            case today
            case tomorrow
            /// Another day of the week, by its number in the engine's
            /// calendar, as `Calendar.Component.weekday` counts them: 1 for
            /// Sunday to 7 for Saturday.
            case weekday(Int)
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
            /// The month, by its number in the engine's calendar: 1 for
            /// January to 12 for December.
            public let month: Int

            public init(_ third: Third, month: Int) {
                self.third = third
                self.month = month
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
    }

    /// How the app says this finish date on `now`'s day, by `calendar`, the
    /// engine's: when the latest day is less than 7 days from the start of
    /// today, one day when soonest and latest are the same day, and else both
    /// ends, joined by "or" when they're one day apart and by "to" otherwise;
    /// and else each end by the third of its month it falls in, one third
    /// when both are in the same one, two of one month, or two months.
    /// Not worked out yet (#491): every finish date reads as today.
    public func wording(now: Date, calendar: Calendar) -> Wording {
        .day(.today)
    }
}
