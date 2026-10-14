import AppKit
import SwiftUI

/// Ficha lives in the menu bar only: no Dock icon and no main window
/// (`LSUIElement` in `project.yml`).
@main
struct FichaApp: App {
    private let variant = AppVariant.current

    var body: some Scene {
        MenuBarExtra(variant.name, systemImage: variant.menuBarSymbol) {
            Button("Salir") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
