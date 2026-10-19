import AppKit
import SwiftUI

/// One of the app's windows, like Diagnostics or Settings: one at a time, in
/// the middle of the screen, with a title bar and a close button.
final class AppWindow: NSWindow {
    /// A window titled `title` that shows `content`.
    init(title: String, content: some View) {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        self.title = title
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = NSHostingView(rootView: content)
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
