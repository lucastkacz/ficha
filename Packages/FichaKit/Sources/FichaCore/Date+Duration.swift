import Foundation

extension Date {
    /// The time `duration` after this one.
    public func adding(_ duration: Duration) -> Date {
        addingTimeInterval(duration.timeInterval)
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

    /// A span of `count` whole days, or nil when it has more seconds than
    /// Ficha counts with, as an interval from a file may.
    public static func days(exactly count: Int64) -> Duration? {
        let (seconds, overflows) = count.multipliedReportingOverflow(by: secondsInADay)
        return overflows ? nil : .seconds(seconds)
    }

    /// This span in seconds, as Foundation counts time, and as the database
    /// and iCloud keep an interval: exactly, for a span of whole seconds,
    /// which dividing it by a second isn't for one of days, whose
    /// attoseconds a double can't hold.
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }

    /// A span of `count` days, with their fraction.
    public init(days count: Double) {
        self = .seconds(count * Double(secondsInADay))
    }

    /// This span in days, with their fraction.
    public var inDays: Double {
        self / .days(1)
    }
}

/// The seconds in a day, as Ficha counts its days: 24 hours, whatever the
/// clocks do.
let secondsInADay: Int64 = 24 * 60 * 60
