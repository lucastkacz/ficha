import AppKit
import FichaCore
import FichaData
import SwiftUI

/// A deck in the menu bar's Prioritize submenu, by its emoji and its last
/// level under its parent: an item ticked while it's a priority deck, which toggles it, off
/// while it's set aside, on its own or inside a deck that is, unless it's a
/// priority deck, to untick; or, for a parent, a submenu that lists that item
/// first, then the decks right inside it.
private struct PrioritizeDeckItem: View {
    let item: PrioritizeMenu.DeckItem
    /// Toggles the priority of the deck with a whole name.
    let toggle: (String) -> Void

    var body: some View {
        if item.children.isEmpty {
            toggleItem
        } else {
            Menu(item.shownTitle) {
                toggleItem
                Divider()
                ForEach(item.children) { child in
                    PrioritizeDeckItem(item: child, toggle: toggle)
                }
            }
        }
    }

    /// The item that toggles the deck's priority.
    private var toggleItem: some View {
        Toggle(isOn: Binding(get: { item.isTicked }, set: { _ in toggle(item.deck.name) })) {
            Text(verbatim: item.shownTitle)
        }
        .disabled(!item.isEnabled)
    }
}

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
    /// Opens the Settings window on its Sync tab.
    let openSyncSettings: () -> Void
    /// Asks right away whether the review panel shows up on its own, for
    /// Ficha Dev's debug menu.
    let checkAppearance: () -> AppearanceCheck?
    /// What to do once Ficha Dev's debug menu moved its time forward.
    let timeMoved: () -> Void
    /// What Ficha Dev's debug menu does with its second device and with sync.
    let secondDevice: SecondDeviceActions

    var body: some View {
        let saysICloudIsFull = model.sync?.saysICloudIsFull == true
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
        }
        if saysICloudIsFull {
            Button(action: openSyncSettings) {
                Label {
                    Text(
                        "iCloud is full",
                        comment: """
                            A menu item while iCloud is full, which opens Settings' Sync tab, where it says changes wait \
                            until there's room.
                            """)
                } icon: {
                    Image(systemName: "exclamationmark.icloud")
                }
            }
        }
        if model.backups.lastBackupFailed || saysICloudIsFull {
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

    /// The Prioritize submenu, with what the engine offers (ADR 0011, ADR
    /// 0024): "None", ticked while no deck is a priority deck, which clears
    /// them; then every deck as a tree, Default first while it holds cards or
    /// has a switch on, each ticked while it's a priority deck, which toggles
    /// it, and off while it's set aside, on its own or inside a deck that
    /// is. A parent is a submenu that lists itself first, then the decks
    /// right inside it. A divider sets the decks apart. A change applies from
    /// the next appearance, review now or "See more" on.
    private var prioritizeSubmenu: some View {
        Menu(prioritizeTitle) {
            if let menu = model.prioritizeMenu {
                Toggle(
                    isOn: Binding(
                        get: { menu.isNoneTicked },
                        set: { _ in changePriority { () throws(EngineError) in try model.clearPriorityDecks() } })
                ) {
                    Text(
                        "None",
                        comment:
                            "In the menu's Prioritize submenu: no deck is a priority deck. Choosing it clears them.")
                }
                if !menu.decks.isEmpty {
                    Divider()
                }
                ForEach(menu.decks) { item in
                    PrioritizeDeckItem(item: item, toggle: togglePriority(ofDeck:))
                }
            } else {
                Text("Couldn't read your decks")
            }
        }
    }

    /// Toggles the priority of the deck `deck`, as its item in the
    /// Prioritize submenu does.
    private func togglePriority(ofDeck deck: String) {
        changePriority { () throws(EngineError) in try model.togglePriority(ofDeck: deck) }
    }

    /// "Prioritize", naming the priority decks while there are some, so Lucas
    /// sees that priority is on without opening the submenu.
    private var prioritizeTitle: String {
        let names = (model.prioritizeMenu?.priorityDeckNames ?? []).map(Deck.shownName)
        guard !names.isEmpty else {
            return String(
                localized: "Prioritize",
                comment: "A menu-bar submenu that picks the decks whose cards come first, while none is picked.")
        }
        return String(
            localized: "Prioritize: \(names.formatted(.list(type: .and, width: .narrow)))",
            comment: "The Prioritize submenu's title while some decks are priority decks, which it lists by name.")
    }

    /// Makes a change to the priority decks, or says in an alert why it
    /// couldn't be saved, as when the deck was set aside meanwhile.
    private func changePriority(_ change: () throws(EngineError) -> Void) {
        do {
            try change()
        } catch {
            showAlert(
                String(localized: "Couldn't change the priority decks"), explaining: error, style: .warning,
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
