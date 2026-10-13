import AppKit
import SwiftUI

/// Ficha lives in the menu bar only: no Dock icon and no main window
/// (`LSUIElement` in `project.yml`).
@main
struct FichaApp: App {
    var body: some Scene {
        MenuBarExtra("Ficha", systemImage: "character.book.closed") {
            Button("Salir") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
