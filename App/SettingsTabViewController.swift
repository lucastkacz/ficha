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
/// window as tall as the selected tab. The last tab says which version of the
/// app this is. It opens on the tab Lucas left it on last, unless it's asked
/// to open on another.
final class SettingsTabViewController: NSTabViewController {
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
        add(.general, settings: GeneralSettings(model: model, captureShortcut: captureShortcut))
        // Each of these changes one of the settings that decide a card's
        // progress, which the engine keeps.
        add(.appearances, content: ProgressSettingsForm(model: model, settings: AppearancesSettings(model: model)))
        add(.reviewPanel, content: ProgressSettingsForm(model: model, settings: ReviewPanelSettings(model: model)))
        add(
            .scheduling,
            content: ProgressSettingsForm(
                model: model, settings: SchedulingSettings(scheduler: Bindable(model).settings.scheduler)))
        add(.backups, content: BackupsTab(model: model, closeReviewPanel: closeReviewPanel))
        if model.sync != nil {
            add(.sync, content: SyncTab(model: model))
        }
        add(.about, content: AboutTab())
        select(firstTab)
    }

    /// Shows `tab`.
    func select(_ tab: SettingsTab) {
        if let index = tabViewItems.firstIndex(where: { SettingsTab(of: $0) == tab }) {
            selectedTabViewItemIndex = index
        }
    }

    /// Adds `tab`, which shows `settings` in a grouped form.
    private func add(_ tab: SettingsTab, settings: some View) {
        add(tab, content: Form { settings }.formStyle(.grouped))
    }

    /// Adds `tab`, which shows `content`. The tab follows the content's
    /// height as it changes, as when Lucas adds a learning step.
    private func add(_ tab: SettingsTab, content: some View) {
        let controller = NSHostingController(rootView: content.frame(width: 500))
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
    }
}
