import SwiftUI

/// Ficha lives in the menu bar only: no Dock icon and no main window
/// (`LSUIElement` in `project.yml`). `main.swift` starts it.
struct FichaApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private let variant = AppVariant.current

    var body: some Scene {
        // Without a model, the database couldn't be opened, and the app quits
        // as soon as it has said why.
        MenuBarExtra {
            if let model = appDelegate.model {
                MenuContent(
                    model: model, openCapture: appDelegate.openCapture,
                    captureShortcut: appDelegate.captureShortcut, openReviewPanel: appDelegate.openReviewPanel,
                    openCards: appDelegate.openCards, openDiagnostics: appDelegate.openDiagnostics,
                    openSettings: appDelegate.openSettings, openBackupSettings: appDelegate.openBackupSettings,
                    checkAppearance: appDelegate.checkAppearanceNow,
                    secondDevice: SecondDeviceActions(
                        openCards: appDelegate.openSecondDeviceCards, reviewNow: appDelegate.reviewNowOnSecondDevice,
                        syncNow: appDelegate.syncNow))
            }
        } label: {
            MenuBarIcon(variant: variant, model: appDelegate.model)
        }
    }
}

/// The app's icon in the menu bar, with how many cards are due when Lucas
/// turned that on in Settings and some are: off by default, so Ficha doesn't
/// pressure him.
private struct MenuBarIcon: View {
    let variant: AppVariant
    let model: AppModel?

    var body: some View {
        if let model, model.showsDueCount, let due = model.progress?.due, due > 0 {
            Label {
                Text(due, format: .number)
            } icon: {
                Image(systemName: variant.menuBarSymbol)
            }
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(Text("\(variant.name), \(due) due", comment: "The menu-bar icon, with the due count."))
        } else {
            Image(systemName: variant.menuBarSymbol)
                .accessibilityLabel(Text(verbatim: variant.name))
        }
    }
}
