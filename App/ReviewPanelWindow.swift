import AppKit
import FichaData
import SwiftUI

/// The review panel's window: a small floating panel without a title bar,
/// which its Liquid Glass draws, near the top of the screen and on the Space
/// Lucas is in. It's an AppKit panel because a SwiftUI window without a title
/// bar can't take the keyboard. It takes the keyboard without activating
/// Ficha, so once it closes, the keyboard goes back to the app Lucas was in.
final class ReviewPanelWindow: NSPanel {
    /// A panel for the cards a review now brought, which closes itself when
    /// Lucas is done.
    init(model: Result<ReviewPanelModel, EngineError>) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        title = "Repasar"
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

    /// Shows the panel at the top of the screen Lucas is pointing at, centered
    /// just below the menu bar, and gives it the keyboard. As its content
    /// changes size, it keeps its top edge where it is.
    func show() {
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
        makeKeyAndOrderFront(nil)
    }
}
