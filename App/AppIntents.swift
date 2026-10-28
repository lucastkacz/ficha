import AppIntents
import os

/// The App Intents' log, which says when macOS runs one, and what it brings.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "intents")

/// Ficha's Focus filter: added to a Focus of macOS in System Settings, its
/// switch holds appearances back while that Focus is on (#166). Its `current`
/// value is the switch as the user left it while the Focus is on, and off
/// otherwise, which `SystemMacSignals` reads every few seconds. macOS also
/// runs `perform` with it as the Focus turns on or off, but only once it's
/// connected to the app, as #307's probe found on macOS 26.3.
struct HoldBackAppearancesFilter: SetFocusFilterIntent {
    static let title = LocalizedStringResource(
        "Hold Back Appearances", comment: "The name of the app's filter in a Focus, in System Settings.")
    static let description: IntentDescription? = IntentDescription(
        LocalizedStringResource(
            "Holds back appearances while this Focus is on. Review now still works.",
            comment: "What the app's filter in a Focus does, in System Settings."))

    @Parameter(
        title: LocalizedStringResource(
            "Hold back appearances", comment: "The switch in the app's filter in a Focus, in System Settings."),
        default: false)
    var holdsBack: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: holdsBack
                ? LocalizedStringResource(
                    "Holds back appearances", comment: "The app's filter in a Focus, with its switch on.")
                : LocalizedStringResource(
                    "Doesn't hold back appearances", comment: "The app's filter in a Focus, with its switch off."))
    }

    /// Holds appearances back, or stops, without waiting for the next read.
    /// Before the app launched with its cards there's nothing to hold back:
    /// it reads the filter as it starts.
    @MainActor
    func perform() async throws -> some IntentResult {
        logger.info("A Focus holds appearances back now: \(holdsBack, privacy: .public)")
        AppDelegate.launched?.focusChanged(holdsBack: holdsBack)
        return .result()
    }
}

/// "Review now" in the Shortcuts app, Spotlight and a keyboard shortcut the
/// user sets (#170): it does what the menu's Review now does, without
/// bringing Ficha forward, since the review panel never activates it.
struct ReviewNowIntent: AppIntent {
    static let title = LocalizedStringResource(
        "Review Now", comment: "The name of the app's action in the Shortcuts app and Spotlight.")
    static let description: IntentDescription? = IntentDescription(
        LocalizedStringResource(
            "Opens the review panel with the cards that are due, as the menu's Review now does.",
            comment: "What the app's Review Now action does, in the Shortcuts app."))
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.launched else {
            throw CardsNotOpen(
                localizedStringResource: LocalizedStringResource(
                    "\(AppVariant.current.name) can't open your cards. Open it to see why.",
                    comment: """
                        An error from the app's Review Now action, when the app couldn't open its cards at launch. \
                        Opening the app again shows an alert that says why.
                        """))
        }
        logger.info("Review now from an App Intent")
        app.openReviewPanel()
        return .result()
    }
}

/// The shortcuts Ficha offers from install, with no shortcut made by hand.
struct FichaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReviewNowIntent(), phrases: ["Review now in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Review Now", comment: "The name of the app's action in the Shortcuts app and Spotlight."),
            systemImageName: "rectangle.stack")
    }
}

/// Why an App Intent couldn't run: the app couldn't open its cards, as it
/// said at launch, before quitting.
private struct CardsNotOpen: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource
}
