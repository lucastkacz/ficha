import AppKit
import SwiftUI

/// The Diagnostics window, one at a time: what each detector sees right now,
/// and the latest appearances. Opening it while it's open brings it forward.
final class DiagnosticsWindow: NSWindow {
    /// A window that shows what `model`'s appearances and the detectors say.
    init(model: AppModel) {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        title = String(localized: "Diagnostics", comment: "The Diagnostics window's title.")
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = NSHostingView(rootView: DiagnosticsView(model: model))
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
