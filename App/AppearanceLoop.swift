import FichaCore
import FichaData
import Foundation
import os

/// The appearances' log.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "appearances")

/// What asking the engine about an appearance came to.
enum AppearanceCheck {
    /// The review panel was open, so the engine wasn't asked.
    case panelOpen
    /// The engine decided this, and the panel showed up if it said so.
    case decided(AppearanceDecision)
    /// The engine couldn't decide, for this reason.
    case failed(EngineError)
}

/// Asks the engine whether the review panel shows up on its own, and shows it
/// when the engine says so (ADR 0003): every minute, or sooner, when the
/// engine says when the next appearance may come, and as soon as the Mac or
/// its screens wake, or a suppression starts or ends. As they go to sleep,
/// the open panel closes on its own.
final class AppearanceLoop {
    /// How long it waits at most between two checks.
    private static let checkInterval = Duration.seconds(60)

    private let model: AppModel
    private let mac: SystemMacSignals
    private let panel: ReviewPanel
    /// The wait until the next check.
    private var nextCheck: Task<Void, Never>?
    /// Whether the last check failed: the panel says so once, not every
    /// minute.
    private var lastCheckFailed = false

    init(model: AppModel, mac: SystemMacSignals, panel: ReviewPanel) {
        self.model = model
        self.mac = mac
        self.panel = panel
    }

    /// Starts checking, a minute from now. A panel shown while Ficha was still
    /// launching took the keyboard as it showed, while Lucas typed, so the
    /// first check waits until Ficha has settled.
    func start() {
        mac.sleptOrWoke = { [weak self] in
            self?.macSleptOrWoke()
        }
        mac.suppressionsChanged = { [weak self] in
            self?.check()
        }
        mac.startDetecting()
        checkAgain(after: Self.checkInterval)
    }

    /// Asks the engine now, unless the panel is open, shows the panel if the
    /// engine says so, and waits for the next check. Ficha Dev's debug menu
    /// checks this way too.
    @discardableResult
    func check() -> AppearanceCheck {
        let result = askTheEngine()
        var wait = Self.checkInterval
        if case .decided(.notNow(let reason)) = result, let until = reason.until {
            wait = min(wait, max(.seconds(1), .seconds(until.timeIntervalSince(model.now))))
        }
        checkAgain(after: wait)
        return result
    }

    /// Checks again after `wait`, in place of any check it was waiting for.
    private func checkAgain(after wait: Duration) {
        nextCheck?.cancel()
        nextCheck = Task { [weak self] in
            do {
                try await Task.sleep(for: wait)
            } catch {
                return
            }
            self?.check()
        }
    }

    private func askTheEngine() -> AppearanceCheck {
        guard !panel.isOpen else {
            return .panelOpen
        }
        let decision: AppearanceDecision
        do {
            decision = try model.checkAppearance(mac: mac)
        } catch {
            logger.error("Couldn't check for an appearance: \(String(describing: error), privacy: .public)")
            // Rather than stop showing up without a word, the panel shows up
            // once to say why.
            if !lastCheckFailed {
                panel.showFailure(error)
            }
            lastCheckFailed = true
            return .failed(error)
        }
        lastCheckFailed = false
        switch decision {
        case .show(let cards):
            logger.info("The review panel shows up on its own with \(cards.count) cards")
            panel.showAppearance(cards)
        case .notNow(let reason):
            logger.debug("No appearance now: \(String(describing: reason), privacy: .public)")
        }
        return .decided(decision)
    }

    /// As the Mac or its screens go to sleep, there's no one to show the panel
    /// to, so the open panel closes on its own. As they wake, it checks right
    /// away, so the next appearance comes as soon as the wait after waking
    /// is over.
    private func macSleptOrWoke() {
        if mac.isAsleep {
            panel.close(.onItsOwn)
        } else {
            check()
        }
    }
}
