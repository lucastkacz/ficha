import Foundation

/// What Lucas's device tells Ficha. The Mac's app reads it from the OS and
/// tests fake it, so the rules that react to it are tested without the OS
/// (`CODING_STANDARDS.md`). The iPhone's never holds an appearance back:
/// waking, idle time and suppressions don't apply there, and iOS's Focus
/// silences notifications on its own (#97).
public protocol DeviceSignals {
    /// Whether the device or its screens are asleep, so there's no one to show
    /// an appearance to.
    var isAsleep: Bool { get }
    /// When the device or its screens last woke, by the engine's time, or nil
    /// when they haven't slept since Ficha started.
    var lastWake: Date? { get }
    /// How long it's been since Lucas last pressed a key, clicked, moved the
    /// pointer or scrolled, or nil when the device doesn't say.
    var idleTime: Duration? { get }
    /// What holds appearances back now: a meeting, a video or a full-screen
    /// app, or none of them.
    var suppressions: Set<Suppression> { get }
    /// When each suppression last ended, by the engine's time. One that
    /// hasn't ended since Ficha started has none.
    var suppressionEnds: [Suppression: Date] { get }
}
