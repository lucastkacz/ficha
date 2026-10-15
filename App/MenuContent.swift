import AppKit
import SwiftUI

/// The menu under Ficha's icon in the menu bar.
struct MenuContent: View {
    let model: AppModel
    /// Opens the review panel with the cards a review now brings.
    let openReviewPanel: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capturar…") {
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
        Button("Salir") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// "Repasar ahora", with how many cards are due when some are.
    private var reviewNowTitle: String {
        guard let due = model.progress?.due, due > 0 else {
            return "Repasar ahora"
        }
        return "Repasar ahora (\(inWords(due, one: "vencida", many: "vencidas")))"
    }

    /// How many cards Lucas learned and how many captures wait in the inbox,
    /// in words.
    private var progressLine: String {
        guard let progress = model.progress else {
            return "No se pudo contar tu progreso"
        }
        let learned =
            switch progress.learned {
            case 0: "Ninguna ficha aprendida"
            case let count: inWords(count, one: "ficha aprendida", many: "fichas aprendidas")
            }
        let inbox =
            switch progress.capturesInInbox {
            case 0: "la bandeja está vacía"
            case let count: inWords(count, one: "captura en la bandeja", many: "capturas en la bandeja")
            }
        return "\(learned) · \(inbox)"
    }
}

/// A count in words, like "1 ficha" or "3 fichas".
private func inWords(_ count: Int, one: String, many: String) -> String {
    "\(count) \(count == 1 ? one : many)"
}
