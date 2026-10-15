import AppKit
import SwiftUI

/// The menu under Ficha's icon in the menu bar.
struct MenuContent: View {
    let model: AppModel
    /// Opens the review panel with the cards review now brings.
    let reviewNow: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capturar…") {
            // A menu-bar app isn't active until it's asked to be, and the
            // window only takes the keyboard in an active app.
            NSApplication.shared.activate()
            openWindow(id: CaptureView.windowID)
        }
        Button(reviewNowTitle, action: reviewNow)
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
        switch model.progress?.due {
        case nil, 0: "Repasar ahora"
        case 1: "Repasar ahora (1 vencida)"
        case let count?: "Repasar ahora (\(count) vencidas)"
        }
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
            case 1: "1 ficha aprendida"
            case let count: "\(count) fichas aprendidas"
            }
        let inbox =
            switch progress.capturesInInbox {
            case 0: "la bandeja está vacía"
            case 1: "1 captura en la bandeja"
            case let count: "\(count) capturas en la bandeja"
            }
        return "\(learned) · \(inbox)"
    }
}
