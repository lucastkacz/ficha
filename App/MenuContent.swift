import AppKit
import FichaData
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
    /// Opens the Cards window.
    let openCards: () -> Void
    /// Opens the Diagnostics window.
    let openDiagnostics: () -> Void
    /// Opens the Settings window.
    let openSettings: () -> Void
    /// Opens the Settings window on its Backups tab.
    let openBackupSettings: () -> Void
    /// Asks right away whether the review panel shows up on its own, for
    /// Ficha Dev's debug menu.
    let checkAppearance: () -> AppearanceCheck?
    /// What to do once Ficha Dev's debug menu moved its time forward.
    let timeMoved: () -> Void
    /// What Ficha Dev's debug menu does with its second device and with sync.
    let secondDevice: SecondDeviceActions

    var body: some View {
        if model.backups.lastBackupFailed {
            Button(action: openBackupSettings) {
                Label {
                    Text(
                        "Last backup failed",
                        comment: """
                            A menu item while the last backup failed, which opens Settings' Backups tab, where it says \
                            why.
                            """)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            }
            Divider()
        }
        Button("Capture…", action: openCapture)
            .keyboardShortcut(captureShortcut.shortcut?.keyboardShortcut)
        Button(reviewNowTitle, action: openReviewPanel)
        prioritizeSubmenu
        Divider()
        Text(progressLine)
        Button(
            String(
                localized: "Cards…", comment: "A menu item that opens the Cards window, where Lucas sees all his cards."
            ),
            action: openCards)
        Button("Diagnostics", action: openDiagnostics)
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        if let debugTools = model.debugTools {
            Divider()
            DebugMenu(
                tools: debugTools, settings: model.settings, timeMoved: timeMoved,
                checkAppearance: checkAppearance, captureShortcut: captureShortcut, secondDevice: secondDevice)
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

    /// The Prioritize submenu, as the engine offers it: "None", ticked while
    /// no tag is a priority tag, which clears them, and then each tag, its
    /// emoji before its name, ticked while it's a priority tag, which toggles
    /// it. A change applies from the next appearance, review now or "See
    /// more" on.
    private var prioritizeSubmenu: some View {
        Menu(prioritizeTitle) {
            if let menu = model.prioritizeMenu {
                Toggle(
                    isOn: Binding(
                        get: { menu.isNoneTicked },
                        set: { _ in changePriority { () throws(EngineError) in try model.clearPriorityTags() } })
                ) {
                    Text(
                        "None",
                        comment: "In the menu's Prioritize submenu: no tag is a priority tag. Choosing it clears them.")
                }
                if !menu.tags.isEmpty {
                    Divider()
                }
                ForEach(menu.tags, id: \.name) { tag in
                    Toggle(
                        isOn: Binding(
                            get: { tag.isPriority },
                            set: { _ in
                                changePriority { () throws(EngineError) in try model.togglePriority(of: tag.name) }
                            })
                    ) {
                        Text(verbatim: tag.title)
                    }
                }
            } else {
                Text("Couldn't read your tags")
            }
        }
    }

    /// "Prioritize", naming the priority tags while there are some, so Lucas
    /// sees that priority is on without opening the submenu.
    private var prioritizeTitle: String {
        let names = model.prioritizeMenu?.priorityTagNames ?? []
        guard !names.isEmpty else {
            return String(
                localized: "Prioritize",
                comment: "A menu-bar submenu that picks the tags whose cards come first, while none is picked.")
        }
        return String(
            localized: "Prioritize: \(names.formatted(.list(type: .and, width: .narrow)))",
            comment: "The Prioritize submenu's title while some tags are priority tags, which it lists by name.")
    }

    /// Makes a change to the priority tags, or says in an alert why it
    /// couldn't be saved.
    private func changePriority(_ change: () throws(EngineError) -> Void) {
        do {
            try change()
        } catch {
            showAlert(
                String(localized: "Couldn't change the priority tags"), explaining: error, style: .warning,
                button: String(localized: "OK"))
        }
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
