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

/// A time that only moves when told to: for tests, previews and the debug menu.
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
