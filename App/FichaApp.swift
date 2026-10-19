import SwiftUI

/// Ficha lives in the menu bar only: no Dock icon and no main window
/// (`LSUIElement` in `project.yml`).
@main
struct FichaApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private let variant = AppVariant.current

    var body: some Scene {
        // Without a model, the database couldn't be opened, and the app quits
        // as soon as it has said why.
        MenuBarExtra(variant.name, systemImage: variant.menuBarSymbol) {
            if let model = appDelegate.model {
                MenuContent(
                    model: model, openCapture: appDelegate.openCapture,
                    captureShortcut: appDelegate.captureShortcut, openReviewPanel: appDelegate.openReviewPanel,
                    openDiagnostics: appDelegate.openDiagnostics, checkAppearance: appDelegate.checkAppearanceNow)
            }
        }
    }
}
