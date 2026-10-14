import AppKit
import SwiftUI

/// The menu under Ficha's icon in the menu bar.
struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capturar…") {
            // A menu-bar app isn't active until it's asked to be, and the
            // window only takes the keyboard in an active app.
            NSApplication.shared.activate()
            openWindow(id: CaptureView.windowID)
        }
        Divider()
        Text(inboxLine)
        Divider()
        Button("Salir") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// How many captures wait in the inbox, in words.
    private var inboxLine: String {
        switch model.inboxCount {
        case nil: "No se pudo contar la bandeja"
        case 0: "La bandeja está vacía"
        case 1: "1 captura en la bandeja"
        case let count?: "\(count) capturas en la bandeja"
        }
    }
}
