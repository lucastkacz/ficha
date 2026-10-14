import Foundation
import Synchronization

/// Where logic gets the current time from.
///
/// Logic never reads `Date()` directly: it asks a `TimeSource`, so tests and the
/// app's debug menu can fix time and move it forward. (Named `TimeSource` and not
/// `Clock` so it doesn't clash with the standard library's `Clock`.)
public protocol TimeSource: Sendable {
    /// The current instant.
    var now: Date { get }
}

/// The real time, from the system.
public struct SystemTimeSource: TimeSource {
    public init() {}

    public var now: Date { Date() }
}

/// A time that only moves when told to: for tests and previews.
public final class ManualTimeSource: TimeSource {
    private let current: Mutex<Date>

    public init(now: Date) {
        current = Mutex(now)
    }

    public var now: Date {
        current.withLock { $0 }
    }

    /// Moves time forward (or back, with a negative interval).
    public func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

/// A time that runs like another one, ahead of it by however much it was
/// moved: Ficha Dev's time, which runs like the system's while its debug menu
/// moves it forward.
public final class ShiftedTimeSource: TimeSource {
    private let base: any TimeSource
    private let currentShift: Mutex<TimeInterval>

    /// A time `shift` ahead of `base` (or behind it, with a negative shift).
    public init(base: any TimeSource, shift: TimeInterval) {
        self.base = base
        currentShift = Mutex(shift)
    }

    public var now: Date {
        base.now.addingTimeInterval(shift)
    }

    /// How far ahead of its base it is.
    public var shift: TimeInterval {
        currentShift.withLock { $0 }
    }

    /// Moves time forward (or back, with a negative interval), and it keeps
    /// running from there.
    public func advance(by interval: TimeInterval) {
        currentShift.withLock { $0 += interval }
    }
}
