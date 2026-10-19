import AppKit
import SwiftUI

/// One of the app's windows, like Diagnostics or Settings: one at a time, in
/// the middle of the screen, with a title bar and a close button.
final class AppWindow: NSWindow {
    /// A window titled `title` that shows `content`.
    convenience init(title: String, content: some View) {
        self.init()
        self.title = title
        contentView = NSHostingView(rootView: content)
    }

    /// A window that shows `tabs` as a Mac's settings window does: the tabs
    /// in its toolbar, and the selected tab's name as its title.
    convenience init(tabs: NSTabViewController) {
        self.init()
        toolbarStyle = .preference
        contentViewController = tabs
        // As NSWindow's documentation suggests, since the content doesn't
        // title the window. The tabs' title is the selected tab's.
        bind(.title, to: tabs, withKeyPath: #keyPath(NSViewController.title))
    }

    /// A window with no content yet.
    private init() {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        isRestorable = false
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
