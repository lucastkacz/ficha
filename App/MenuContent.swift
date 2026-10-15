import AppKit
import SwiftUI

/// The menu under Ficha's icon in the menu bar.
struct MenuContent: View {
    let model: AppModel
    /// Opens the review panel with the cards a review now brings.
    let openReviewPanel: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capture…") {
            // A menu-bar app isn't active until it's asked to be, and the
            // window only takes the keyboard in an active app.
            NSApplication.shared.activate()
            openWindow(id: CaptureView.windowID)
        }
        Button(reviewNowTitle, action: openReviewPanel)
        Divider()
        Text(progressLine)
        if let debugTools = model.debugTools {
            Divider()
            DebugMenu(tools: debugTools, timeMoved: model.countProgress)
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

    /// How many cards Lucas learned and how many captures wait in the inbox,
    /// in words. The String Catalog holds the singular and plural of each
    /// count.
    private var progressLine: String {
        guard let progress = model.progress else {
            return String(localized: "Couldn't count your progress")
        }
        let learned =
            switch progress.learned {
            case 0: String(localized: "No cards learned")
            case let count: String(localized: "\(count) cards learned")
            }
        let inbox =
            switch progress.capturesInInbox {
            case 0: String(localized: "the inbox is empty")
            case let count: String(localized: "\(count) captures in the inbox")
            }
        return "\(learned) · \(inbox)"
    }
}
