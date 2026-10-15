import Foundation

/// What Lucas's Mac tells Ficha, which the app reads from the OS and tests
/// fake, so the rules that react to it are tested without the OS
/// (`CODING_STANDARDS.md`).
public protocol MacSignals {
    /// Whether the Mac or its screens are asleep, so there's no one to show
    /// the review panel to.
    var isAsleep: Bool { get }
    /// When the Mac or its screens last woke, by the engine's time, or nil
    /// when they haven't slept since Ficha started.
    var lastWake: Date? { get }
    /// How long it's been since Lucas last pressed a key, clicked, moved the
    /// pointer or scrolled, or nil when the Mac doesn't say.
    var idleTime: Duration? { get }
}
