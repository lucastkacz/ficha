import AppKit
import SwiftUI

/// The menu under Ficha's icon in the menu bar.
struct MenuContent: View {
    let model: AppModel
    /// Opens the capture window.
    let openCapture: () -> Void
    /// The shortcut that opens the capture window from any app, which the
    /// menu shows next to "Capture…" while it's on.
    let captureShortcut: CaptureShortcutRegistration
    /// Opens the review panel with the cards a review now brings.
    let openReviewPanel: () -> Void
    /// Opens the Diagnostics window.
    let openDiagnostics: () -> Void
    /// Opens the Settings window.
    let openSettings: () -> Void
    /// Asks right away whether the review panel shows up on its own, for
    /// Ficha Dev's debug menu.
    let checkAppearance: () -> AppearanceCheck?

    var body: some View {
        Button("Capture…", action: openCapture)
            .keyboardShortcut(captureShortcut.shortcut?.keyboardShortcut)
        Button(reviewNowTitle, action: openReviewPanel)
        Divider()
        Text(progressLine)
        Button("Diagnostics", action: openDiagnostics)
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        if let debugTools = model.debugTools {
            Divider()
            DebugMenu(
                tools: debugTools, settings: model.settings, timeMoved: model.countProgress,
                checkAppearance: checkAppearance, captureShortcut: captureShortcut)
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// "Review now", with how many cards are due when some are.
    private var reviewNowTitle: String {
        guard let due = model.progress?.due, due > 0 else {
            return String(localized: "Review now")
        }
        return String(localized: "Review now (\(due) due)")
    }

    /// How many cards Lucas learned and how many captures and flagged cards
    /// wait in the inbox, in words. The String Catalog words each count for
    /// zero, one and more.
    private var progressLine: String {
        guard let progress = model.progress else {
            return String(localized: "Couldn't count your progress")
        }
        return String(
            localized: "\(progress.learned) cards learned · \(progress.inInbox) in the inbox",
            comment: """
                The menu's progress line: how many cards Lucas learned, and how many captures and flagged cards wait \
                in the inbox.
                """
        )
    }
}
