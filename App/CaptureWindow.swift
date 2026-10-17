import AppKit
import SwiftUI

/// The capture window, one at a time: a small floating window titled
/// "Capture", sized to its fields. It's an AppKit window, so the capture
/// shortcut can open it from any app, outside SwiftUI's views.
final class CaptureWindow: NSObject, NSWindowDelegate {
    private let model: AppModel
    /// The window while it's open.
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    /// Opens the window with empty fields, or, when it's open, brings it
    /// forward with what Lucas typed. Either way it takes the keyboard.
    func open() {
        let window = window ?? makeWindow()
        self.window = window
        // A menu-bar app isn't active until it's asked to be, and the window
        // only takes the keyboard in an active app.
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    /// A new window, with empty fields, in the middle of the screen.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = String(localized: "Capture", comment: "The capture window's title.")
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        let content = NSHostingController(
            rootView: CaptureView(model: model, dismiss: { [weak window] in window?.close() }))
        content.sizingOptions = .preferredContentSize
        window.contentViewController = content
        window.center()
        return window
    }
}
