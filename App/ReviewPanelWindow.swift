import AppKit
import FichaCore
import FichaData
import SwiftUI
import os

/// The review panel's log, which says when it takes the keyboard.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "review panel")

/// The review panel's window: a small floating panel without a title bar,
/// which its Liquid Glass draws, near the top of the screen and on the Space
/// Lucas is in. It's an AppKit panel because a SwiftUI window without a title
/// bar can't take the keyboard. It takes the keyboard without activating
/// Ficha, so once it closes, the keyboard goes back to the app Lucas was in.
/// When it shows up on its own, it takes the keyboard only as the focus mode
/// says, so it doesn't catch what Lucas is typing (#10's findings).
final class ReviewPanelWindow: NSPanel {
    /// The panel's cards, or why review now couldn't bring them.
    private let model: Result<ReviewPanelModel, EngineError>
    /// Whether the panel takes the keyboard now, while it waits to take it on
    /// its own: nil once it has it, which happens once per panel.
    private var takesKeyboardNow: (() -> Bool)?
    /// Watches the panel while it's open.
    private var watching: Task<Void, Never>?

    /// A panel for the cards a review now or an appearance brought, which
    /// closes itself when Lucas is done.
    init(model: Result<ReviewPanelModel, EngineError>) {
        self.model = model
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        title = String(
            localized: "Review",
            comment: "The review panel's window title, which doesn't show: the panel has no title bar.")
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentView = NSHostingView(
            rootView: ReviewPanelView(model: model) { [weak self] in
                self?.close()
            }
        )
    }

    // A window without a title bar takes the keyboard only when it says so.
    override var canBecomeKey: Bool { true }

    /// Shows the panel and gives it the keyboard, since Lucas asked for it:
    /// a review now.
    func show() {
        place()
        makeKeyAndOrderFront(nil)
        watch()
    }

    /// Shows the panel on its own, over whatever Lucas is doing, without the
    /// keyboard: an appearance. It takes the keyboard once, when the focus
    /// mode of `settings` says so, by how long `mac` says Lucas has been idle.
    /// Ficha is never activated, so the app Lucas is in stays in front.
    func showOnItsOwn(settings: ReviewSettings, mac: some MacSignals) {
        place()
        orderFrontRegardless()
        takesKeyboardNow = {
            settings.focusMode.takesKeyboard(idle: mac.idleTime, after: settings.idleBeforeTakingKeyboard)
        }
        takeKeyboardIfItsTime()
        watch()
    }

    /// Brings the open panel to the front with the keyboard, since Lucas
    /// asked for it.
    func bringForward() {
        orderFrontRegardless()
        makeKey()
        takesKeyboardNow = nil
    }

    /// Closes the panel as Esc does, which snoozes an appearance: as Ficha
    /// quits.
    func closeAsLucasWould() {
        if case .success(let panel) = model {
            panel.close()
        }
        close()
    }

    /// Closes the panel on its own: as the Mac or its screens go to sleep.
    func closeOnItsOwn() {
        if case .success(let panel) = model {
            panel.closeOnItsOwn()
        }
        close()
    }

    override func close() {
        watching?.cancel()
        watching = nil
        super.close()
    }

    /// Places the panel at the top of the screen Lucas is pointing at,
    /// centered just below the menu bar. As its content changes size, it
    /// keeps its top edge where it is.
    private func place() {
        let mouse = NSEvent.mouseLocation
        guard
            let contentView,
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else {
            return
        }
        let size = contentView.fittingSize
        setContentSize(size)
        let visible = screen.visibleFrame
        setFrameTopLeftPoint(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - 40))
    }

    /// Every quarter of a second while the panel is open, as #10's prototype
    /// did: gives it the keyboard when it's time, and closes it once it's
    /// been untouched for long enough.
    private func watch() {
        guard case .success(let panel) = model else { return }
        watching = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                self?.takeKeyboardIfItsTime()
                panel.closeIfUntouched()
            }
        }
    }

    /// Gives the panel the keyboard once the focus mode says so. If Lucas
    /// gave it the keyboard first, by clicking it, it doesn't take it again
    /// after he clicks away.
    private func takeKeyboardIfItsTime() {
        guard let takesKeyboardNow else { return }
        if isKeyWindow {
            logger.info("The review panel has the keyboard: Lucas clicked it")
            self.takesKeyboardNow = nil
        } else if takesKeyboardNow() {
            makeKey()
            logger.info("The review panel took the keyboard")
            self.takesKeyboardNow = nil
        }
    }
}
