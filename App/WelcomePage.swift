import AppKit
import FichaData
import SwiftUI

/// The Welcome page, in a window of its own, the first time the real Ficha
/// opens on a Mac: it says Ficha lives in the menu bar, shows its icon, and
/// asks whether it opens at login, as `AppOpening` says. It shows in front of
/// the other apps, floats over the app's other windows, and only its buttons
/// close it, with no close button, so nobody skips the question unawares.
/// `make render` draws it for the real Ficha, and Ficha Dev's debug menu shows
/// it. The startup code doesn't wait for it: what follows runs once a button
/// closes it, so App Intents and a second opening reach the app meanwhile.
final class WelcomeWindow: NSWindow {
    /// Whether the page is open: until a button closes it, also while the app
    /// is hidden, which `isVisible` doesn't say.
    private(set) var isOpen = false

    /// The window for `app`'s page, closed, which asks whether the app opens
    /// at login when `asks` says so, as large as its text and its buttons need
    /// in the app's language. `answered` takes the button the user pressed.
    init(app: AppVariant, asks: Bool, answered: @escaping (AppOpening.Answer) -> Void) {
        super.init(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        // The name Mission Control and VoiceOver read, which the page doesn't
        // show as a title.
        title = app.name
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // The menu's Cards… can open while the page is open, and appearances
        // wait for the page: under that window, nobody would know. The review
        // panel and the capture window float too, so either, which comes only
        // when asked for and closes soon, still shows over the page, where the
        // keyboard goes.
        level = .floating
        // A window that can't close or minimize shows these grayed instead.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isReleasedWhenClosed = false
        isRestorable = false
        let content = NSHostingView(rootView: WelcomePage(app: app, asks: asks, answered: answered))
        // The title bar shows nothing, so the page starts at the window's top.
        content.safeAreaRegions = []
        contentView = content
        setContentSize(content.fittingSize)
    }

    /// Shows the window in the middle of the screen, in front of the other
    /// apps.
    func show() {
        isOpen = true
        center()
        bringForwardWithTheApp()
    }

    override func close() {
        super.close()
        isOpen = false
    }
}

/// What the Welcome page says, and its buttons: Open at Login, the default
/// button, and Not Now, which Esc presses, or, when it doesn't ask, only
/// Continue. Its text wraps at an alert's width, so a long language such as
/// German makes it taller, and its buttons, which can't wrap, make it wider
/// when they need more.
private struct WelcomePage: View {
    /// The width the text wraps at, which the page's padding makes an alert's.
    private static let textWidth: CGFloat = 372

    let app: AppVariant
    let asks: Bool
    let answered: (AppOpening.Answer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "\(app.name) lives in the menu bar",
                    comment:
                        "The title of the Welcome page, the first time the app opens on a Mac. The name is the app's."
                )
                .font(.title2.bold())
                Text(
                    """
                    Look for \(Text(Image(systemName: app.menuBarSymbol))) at the top of your screen. From there, \
                    \(app.name) shows you a card every so often. If you can't see the icon, open \(app.name) again to \
                    reach your cards.
                    """,
                    comment: """
                        On the Welcome page, under that the app lives in the menu bar. The first value is the app's \
                        icon in the menu bar, drawn in the text. The other two are the app's name.
                        """
                )
                .accessibilityLabel(
                    Text(
                        """
                        Look for the \(app.name) icon at the top of your screen. From there, \(app.name) shows you a \
                        card every so often. If you can't see the icon, open \(app.name) again to reach your cards.
                        """,
                        comment: """
                            What VoiceOver reads on the Welcome page for the sentence that draws the app's icon in the \
                            menu bar, which it names instead. The three values are the app's name.
                            """))
            }
            .frame(width: Self.textWidth, alignment: .leading)
            if asks {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Open \(app.name) when you log in?",
                        comment: "The question on the Welcome page. The name is the app's."
                    )
                    .font(.headline)
                    Text(
                        "\(app.name) shows you cards only while it's open. You can change this later in Settings.",
                        comment: "On the Welcome page, under whether the app opens at login. The name is the app's.")
                }
                .frame(width: Self.textWidth, alignment: .leading)
            }
            buttons
        }
        .padding(24)
        .fixedSize()
    }

    /// The buttons, at the page's trailing side, the default one last, as an
    /// alert has them, each as wide as its title, however wide that makes the
    /// page.
    private var buttons: some View {
        HStack {
            if asks {
                Button {
                    answered(.notNow)
                } label: {
                    Text("Not Now", comment: "A button of the Welcome page: the app doesn't open at login.")
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    answered(.openAtLogin)
                } label: {
                    Text("Open at Login", comment: "A button of the Welcome page: the app opens at login.")
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    answered(.continued)
                } label: {
                    Text(
                        "Continue",
                        comment: """
                            The only button of the Welcome page when the app already opens at login, which closes the \
                            page.
                            """)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .frame(minWidth: Self.textWidth, alignment: .trailing)
    }
}
