import AppKit
import FichaCore
import FichaData
import SwiftUI
import os

/// The review panel's log, which says when the panel gets the keyboard.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "review panel")

/// The review panel's window: a small floating panel without a title bar,
/// which its Liquid Glass draws, near the top of the screen and on the Space
/// Lucas is in. It's an AppKit panel because a SwiftUI window without a title
/// bar can't take the keyboard. It takes the keyboard without activating
/// Ficha, so once it closes, the keyboard goes back to the app Lucas was in.
/// When it shows up on its own, it can't have the keyboard until the focus
/// mode says so or Lucas clicks it, so it doesn't catch what he's typing
/// (#10's findings).
final class ReviewPanelWindow: NSPanel {
    /// The panel's cards, or why they couldn't be brought.
    private let model: Result<ReviewPanelModel, EngineError>
    /// Whether a panel that says why it couldn't bring its cards may have the
    /// keyboard: when Lucas opened it, or once he clicks it.
    private var failureMayHaveKeyboard = false
    /// What tells the panel how long Lucas has been idle, while it waits to
    /// take the keyboard on its own.
    private var mac: SystemMacSignals?
    /// Watches the panel while it's open.
    private var watching: Task<Void, Never>?

    /// A panel for the cards a review now or an appearance brought, which
    /// closes itself when Lucas closes it or it closes on its own, or for why
    /// they couldn't be brought.
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
        let content = NSHostingView(
            rootView: ReviewPanelView(model: model) { [weak self] in
                self?.close()
            }
        )
        // The panel is the glass's rounded rectangle, not its whole frame:
        // while the panel has the keyboard, the glass's backdrop covers the
        // whole frame, and the panel's shadow follows it, unless the content
        // is clipped to the glass's shape (#64).
        content.wantsLayer = true
        content.layer?.cornerRadius = ReviewPanelView.cornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        contentView = content
    }

    // A window without a title bar takes the keyboard only when it says so,
    // and this one says so only when it may have it: AppKit once gave it the
    // keyboard as it showed, while Lucas typed, before the focus mode allowed
    // it.
    override var canBecomeKey: Bool {
        switch model {
        case .success(let panel): panel.mayHaveKeyboard
        case .failure: failureMayHaveKeyboard
        }
    }

    // A click gives the panel the keyboard, before AppKit decides whether it
    // may have it.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            giveKeyboard()
            logger.info("Lucas clicked the review panel, which gives it the keyboard")
        }
        super.sendEvent(event)
    }

    /// Shows the panel and gives it the keyboard, since Lucas asked for it:
    /// a review now.
    func show() {
        failureMayHaveKeyboard = true
        place()
        makeKeyAndOrderFront(nil)
        watch()
    }

    /// Shows the panel on its own, over whatever Lucas is doing, without the
    /// keyboard: an appearance, or why one couldn't come. It takes the
    /// keyboard once, as the focus mode says, by how long `mac` says Lucas has
    /// been idle. Ficha is never activated, so the app Lucas is in stays in
    /// front.
    func showOnItsOwn(mac: SystemMacSignals) {
        self.mac = mac
        place()
        orderFrontRegardless()
        takeKeyboardIfItsTime()
        watch()
    }

    /// Brings the open panel to the front with the keyboard, since Lucas
    /// asked for it with review now.
    func bringForward() {
        giveKeyboard()
        orderFrontRegardless()
        makeKey()
    }

    /// Closes the panel: Lucas closes it, or it closes on its own.
    func close(_ closing: ReviewPanelState.Closing) {
        if case .success(let panel) = model {
            panel.close(closing)
        }
        close()
    }

    override func close() {
        watching?.cancel()
        watching = nil
        super.close()
    }

    /// Lets the panel have the keyboard, since Lucas asked for it.
    private func giveKeyboard() {
        switch model {
        case .success(let panel): panel.clicked()
        case .failure: failureMayHaveKeyboard = true
        }
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

    /// Gives the panel the keyboard when the focus mode says so.
    private func takeKeyboardIfItsTime() {
        guard let mac, case .success(let panel) = model, panel.takesKeyboard(on: mac) else { return }
        makeKey()
        logger.info("The review panel took the keyboard")
    }
}
