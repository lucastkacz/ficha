import AppKit
import FichaData
import SwiftUI

/// The Cards window: Lucas's cards and his inbox in three panes, as Mail lays
/// out its own. There's one, which he can resize down to what fits the three
/// panes, and which opens where he left it. While it's open, the app shows in
/// the Dock and in ⌘Tab, so he can switch back to it as to any app; once it
/// closes, the app lives in the menu bar only again.
final class CardsWindow: NSWindow {
    /// The name the window's frame is kept under in the app's preferences.
    private static let frameName = "Cards"
    /// The least the window's content can be below its toolbar: enough for
    /// the sidebar, the table and the detail side by side.
    static let minimumSize = NSSize(width: 880, height: 440)
    /// The window's content the first time it opens.
    private static let firstSize = NSSize(width: 1120, height: 640)

    private let model: AppModel
    /// Whether the window is open: on screen, minimized, or hidden with the
    /// app.
    private var isOpen = false

    /// The window, closed, for Lucas's cards in `model`.
    init(model: AppModel) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.firstSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true)
        title = String(localized: "Cards", comment: "The Cards window's title.")
        isReleasedWhenClosed = false
        isRestorable = false
        // The toolbar, where the split view puts its sidebar button.
        toolbar = NSToolbar()
        toolbarStyle = .unified
        if !setFrameUsingName(Self.frameName) {
            center()
        }
        setFrameAutosaveName(Self.frameName)
    }

    /// Opens the window where Lucas left it, with his cards as they are now,
    /// and shows the app in the Dock and in ⌘Tab. When it's open, it comes
    /// forward.
    func open() {
        guard !isOpen else {
            bringForward()
            return
        }
        isOpen = true
        makeContent()
        NSApplication.shared.setActivationPolicy(.regular)
        bringForward()
    }

    /// Gives the window its content, with Lucas's cards as they are now, as
    /// it opens: the app opens it on screen, and `make render` offscreen. The
    /// content is made each time the window opens, so it starts on All cards
    /// with nothing selected or searched, its table as Lucas left it, and
    /// stops reading the cards once it closes. `make render` may give it a
    /// state to open with instead, partway through an import.
    func makeContent(opening state: CardsWindowState? = nil) {
        // Once SwiftUI lays it out, a window's hosting view sets the window's
        // minimum whatever contentMinSize says: from its content's least size
        // with .minSize, and to none without it. So the content says how
        // small it can be, and the hosting view sets nothing else.
        let content = NSHostingView(
            rootView: CardsView(model: model, state: state)
                .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height))
        content.sceneBridgingOptions = [.toolbars]
        content.sizingOptions = [.minSize]
        contentView = content
    }

    /// Brings the window in front of the other apps, out of the Dock when
    /// it's minimized, and with the app when it's hidden.
    private func bringForward() {
        if isMiniaturized {
            deminiaturize(nil)
        }
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate()
        // As AppWindow does: in front even when macOS doesn't activate the
        // app at once.
        orderFrontRegardless()
        makeKey()
    }

    /// Closes the window and its content, and takes the app out of the Dock
    /// and ⌘Tab.
    override func close() {
        super.close()
        isOpen = false
        contentView = nil
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
