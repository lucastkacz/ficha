import Foundation

/// What Lucas's Mac tells Ficha, which the app reads from the OS and tests
/// fake, so the rules that react to it are tested without the OS
/// (`CODING_STANDARDS.md`).
public protocol MacSignals {
    /// When the Mac last woke, by the engine's time, or nil when it hasn't
    /// slept since Ficha started.
    var lastWake: Date? { get }
    /// How long it's been since Lucas last pressed a key, clicked, moved the
    /// pointer or scrolled, or nil when the Mac doesn't say.
    var idleTime: Duration? { get }
}
