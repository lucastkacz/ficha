import AppKit
import SwiftUI

/// The capture window: a small floating panel titled "Capture", sized to its
/// fields, in the middle of the screen, on the Space Lucas is in and over a
/// full-screen app too. It's an AppKit panel, so the capture shortcut can open
/// it from any app, outside SwiftUI's views. Like the review panel, it takes
/// the keyboard without activating Ficha (#10's findings): macOS may refuse to
/// activate a menu-bar app while Lucas works in another, and once the window
/// closes, the keyboard goes back to the app he was in.
final class CaptureWindow: NSPanel {
    /// A window with empty fields, for a capture into `model`.
    init(model: AppModel) {
        super.init(
            contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: true)
        title = String(localized: "Capture", comment: "The capture window's title.")
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = NSHostingView(
            rootView: CaptureView(model: model) { [weak self] in
                self?.close()
            }
        )
    }

    /// Shows the window in the middle of the screen, with the keyboard.
    func show() {
        if let contentView {
            setContentSize(contentView.fittingSize)
        }
        center()
        makeKeyAndOrderFront(nil)
    }

    /// Brings the open window to the front with the keyboard, with what Lucas
    /// typed in it.
    func bringForward() {
        orderFrontRegardless()
        makeKey()
    }
}
