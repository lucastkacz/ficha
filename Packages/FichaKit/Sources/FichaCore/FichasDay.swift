import Foundation

/// Ficha's day (ADR 0045): from an hour of a calendar's clock, 4:00 unless
/// the user sets another (`ReviewSettings.dayStartsAtHour`), to the same hour
/// the next day, as Anki's "Next day starts at" counts, so that a night that
/// crosses midnight is one day. The new cards a day, the finish date and the
/// days Ficha names count by it; a card's due time doesn't.
extension Calendar {
    /// When Ficha's day that `time` is in started, for a day that starts at
    /// the hour `hour`, from 0 to 23: that hour of `time`'s calendar day, or
    /// of the one before when `time` comes before it.
    public func startOfFichasDay(for time: Date, startingAt hour: Int) -> Date {
        let calendarDay = startOfDay(for: time)
        let start = date(atHour: hour, of: calendarDay)
        guard time < start else {
            return start
        }
        return date(atHour: hour, of: startOfDay(for: calendarDay.addingTimeInterval(-1)))
    }

    /// When the Ficha's day after the one `time` is in starts, for a day that
    /// starts at the hour `hour`: that hour of the calendar day after the one
    /// it started on.
    public func startOfNextFichasDay(after time: Date, startingAt hour: Int) -> Date {
        let startDay = calendarDay(ofFichasDayOf: time, startingAt: hour)
        // Noon of the next calendar day, give or take the hour the clock
        // moves, since a calendar day lasts 23 to 25 hours.
        let nextCalendarDay = startOfDay(for: startDay.addingTimeInterval(36 * 60 * 60))
        return date(atHour: hour, of: nextCalendarDay)
    }

    /// The calendar day that Ficha's day `time` is in started on, as its
    /// start: the day the finish date and the days Ficha names count from, so
    /// at 2:00 on a Thursday, with the day starting at 4:00, "today" is
    /// Wednesday.
    public func calendarDay(ofFichasDayOf time: Date, startingAt hour: Int) -> Date {
        startOfDay(for: startOfFichasDay(for: time, startingAt: hour))
    }

    /// Whether `time` and `other` are in the same Ficha's day, for a day that
    /// starts at the hour `hour`.
    public func isDate(_ time: Date, inSameFichasDayAs other: Date, startingAt hour: Int) -> Bool {
        startOfFichasDay(for: time, startingAt: hour) == startOfFichasDay(for: other, startingAt: hour)
    }

    /// The hour `hour` of the calendar day that starts at `day`, by this
    /// calendar's clock.
    private func date(atHour hour: Int, of day: Date) -> Date {
        // Foundation finds a time for every hour of a day, the next one when
        // the clock skips it; the hours added are for a calendar it doesn't.
        date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day.addingTimeInterval(Double(hour) * 60 * 60)
    }
}
