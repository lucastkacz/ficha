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
    static let title: LocalizedStringResource = "Hold Back Appearances"
    static let description: IntentDescription? = IntentDescription(
        "Holds back appearances while this Focus is on. Review now still works.")

    @Parameter(title: "Hold back appearances", default: false)
    var holdsBack: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: holdsBack ? "Holds back appearances" : "Doesn't hold back appearances")
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
    static let title: LocalizedStringResource = "Review Now"
    static let description: IntentDescription? = IntentDescription(
        "Opens the review panel with the cards that are due, as the menu's Review now does.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.launched else {
            throw CardsNotOpen(
                localizedStringResource: "\(AppVariant.current.name) can't open your cards")
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
            intent: ReviewNowIntent(), phrases: ["Review now in \(.applicationName)"], shortTitle: "Review Now",
            systemImageName: "rectangle.stack")
    }
}

/// Why an App Intent couldn't run: the app couldn't open its cards, as it
/// said at launch, before quitting.
private struct CardsNotOpen: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource
}
