import AppKit
import FichaCore
import FichaData
import os

/// The appearances' log.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "appearances")

/// What asking the engine about an appearance came to.
enum AppearanceCheck {
    /// The review panel was open, so the engine wasn't asked.
    case panelOpen
    /// The Mac or its screens were asleep, so the engine wasn't asked.
    case asleep
    /// The engine decided this, and the panel showed up if it said so.
    case decided(AppearanceDecision)
    /// The engine couldn't decide, for this reason.
    case failed(EngineError)
}

/// Asks the engine whether the review panel shows up on its own, and shows it
/// when the engine says so (ADR 0003): every minute, or sooner, when the
/// engine says when the next appearance may come. While the Mac or its
/// screens sleep, it doesn't ask. When they wake, it notes when, since an
/// appearance waits a while after waking, and asks again.
final class AppearanceLoop {
    /// How long it waits at most between two checks.
    private static let checkInterval = Duration.seconds(60)

    private let model: AppModel
    private let mac: SystemMacSignals
    private let panels: ReviewPanels
    private var isMacAsleep = false
    private var areScreensAsleep = false
    /// The wait until the next check.
    private var nextCheck: Task<Void, Never>?
    /// What the loop follows of the Mac's sleep and wake, for as long as
    /// Ficha runs.
    private var observers: [any NSObjectProtocol] = []

    init(model: AppModel, mac: SystemMacSignals, panels: ReviewPanels) {
        self.model = model
        self.mac = mac
        self.panels = panels
    }

    /// Starts checking: right away, and from then on.
    func start() {
        observe(NSWorkspace.willSleepNotification, as: .macSleeps)
        observe(NSWorkspace.screensDidSleepNotification, as: .screensSleep)
        observe(NSWorkspace.didWakeNotification, as: .macWakes)
        observe(NSWorkspace.screensDidWakeNotification, as: .screensWake)
        check()
    }

    /// Asks the engine now, unless the panel is open or the Mac is asleep,
    /// shows the panel if the engine says so, and waits for the next check.
    /// Ficha Dev's debug menu checks this way too.
    @discardableResult
    func check() -> AppearanceCheck {
        nextCheck?.cancel()
        nextCheck = nil
        guard !isMacAsleep, !areScreensAsleep else {
            return .asleep
        }
        let result = askTheEngine()
        var wait = Self.checkInterval
        if case .decided(.notNow(let reason)) = result, let until = reason.until {
            wait = min(wait, max(.seconds(1), .seconds(until.timeIntervalSince(model.now))))
        }
        nextCheck = Task { [weak self] in
            do {
                try await Task.sleep(for: wait)
            } catch {
                return
            }
            self?.check()
        }
        return result
    }

    private func askTheEngine() -> AppearanceCheck {
        guard !panels.isOpen else {
            return .panelOpen
        }
        let decision: AppearanceDecision
        do {
            decision = try model.checkAppearance(mac: mac)
        } catch {
            logger.error("Couldn't check for an appearance: \(String(describing: error), privacy: .public)")
            return .failed(error)
        }
        if case .show(let cards) = decision {
            logger.info("The review panel shows up on its own with \(cards.count) cards")
            panels.showAppearance(cards)
        }
        return .decided(decision)
    }

    /// Follows `notification`, which the OS posts when the Mac or its screens
    /// sleep or wake.
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

    /// When the Mac or its screens go to sleep, there's no one to show the
    /// panel to: the open panel closes on its own, and the checks stop. When
    /// both are awake again, it notes when they woke, and checks.
    private func follow(_ event: SleepOrWake) {
        let wasAsleep = isMacAsleep || areScreensAsleep
        switch event {
        case .macSleeps: isMacAsleep = true
        case .screensSleep: areScreensAsleep = true
        case .macWakes: isMacAsleep = false
        case .screensWake: areScreensAsleep = false
        }
        switch (wasAsleep, isMacAsleep || areScreensAsleep) {
        case (false, true):
            nextCheck?.cancel()
            nextCheck = nil
            panels.closeOnItsOwn()
        case (true, false):
            mac.noteWake(at: model.now)
            check()
        case (false, false), (true, true):
            break
        }
    }
}

/// The Mac or its screens going to sleep or waking.
private enum SleepOrWake {
    case macSleeps
    case screensSleep
    case macWakes
    case screensWake
}

extension NoAppearance {
    /// When an appearance may come, when the engine knows it.
    fileprivate var until: Date? {
        switch self {
        case .tooSoonAfterLastOne(let until), .tooSoonAfterWaking(let until): until
        case .outsideActiveHours, .nothingDue: nil
        }
    }
}
