import AppKit
import FichaData
import Observation
import SwiftUI

extension SettingsTab {
    /// The tab `item` shows, if it's one of these.
    init?(of item: NSTabViewItem?) {
        guard let identifier = item?.identifier as? String else { return nil }
        self.init(rawValue: identifier)
    }

    /// The tab's name, under its icon and in the window's title.
    var name: String {
        switch self {
        case .general: String(localized: "General", comment: "A tab of the Settings window.")
        case .pace:
            String(
                localized: "Pace",
                comment: """
                    A tab of the Settings window: how fast new cards come, and the queue of decks they come from.
                    """)
        case .interruptions:
            String(
                localized: "Interruptions",
                comment: """
                    A tab of the Settings window: when the review panel shows up on its own, what holds it back, and \
                    how it behaves once it's up.
                    """)
        case .sync: String(localized: "Sync", comment: "A tab of the Settings window: sync through iCloud.")
        case .advanced:
            String(
                localized: "Advanced",
                comment: """
                    A tab of the Settings window: when cards come back, as Anki's deck options set it, the backups and \
                    Diagnostics.
                    """)
        }
    }

    /// The tab's icon.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .pace: "speedometer"
        case .interruptions: "clock"
        case .sync: "icloud"
        case .advanced: "slider.horizontal.3"
        }
    }
}

/// Where a tab of Settings scrolls to, as Settings is asked to show one of
/// its sections, such as Advanced's Backups, which "Last backup failed" in
/// the menu opens: each request scrolls once, even to the section asked for
/// before.
@Observable
final class SettingsScroll {
    /// The section asked for last, or nil while none was.
    private(set) var section: SettingsSection?
    /// How many times a section was asked for, so a tab scrolls each time.
    private(set) var requests = 0

    /// Asks the tab that holds `section` to scroll to it.
    func scroll(to section: SettingsSection) {
        self.section = section
        requests += 1
    }
}

/// The Settings window's content, as a Mac's usual settings window: its five
/// tabs in the toolbar (#492), each as tall as its settings, so none scrolls,
/// but Advanced, taller than a screen, which scrolls at the height of
/// Interruptions, the next tallest; and the window as tall as the selected
/// tab and as wide as its toolbar's tabs need, 500 points at least. It opens
/// on the tab Lucas left it on last, unless it's asked to open on another.
final class SettingsTabViewController: NSTabViewController {
    /// How tall Advanced is, past which it scrolls: Interruptions' height, as
    /// `make render`'s pictures of the two measured it.
    private static let advancedHeight: CGFloat = 739
    /// How wide every tab is, and so the window.
    private var width: CGFloat = 500
    /// Where a tab scrolls to, as Settings is asked to show a section.
    private let scroll = SettingsScroll()

    /// The tabs of every default Lucas can change in `model`, and of the
    /// capture shortcut, `captureShortcut`, with the Sync tab in an app that
    /// syncs: Advanced closes the review panel with `closeReviewPanel` before
    /// a restore, and opens the Diagnostics window with `openDiagnostics`.
    /// It opens on `tab`, scrolled to `section` when it's one of the tab's,
    /// or on the tab Lucas left it on last, when the window has it.
    convenience init(
        model: AppModel, captureShortcut: CaptureShortcutRegistration, closeReviewPanel: @escaping () -> Void,
        openDiagnostics: @escaping () -> Void, openingOn tab: SettingsTab? = nil, at section: SettingsSection? = nil
    ) {
        self.init(nibName: nil, bundle: nil)
        // Read before adding the tabs, since adding the first one selects it.
        let firstTab = tab ?? Preferences.settingsTab
        tabStyle = .toolbar
        let tabs = SettingsTab.shown(syncing: model.sync != nil)
        width = Self.width(showing: tabs)
        for shown in tabs {
            add(
                shown,
                content: SettingsTabContent(
                    tab: shown, model: model, captureShortcut: captureShortcut, width: width,
                    closeReviewPanel: closeReviewPanel, openDiagnostics: openDiagnostics, scroll: scroll))
        }
        select(firstTab, at: section)
    }

    /// How wide Settings is with `tabs` in its toolbar: 500 points, or as
    /// wide as the toolbar needs to show every tab's name, since a name can't
    /// wrap and AppKit hides the tabs that don't fit behind ». The forms
    /// inside keep wrapping their texts, and Advanced's table of copies fits
    /// by narrowing its Kind column, whose texts wrap too
    /// (`CopyTableColumns`). Our own sum of AppKit's toolbar, as `make
    /// render`'s pictures measure it: each name in the toolbar's font, at
    /// least as wide as an icon, the room between two tabs and at the
    /// window's edges.
    private static func width(showing tabs: [SettingsTab]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let names = tabs.map { max($0.name.width(in: font), 32) }
        let toolbar = names.reduce(0, +) + 14 * CGFloat(tabs.count - 1) + 2 * 24
        return max(500, toolbar.rounded(.up))
    }

    /// Shows `tab`, scrolled to `section` when it's one of the tab's.
    func select(_ tab: SettingsTab, at section: SettingsSection? = nil) {
        if let index = tabViewItems.firstIndex(where: { SettingsTab(of: $0) == tab }) {
            selectedTabViewItemIndex = index
        }
        if let section, tab.sections.contains(section) {
            scroll.scroll(to: section)
        }
    }

    /// Adds `tab`, which shows `content`, as wide as every tab, and, for
    /// Advanced, `advancedHeight` tall. Each other tab follows its content's
    /// height as it changes, as Sync does when Lucas picks to sync only the
    /// cards in chosen decks.
    private func add(_ tab: SettingsTab, content: some View) {
        let sized = content.frame(width: width).frame(idealHeight: tab == .advanced ? Self.advancedHeight : nil)
        let controller = NSHostingController(rootView: sized)
        controller.sizingOptions = .preferredContentSize
        controller.title = tab.name
        let item = NSTabViewItem(viewController: controller)
        item.identifier = tab.rawValue
        item.label = tab.name
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
        addTabViewItem(item)
    }

    /// Keeps the tab Lucas picks, for the next time Settings opens.
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let tab = SettingsTab(of: tabViewItem) {
            Preferences.settingsTab = tab
        }
        keepTheKeyboardOutOfTheAdvancedTab()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keepTheKeyboardOutOfTheAdvancedTab()
    }

    /// Leaves the keyboard with the window when the Advanced tab shows, as
    /// Settings opens on it or Lucas picks it: AppKit gives it to the tab's
    /// Longest interval field, Settings' only text field, with its number
    /// selected, where a stray keystroke would change a setting that syncs.
    /// A click or Tab puts it there.
    private func keepTheKeyboardOutOfTheAdvancedTab() {
        guard SettingsTab(of: tabView.selectedTabViewItem) == .advanced else { return }
        view.window?.makeFirstResponder(nil)
    }
}
