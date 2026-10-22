import Synchronization
import Testing

/// A steady clock that moves only when a test moves it, for the review panel
/// to time Lucas on, as the app's continuous clock does.
final class ManualClock: Clock {
    /// An instant on the clock: how far it moved since it started.
    struct Instant: InstantProtocol {
        let offset: Swift.Duration

        func advanced(by duration: Swift.Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Swift.Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private let current = Mutex(Instant(offset: .zero))

    var now: Instant {
        current.withLock { $0 }
    }

    var minimumResolution: Swift.Duration {
        .zero
    }

    /// Moves the clock forward.
    func advance(by duration: Swift.Duration) {
        current.withLock { $0 = $0.advanced(by: duration) }
    }

    // The review panel only reads its clock.
    func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        Issue.record("Nothing sleeps on a manual clock: a test moves it by hand.")
    }
}
