import Foundation

extension Date {
    /// The time `duration` after this one.
    public func adding(_ duration: Duration) -> Date {
        addingTimeInterval(duration.timeInterval)
    }

    /// The days from `earlier` to this time, with their fraction: negative
    /// when `earlier` comes after it.
    func days(since earlier: Date) -> Double {
        timeIntervalSince(earlier) / Duration.days(1).timeInterval
    }
}

extension Duration {
    /// A span of whole minutes.
    static func minutes(_ count: Int64) -> Duration {
        .seconds(count * 60)
    }

    /// A span of whole hours.
    static func hours(_ count: Int64) -> Duration {
        .seconds(count * 60 * 60)
    }

    /// A span of whole days.
    static func days(_ count: Int64) -> Duration {
        .seconds(count * secondsInADay)
    }

    /// This span in seconds, as Foundation counts time, and as the database
    /// and iCloud keep an interval: exactly, for a span of whole seconds,
    /// which dividing it by a second isn't for one of days, whose
    /// attoseconds a double can't hold.
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }

    /// This span in days, with their fraction.
    var inDays: Double {
        self / .days(1)
    }

    /// Whether this span is a whole number of days, one at least, as a
    /// graduated interval always is.
    var isWholeDays: Bool {
        let (seconds, attoseconds) = components
        return seconds >= secondsInADay && seconds % secondsInADay == 0 && attoseconds == 0
    }
}

/// The seconds in a day, as Ficha counts its days: 24 hours, whatever the
/// clocks do.
private let secondsInADay: Int64 = 24 * 60 * 60
