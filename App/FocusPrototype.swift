// PROTOTYPE for #10, throwaway: this branch is never merged.
//
// The question: how can the review panel show up over whatever Lucas is doing
// without catching what he types? Ficha Dev's debug menu tries the three focus
// modes on the real review panel, over the app Lucas is typing in, and the
// panel shows what happens live, under the card. Its findings go to
// `docs/prototypes/review-panel-focus.md`, for the appearances ticket (#11).

import AppKit
import ApplicationServices
import CoreGraphics
import FichaCore
import FichaData
import Observation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "focus-prototype")

/// The three focus modes the prototype tries.
enum PrototypeFocusMode: String, CaseIterable {
    /// The panel never takes the keyboard on its own: Lucas clicks it.
    case never
    /// The panel takes the keyboard once Lucas has been idle for 5 seconds.
    case afterIdle
    /// The panel takes the keyboard as soon as it shows.
    case always

    var title: String {
        switch self {
        case .never: "Nunca toma el teclado"
        case .afterIdle: "Lo toma tras 5 s quieto"
        case .always: "Lo toma siempre"
        }
    }
}

/// How the panel gives the keyboard back when it closes, to the app in front.
enum KeyboardReturn: String {
    /// Only closes, as #9's panel does. Lucas found that his keys didn't go
    /// back to TextEdit (#34).
    case nothing
    /// Yields activation to the app in front and activates it, as macOS 14's
    /// cooperative activation asks, before closing.
    case activateFront
    /// Hides Ficha Dev once the panel is closed.
    case hide
}

/// How long Lucas must be idle before the panel takes the keyboard, in the
/// `afterIdle` mode.
private let idleThreshold: TimeInterval = 5

/// Every input event, the keyboard's and the mouse's: CoreGraphics'
/// `kCGAnyInputEventType`, which Swift doesn't import.
private let anyInputEvent = CGEventType(rawValue: ~0)

/// One trial of a focus mode at a time: the review panel shows up over the app
/// Lucas is in, without activating Ficha Dev, and takes the keyboard as the mode
/// says. What it sees is what the panel's readout shows.
@Observable
final class FocusPrototype {
    static let shared = FocusPrototype()

    private(set) var mode = PrototypeFocusMode.never
    /// Whether the panel is the key window, the one keys go to.
    private(set) var hasKeyboard = false
    /// How long after showing the panel took the keyboard on its own, if it did.
    private(set) var tookKeyboardAfter: Duration?
    /// Seconds since Lucas last touched the keyboard, the mouse or the trackpad,
    /// as the OS tells it.
    private(set) var idle: TimeInterval = 0
    /// Seconds since Lucas last pressed a key.
    private(set) var idleFromKeyboard: TimeInterval = 0
    private(set) var frontmostApp = ""
    /// The app whose menus the menu bar shows.
    private(set) var menuBarOwner = ""
    /// Whether AppKit says Ficha Dev is active.
    private(set) var isFichaActive = false
    /// The keys that reached the panel, oldest first.
    private(set) var keys: [String] = []
    private(set) var permissions = ""

    /// How the panel gives the keyboard back when it closes: from the debug
    /// menu, as #9's panel does, so Lucas's trials match it.
    private(set) var keyboardReturn = KeyboardReturn.nothing

    private var trial: Task<Void, Never>?
    private var panel: ReviewPanelWindow?
    private var keyMonitor: Any?

    /// Shows the panel in `mode` after `delay`, so Lucas has time to go and type
    /// in another app. Ends the trial before, if one is running.
    func start(_ mode: PrototypeFocusMode, after delay: Duration = .seconds(10), quitWhenDone: Bool = false) {
        trial?.cancel()
        panel?.close()
        logger.info("trial \(mode.rawValue, privacy: .public) starts in \(delay, privacy: .public)")
        trial = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.run(mode, quitWhenDone: quitWhenDone)
        }
    }

    /// For agents: with `-FocusPrototype <mode>` among Ficha Dev's launch
    /// arguments, runs one trial right away, closes the panel 3 seconds after
    /// it shows, and quits 4 seconds later. `-FocusPrototypeReturn <how>` picks
    /// how the panel gives the keyboard back.
    func runFromLaunchArguments() {
        let defaults = UserDefaults.standard
        guard
            let argument = defaults.string(forKey: "FocusPrototype"),
            let mode = PrototypeFocusMode(rawValue: argument)
        else {
            return
        }
        if let argument = defaults.string(forKey: "FocusPrototypeReturn"),
            let keyboardReturn = KeyboardReturn(rawValue: argument)
        {
            self.keyboardReturn = keyboardReturn
        }
        start(mode, after: .seconds(2), quitWhenDone: true)
    }

    private func run(_ mode: PrototypeFocusMode, quitWhenDone: Bool) async {
        let model: ReviewPanelModel
        do {
            model = try prototypeCards()
        } catch {
            logger.error("no cards for the prototype: \(error, privacy: .public)")
            return
        }
        self.mode = mode
        tookKeyboardAfter = nil
        keys = []
        let panel = ReviewPanelWindow(model: .success(model))
        panel.contentView = NSHostingView(
            rootView: VStack(spacing: 8) {
                ReviewPanelView(model: .success(model)) { [weak self, weak panel] in
                    guard let panel else { return }
                    self?.close(panel)
                }
                FocusReadout(prototype: self)
            }
        )
        self.panel = panel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            if panel?.isVisible == true {
                self?.keys.append(name(of: event))
                logger.info("a key reached the panel")
            } else {
                logger.info("a key reached Ficha Dev after the panel closed")
            }
            return event
        }

        panel.show(takingKeyboard: mode == .always)
        let shownAt = ContinuousClock.now
        if mode == .always {
            tookKeyboardAfter = .zero
        }
        logger.info("panel shown, mode \(mode.rawValue, privacy: .public)")
        while panel.isVisible, !Task.isCancelled {
            let elapsed = ContinuousClock.now - shownAt
            readTheOS()
            if mode == .afterIdle, tookKeyboardAfter == nil, idle >= idleThreshold {
                panel.makeKey()
                tookKeyboardAfter = elapsed
                logger.info("took the keyboard after \(elapsed, privacy: .public)")
            }
            let hadKeyboard = hasKeyboard
            hasKeyboard = panel.isKeyWindow
            if hasKeyboard != hadKeyboard {
                logger.info("panel is key: \(self.hasKeyboard, privacy: .public)")
            }
            if quitWhenDone, elapsed > .seconds(3) {
                close(panel)
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                break
            }
        }

        readTheOS()
        logger.info(
            "panel closed; frontmost \(self.frontmostApp, privacy: .public), Ficha active \(self.isFichaActive, privacy: .public), \(self.keys.count, privacy: .public) keys reached it"
        )
        // Keys that still reach Ficha Dev now went nowhere: the monitor keeps
        // listening for a while, to tell.
        let closedAt = ContinuousClock.now
        while ContinuousClock.now - closedAt < .seconds(4), !Task.isCancelled {
            readTheOS()
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                break
            }
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if quitWhenDone {
            NSApplication.shared.terminate(nil)
        }
    }

    /// Closes the panel and gives the keyboard back to the app in front, as
    /// `keyboardReturn` says.
    private func close(_ panel: ReviewPanelWindow) {
        guard panel.isVisible else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let isFichaInFront = front?.processIdentifier == NSRunningApplication.current.processIdentifier
        switch keyboardReturn {
        case .nothing:
            panel.close()
        case .activateFront:
            if let front, !isFichaInFront {
                NSApplication.shared.yieldActivation(to: front)
                let activated = front.activate(from: .current, options: [])
                logger.info(
                    "activating \(front.localizedName ?? "?", privacy: .public): \(activated, privacy: .public)")
            }
            panel.close()
        case .hide:
            panel.close()
            NSApplication.shared.hide(nil)
        }
        logger.info("closed, giving the keyboard back by \(self.keyboardReturn.rawValue, privacy: .public)")
    }

    /// Reads what the OS says now: the idle times, the frontmost app and the
    /// permissions Ficha Dev has, none of which asks Lucas for anything.
    private func readTheOS() {
        let hid = anyInputEvent.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) } ?? -1
        let session =
            anyInputEvent.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) } ?? -1
        idle = hid
        idleFromKeyboard = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "ninguna"
        let menuBar = NSWorkspace.shared.menuBarOwningApplication?.localizedName ?? "ninguna"
        let active = NSApplication.shared.isActive
        if frontmost != frontmostApp || menuBar != menuBarOwner || active != isFichaActive {
            logger.info(
                "frontmost \(frontmost, privacy: .public), menu bar \(menuBar, privacy: .public), Ficha active \(active, privacy: .public) (running app says \(NSRunningApplication.current.isActive, privacy: .public))"
            )
        }
        frontmostApp = frontmost
        menuBarOwner = menuBar
        isFichaActive = active
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = CGPreflightListenEventAccess()
        permissions =
            accessibility || inputMonitoring
            ? "Permisos que tiene: \(accessibility ? "Accesibilidad " : "")\(inputMonitoring ? "Monitoreo de entrada" : "")"
            : "Permisos que tiene: ninguno"
        logger.debug(
            "idle hid \(hid, privacy: .public) session \(session, privacy: .public) keyboard \(self.idleFromKeyboard, privacy: .public); accessibility \(accessibility, privacy: .public), input monitoring \(inputMonitoring, privacy: .public)"
        )
    }
}

/// The cards the prototype's panel shows, from an engine of its own in memory,
/// so Ficha Dev's cards stay as they were: four due cards and then a new one,
/// so Space, 1, 2, 3 and Enter all do something.
private func prototypeCards() throws -> ReviewPanelModel {
    let time = ManualTimeSource(now: SystemTimeSource().now)
    let engine = try Engine(location: .inMemory, time: time)
    try SampleCards.load(into: engine)
    let settings = ReviewSettings.defaults
    for card in try engine.cards().prefix(4) {
        try engine.record(
            .firstView, of: card.id, responseTime: .seconds(1), trigger: .reviewNow, ladder: settings.ladder)
    }
    // An hour later, the first step's wait, those four are due.
    time.advance(by: 61 * 60)
    return try ReviewPanelModel(engine: engine, settings: settings)
}

/// A key as the readout shows it.
private func name(of event: NSEvent) -> String {
    let command = event.modifierFlags.contains(.command) ? "⌘" : ""
    let key =
        switch event.keyCode {
        case 49: "espacio"
        case 36, 76: "↩"
        case 53: "esc"
        case 51: "⌫"
        case 48: "⇥"
        default: event.charactersIgnoringModifiers ?? "?"
        }
    return command + key
}

/// What the prototype's panel shows under the card: the mode, who has the
/// keyboard, how long Lucas has been idle, and which keys reached the panel.
private struct FocusReadout: View {
    let prototype: FocusPrototype

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prototipo · \(prototype.mode.title)")
                .font(.caption.weight(.semibold))
            Text(keyboardLine)
            Text("Quieto hace \(seconds(prototype.idle)) · sin teclear hace \(seconds(prototype.idleFromKeyboard))")
            Text("Al frente: \(prototype.frontmostApp) · menú de: \(prototype.menuBarOwner)")
            Text("Ficha Dev activa, según AppKit: \(prototype.isFichaActive ? "sí" : "no")")
            Text("Teclas que llegaron a la cajita: \(keysLine)")
                .fixedSize(horizontal: false, vertical: true)
            Text(prototype.permissions)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(width: 400, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var keyboardLine: String {
        let holder = prototype.hasKeyboard ? "lo tiene la cajita" : "lo tiene la otra app"
        guard let after = prototype.tookKeyboardAfter else {
            return "Teclado: \(holder)"
        }
        return "Teclado: \(holder) · la cajita lo tomó a los \(seconds(after / .seconds(1)))"
    }

    private var keysLine: String {
        prototype.keys.isEmpty ? "ninguna" : prototype.keys.suffix(20).joined(separator: " ")
    }

    private func seconds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "es")))) s"
    }
}
