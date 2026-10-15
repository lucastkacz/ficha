import CoreGraphics
import FichaCore
import Foundation

/// What Lucas's Mac tells Ficha, read from the OS without asking for any
/// permission (#10's findings): when it last woke, which the appearance loop
/// notes as it hears it, and how long Lucas has been idle.
final class SystemMacSignals: MacSignals {
    private(set) var lastWake: Date?

    /// Notes that the Mac, or its screens, woke at `time`, by the engine's
    /// time.
    func noteWake(at time: Date) {
        lastWake = time
    }

    /// The time since the last key press, click, pointer move or scroll, from
    /// the system's input events, which needs no permission.
    var idleTime: Duration? {
        // Every input event: CoreGraphics' `kCGAnyInputEventType`, which Swift
        // doesn't import.
        guard let anyInputEvent = CGEventType(rawValue: ~0) else {
            return nil
        }
        return .seconds(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputEvent))
    }
}
