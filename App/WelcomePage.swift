import AppKit
import CoreServices
import FichaData
import SwiftUI

/// The Welcome page, in a window of its own, the first time the real Ficha
/// opens on a Mac: it says Ficha lives in the menu bar, shows its icon, and
/// asks whether it opens at login, as `AppOpening` says. It shows in front of
/// the other apps, and only its buttons close it, with no close button, so
/// nobody skips the question unawares. `make render` draws it for the real
/// Ficha, and Ficha Dev's debug menu shows it. The startup code doesn't wait
/// for it: what follows runs once a button closes it, so App Intents and a
/// second opening reach the app meanwhile.
final class WelcomeWindow: NSWindow {
    /// Whether the page is open: until a button closes it, also while the app
    /// is hidden, which `isVisible` doesn't say.
    private(set) var isOpen = false

    /// The window for `app`'s page, closed, which asks whether the app opens
    /// at login when `asks` says so, as tall as its text needs in the app's
    /// language. `answered` takes the button the user pressed.
    init(app: AppVariant, asks: Bool, answered: @escaping (AppOpening.Answer) -> Void) {
        super.init(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        // The name Mission Control and VoiceOver read, which the page doesn't
        // show as a title.
        title = app.name
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
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
        bringForward()
    }

    /// Brings the window in front of the other apps, with the app when it's
    /// hidden.
    func bringForward() {
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate()
        // As AppWindow does: in front even when macOS doesn't activate the
        // app at once.
        orderFrontRegardless()
        makeKey()
    }

    override func close() {
        super.close()
        isOpen = false
    }
}

/// What the Welcome page says, and its buttons: Open at Login, the default
/// button, and Not Now, which Esc presses, or, when it doesn't ask, only
/// Continue. It's as wide as an alert, and grows to fit its text in a long
/// language such as German.
private struct WelcomePage: View {
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
                whereItLives(icon: Text(Image(systemName: app.menuBarSymbol)))
                    .accessibilityLabel(whereItLives(icon: Text(iconName)))
            }
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
            }
            buttons
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(width: 420)
    }

    /// Where the app lives and what it does from there, with `icon` where the
    /// text names the menu bar's icon: the icon itself, on screen, and its
    /// name, for VoiceOver.
    private func whereItLives(icon: Text) -> Text {
        Text(
            """
            Look for \(icon) at the top of your screen. From there, \(app.name) shows you a card every so often. If \
            you can't see the icon, open \(app.name) again to reach your cards.
            """,
            comment: """
                On the Welcome page, under that the app lives in the menu bar. The first value is the app's icon in \
                the menu bar, drawn in the text, or its name for VoiceOver, which a text of its own translates to fit \
                this sentence. The other two are the app's name.
                """)
    }

    /// The name VoiceOver reads for the menu bar's icon in `whereItLives(icon:)`.
    private var iconName: String {
        String(
            localized: "the \(app.name) icon",
            comment: """
                What VoiceOver reads for the app's icon in the menu bar on the Welcome page, inside the sentence “Look \
                for %@ at the top of your screen”, so it takes the form that sentence needs. The name is the app's.
                """)
    }

    /// The buttons, at the page's trailing side, the default one last, as an
    /// alert has them.
    private var buttons: some View {
        HStack {
            Spacer()
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
    }
}

extension AppOpening.Launch {
    /// How this launch came, from the Apple event AppKit is handling, which
    /// `applicationDidFinishLaunching` alone can ask: a probe on macOS 26.3.1
    /// found no event yet in `applicationWillFinishLaunching`, and none in the
    /// main queue's next turn. A launch with nothing to open has
    /// `kAEOpenApplication` there, which AppKit sends itself when nobody did,
    /// so running the executable has it too. A link's launch has no event by
    /// then, since `application(_:open:)` took its own before, and neither has
    /// AppleScript's `launch`, so silence wins for what doesn't say it's by
    /// hand. Reading `keyAELaunchedAsLogInItem` from the event's `keyAEPropData`
    /// is our own, from community code: Apple doesn't say where to read it, nor
    /// connect it to `SMAppService.mainApp`, so a real login is a hand check.
    static var fromCurrentAppleEvent: AppOpening.Launch {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventClass == AEEventClass(kCoreEventClass), event.eventID == AEEventID(kAEOpenApplication)
        else {
            return .forSomethingElse
        }
        let launchedAs = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        return launchedAs == OSType(keyAELaunchedAsLogInItem) ? .atLogin : .byHand
    }
}
