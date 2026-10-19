import AppKit
import SwiftUI

/// The Settings window, one at a time: every default Lucas can change.
/// Opening it while it's open brings it forward.
final class SettingsWindow: NSWindow {
    /// A window that changes `model`'s settings and the capture shortcut.
    init(model: AppModel, captureShortcut: CaptureShortcutRegistration) {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        title = String(localized: "Settings", comment: "The Settings window's title.")
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = NSHostingView(rootView: SettingsView(model: model, captureShortcut: captureShortcut))
    }

    /// Shows the window in the middle of the screen, in front of the other
    /// apps.
    func show() {
        if let contentView {
            setContentSize(contentView.fittingSize)
        }
        center()
        bringForward()
    }

    /// Brings the window in front of the other apps.
    func bringForward() {
        NSApplication.shared.activate()
        orderFrontRegardless()
        makeKey()
    }
}
