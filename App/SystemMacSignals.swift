import AppKit
import CoreGraphics
import FichaCore
import Foundation
import os

/// The suppressions' log, which says when they start and end.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "suppressions")

/// What Lucas's Mac tells Ficha, read from the OS without asking for any
/// permission (#10's and #12's findings): whether it or its screens are
/// asleep, when they last woke, how long Lucas has been idle, and what holds
/// appearances back, a Focus by Ficha's filter in it.
final class SystemMacSignals: DeviceSignals {
    /// How often it looks at what holds appearances back: an appearance waits
    /// 2 minutes after a suppression ends anyway, so a few seconds late is
    /// fine, and polling is simpler than following each detector (#12).
    private static let detectionInterval = Duration.seconds(5)

    private var isMacAsleep = false
    private var areScreensAsleep = false
    private(set) var lastWake: Date?
    private(set) var suppressions: Set<Suppression> = []
    private(set) var suppressionEnds: [Suppression: Date] = [:]
    /// The engine's time, which the wakes and the suppressions' ends are
    /// noted by.
    private let now: () -> Date
    /// What to do as the Mac or its screens go to sleep or wake up.
    var sleptOrWoke: (() -> Void)?
    /// What to do as a suppression starts or ends.
    var suppressionsChanged: (() -> Void)?
    /// What it follows of the Mac's sleep and wake, for as long as Ficha runs.
    private var observers: [any NSObjectProtocol] = []
    /// The detectors' polling, for as long as Ficha runs.
    private var detecting: Task<Void, Never>?
    /// The suppressions that couldn't be told at the last look: by their
    /// detectors, or, for a Focus, by Ficha's filter.
    private(set) var cantTell: Set<Suppression> = []

    /// The Mac's signals, noting its wakes and its suppressions' ends by
    /// `now`, the engine's time.
    init(now: @escaping () -> Date) {
        self.now = now
        observe(NSWorkspace.willSleepNotification, as: .macSleeps)
        observe(NSWorkspace.screensDidSleepNotification, as: .screensSleep)
        observe(NSWorkspace.didWakeNotification, as: .macWakes)
        observe(NSWorkspace.screensDidWakeNotification, as: .screensWake)
    }

    /// Starts looking at what holds appearances back, now and every few
    /// seconds, for as long as Ficha runs.
    func startDetecting() {
        detecting?.cancel()
        detectSuppressions()
        detecting = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: Self.detectionInterval)
                } catch {
                    return
                }
                guard let self else { return }
                detectSuppressions()
            }
        }
    }

    /// Notes what the detectors and Ficha's Focus filter say holds
    /// appearances back now. A suppression that can't be told stays as it
    /// was, so a failed reading neither starts nor ends one, and the log says
    /// so.
    private func detectSuppressions() {
        let detection = Detection.read()
        let unknown = Set(Detection.suppressions.filter { detection.isOn($0) == nil })
        noteCantTell(unknown.union(cantTell.intersection([.focus])))
        let detected = Detection.suppressions.filter { detection.isOn($0) ?? suppressions.contains($0) }
        hold(suppressions.subtracting(Detection.suppressions).union(detected))
        readFocusFilter()
    }

    /// Reads whether a Focus holds appearances back, by Ficha's filter. macOS
    /// says so too, through the filter's `perform`, as the Focus turns on or
    /// off, but only once it's connected to Ficha: until then it tries to
    /// launch Ficha, which its own sandbox refuses, as #307's probe found on
    /// macOS 26.3, and Ficha never hears. So Ficha reads it as it reads the
    /// detectors. When it can't, the log says why, once.
    private func readFocusFilter() {
        Task { [weak self] in
            do {
                let filter = try await HoldBackAppearancesFilter.current
                guard let self else { return }
                noteCantTell(cantTell.subtracting([.focus]))
                focusChanged(holdsBack: filter.holdsBack)
            } catch {
                guard let self, !cantTell.contains(.focus) else { return }
                logger.error("Can't read Ficha's Focus filter: \(error.localizedDescription, privacy: .public)")
                noteCantTell(cantTell.union([.focus]))
            }
        }
    }

    /// Notes `unknown` as the suppressions that can't be told now, and logs
    /// it when that changed.
    private func noteCantTell(_ unknown: Set<Suppression>) {
        guard unknown != cantTell else { return }
        let names = Suppression.allCases.filter(unknown.contains).map(\.rawValue).joined(separator: ", ")
        logger.error(
            "Can't tell whether these hold appearances back: \(names.isEmpty ? "none" : names, privacy: .public)")
        cantTell = unknown
    }

    /// Notes whether a Focus holds appearances back, as Ficha's filter says.
    func focusChanged(holdsBack: Bool) {
        hold(holdsBack ? suppressions.union([.focus]) : suppressions.subtracting([.focus]))
    }

    /// Notes `held` as what holds appearances back now, and when each of
    /// those that stopped ended, and says when that changed.
    private func hold(_ held: Set<Suppression>) {
        guard held != suppressions else { return }
        let endedAt = now()
        for ended in suppressions.subtracting(held) {
            suppressionEnds[ended] = endedAt
        }
        suppressions = held
        let names = Suppression.allCases.filter(held.contains).map(\.rawValue).joined(separator: ", ")
        logger.info("Holding appearances back now: \(names.isEmpty ? "nothing" : names, privacy: .public)")
        suppressionsChanged?()
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
