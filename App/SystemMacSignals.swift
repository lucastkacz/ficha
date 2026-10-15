import AppKit
import CoreGraphics
import FichaCore
import Foundation

/// What Lucas's Mac tells Ficha, read from the OS without asking for any
/// permission (#10's findings): whether it or its screens are asleep, when
/// they last woke, and how long Lucas has been idle.
final class SystemMacSignals: MacSignals {
    private var isMacAsleep = false
    private var areScreensAsleep = false
    private(set) var lastWake: Date?
    /// The engine's time, which the wakes are noted by.
    private let now: () -> Date
    /// What to do as the Mac or its screens go to sleep or wake up.
    var sleptOrWoke: (() -> Void)?
    /// What it follows of the Mac's sleep and wake, for as long as Ficha runs.
    private var observers: [any NSObjectProtocol] = []

    /// The Mac's signals, noting its wakes by `now`, the engine's time.
    init(now: @escaping () -> Date) {
        self.now = now
        observe(NSWorkspace.willSleepNotification, as: .macSleeps)
        observe(NSWorkspace.screensDidSleepNotification, as: .screensSleep)
        observe(NSWorkspace.didWakeNotification, as: .macWakes)
        observe(NSWorkspace.screensDidWakeNotification, as: .screensWake)
    }

    var isAsleep: Bool {
        isMacAsleep || areScreensAsleep
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

    /// Follows `notification`, which the OS posts as the Mac or its screens
    /// go to sleep or wake up.
    private func observe(_ notification: Notification.Name, as event: SleepOrWake) {
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: notification, object: nil, queue: .main
        ) { [weak self] _ in
            // An observer on the main queue runs on the main actor.
            MainActor.assumeIsolated {
                self?.follow(event)
            }
        }
        observers.append(observer)
    }

    /// Notes when the Mac and its screens are awake again, and says when they
    /// fall asleep or wake.
    private func follow(_ event: SleepOrWake) {
        let wasAsleep = isAsleep
        switch event {
        case .macSleeps:
            isMacAsleep = true
        case .screensSleep:
            areScreensAsleep = true
        case .macWakes:
            isMacAsleep = false
        case .screensWake:
            // Screens that wake are on a Mac that's awake, even if its own
            // wake went unheard.
            areScreensAsleep = false
            isMacAsleep = false
        }
        if wasAsleep, !isAsleep {
            lastWake = now()
        }
        if wasAsleep != isAsleep {
            sleptOrWoke?()
        }
    }
}

/// The Mac or its screens going to sleep or waking up.
private enum SleepOrWake {
    case macSleeps
    case screensSleep
    case macWakes
    case screensWake
}
