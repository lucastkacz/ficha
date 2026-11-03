import AppKit
import SwiftUI

/// A tab of the Settings window. Its raw value is how the preferences store
/// it, and its tab's identifier, so it never changes.
enum SettingsTab: String {
    case general
    case appearances
    case reviewPanel
    /// Stored as the Ladder tab it replaced (#404), so Settings reopens on
    /// it.
    case scheduling = "ladder"
    case backups
    case sync
    case about

    /// The tab `item` shows, if it's one of these.
    init?(of item: NSTabViewItem?) {
        guard let identifier = item?.identifier as? String else { return nil }
        self.init(rawValue: identifier)
    }

    /// The tab's name, under its icon and in the window's title.
    var name: String {
        switch self {
        case .general: String(localized: "General", comment: "A tab of the Settings window.")
        case .appearances: String(localized: "Appearances", comment: "A tab of the Settings window.")
        case .reviewPanel: String(localized: "Review panel", comment: "A tab of the Settings window.")
        case .scheduling:
            String(
                localized: "Scheduling",
                comment: "A tab of the Settings window: when cards come back, as Anki's deck options set it.")
        case .backups: String(localized: "Backups", comment: "A tab of the Settings window.")
        case .sync: String(localized: "Sync", comment: "A tab of the Settings window: sync through iCloud.")
        case .about: String(localized: "About", comment: "A tab of the Settings window.")
        }
    }

    /// The tab's icon.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearances: "clock"
        case .reviewPanel: "macwindow"
        case .scheduling: "calendar.badge.clock"
        case .backups: "clock.arrow.circlepath"
        case .sync: "icloud"
        case .about: "info.circle"
        }
    }
}

/// The Settings window's content, as a Mac's usual settings window: its tabs
/// in the toolbar, each as tall as its settings, so none scrolls, and the
/// window as tall as the selected tab and as wide as its toolbar's tabs need,
/// 500 points at least. The last tab says which version of the
/// app this is. It opens on the tab Lucas left it on last, unless it's asked
/// to open on another.
final class SettingsTabViewController: NSTabViewController {
    /// How wide every tab is, and so the window.
    private var width: CGFloat = 500

    /// The tabs of every default Lucas can change in `model`, and of the
    /// capture shortcut, `captureShortcut`, then the Backups tab, which closes
    /// the review panel with `closeReviewPanel` before a restore, the Sync
    /// tab, in an app that syncs, and the About tab. It opens on `tab`, or on
    /// the tab Lucas left it on last, when the window has it.
    convenience init(
        model: AppModel, captureShortcut: CaptureShortcutRegistration, closeReviewPanel: @escaping () -> Void,
        openingOn tab: SettingsTab? = nil
    ) {
        self.init(nibName: nil, bundle: nil)
        // Read before adding the tabs, since adding the first one selects it.
        let firstTab = tab ?? Preferences.settingsTab
        tabStyle = .toolbar
        let tabs: [SettingsTab] =
            [.general, .appearances, .reviewPanel, .scheduling, .backups] + (model.sync != nil ? [.sync] : [])
            + [.about]
        width = Self.width(showing: tabs)
        for shown in tabs {
            add(
                shown,
                content: Self.content(
                    of: shown, width: width, model: model, captureShortcut: captureShortcut,
                    closeReviewPanel: closeReviewPanel))
        }
        select(firstTab)
    }

    /// What `tab` shows, `width` points wide.
    @ViewBuilder
    private static func content(
        of tab: SettingsTab, width: CGFloat, model: AppModel, captureShortcut: CaptureShortcutRegistration,
        closeReviewPanel: @escaping () -> Void
    ) -> some View {
        switch tab {
        case .general:
            Form { GeneralSettings(model: model, captureShortcut: captureShortcut) }.formStyle(.grouped)
        // Each of these three changes one of the settings that decide a
        // card's progress, which the engine keeps.
        case .appearances: ProgressSettingsForm(model: model, settings: AppearancesSettings(model: model))
        case .reviewPanel: ProgressSettingsForm(model: model, settings: ReviewPanelSettings(model: model))
        case .scheduling:
            ProgressSettingsForm(
                model: model, settings: SchedulingSettings(scheduler: Bindable(model).settings.scheduler))
        case .backups: BackupsTab(model: model, width: width, closeReviewPanel: closeReviewPanel)
        case .sync: SyncTab(model: model)
        case .about: AboutTab()
        }
    }

    /// How wide Settings is with `tabs` in its toolbar: 500 points, as in
    /// English, or as wide as the toolbar needs to show every tab's name in
    /// a language whose names run longer, as German's and French's do, since
    /// a name can't wrap and AppKit hides the tabs that don't fit behind ».
    /// The forms inside keep wrapping their texts, and the Backups tab's
    /// table of copies fits by narrowing its Kind column, whose texts wrap
    /// too (`CopyTableColumns`). Our own sum of AppKit's toolbar, as
    /// `make render`'s pictures measure it: each name in the toolbar's font,
    /// at least as wide as an icon, the room between two tabs and at the
    /// window's edges.
    private static func width(showing tabs: [SettingsTab]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let names = tabs.map { max(ColumnWidth.width(of: $0.name, in: font), 32) }
        let toolbar = names.reduce(0, +) + 14 * CGFloat(tabs.count - 1) + 2 * 24
        return max(500, toolbar.rounded(.up))
    }

    /// Shows `tab`.
    func select(_ tab: SettingsTab) {
        if let index = tabViewItems.firstIndex(where: { SettingsTab(of: $0) == tab }) {
            selectedTabViewItemIndex = index
        }
    }

    /// Adds `tab`, which shows `content`, as wide as every tab. The tab
    /// follows the content's height as it changes, as when Lucas adds a
    /// learning step.
    private func add(_ tab: SettingsTab, content: some View) {
        let controller = NSHostingController(rootView: content.frame(width: width))
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
        keepTheKeyboardOutOfTheSchedulingTab()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keepTheKeyboardOutOfTheSchedulingTab()
    }

    /// Leaves the keyboard with the window when the Scheduling tab shows, as
    /// Settings opens on it or Lucas picks it: AppKit gives it to the tab's
    /// Longest interval field, Settings' only text field, with its number
    /// selected, where a stray keystroke would change a setting that syncs.
    /// A click or Tab puts it there.
    private func keepTheKeyboardOutOfTheSchedulingTab() {
        guard SettingsTab(of: tabView.selectedTabViewItem) == .scheduling else { return }
        view.window?.makeFirstResponder(nil)
    }
}
