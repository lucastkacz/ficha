import AppKit
import SwiftUI

/// A tab of the Settings window. Its raw value is how the preferences store
/// it, and its tab's identifier, so it never changes.
enum SettingsTab: String {
    case general
    case appearances
    case reviewPanel
    case ladder
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
        case .ladder: String(localized: "Ladder", comment: "A tab of the Settings window.")
        case .about: String(localized: "About", comment: "A tab of the Settings window.")
        }
    }

    /// The tab's icon.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearances: "clock"
        case .reviewPanel: "macwindow"
        case .ladder: "stairs"
        case .about: "info.circle"
        }
    }
}

/// The Settings window's content, as a Mac's usual settings window: its tabs
/// in the toolbar, each as tall as its settings, so none scrolls, and the
/// window as tall as the selected tab. The last tab says which version of the
/// app this is. It opens on the tab Lucas left it on last.
final class SettingsTabViewController: NSTabViewController {
    /// The tabs of every default Lucas can change in `model`, and of the
    /// capture shortcut, `captureShortcut`, then the About tab.
    convenience init(model: AppModel, captureShortcut: CaptureShortcutRegistration) {
        self.init(nibName: nil, bundle: nil)
        // Read before adding the tabs, since adding the first one selects it.
        let lastTab = Preferences.settingsTab
        tabStyle = .toolbar
        add(.general, settings: GeneralSettings(model: model, captureShortcut: captureShortcut))
        add(.appearances, settings: AppearancesSettings(model: model))
        add(.reviewPanel, settings: ReviewPanelSettings(model: model))
        add(.ladder, settings: LadderSettings(ladder: Bindable(model).settings.ladder))
        add(.about, content: AboutTab())
        if let index = tabViewItems.firstIndex(where: { SettingsTab(of: $0) == lastTab }) {
            selectedTabViewItemIndex = index
        }
    }

    /// Adds `tab`, which shows `settings` in a grouped form.
    private func add(_ tab: SettingsTab, settings: some View) {
        add(tab, content: Form { settings }.formStyle(.grouped))
    }

    /// Adds `tab`, which shows `content`. The tab follows the content's
    /// height as it changes, as when Lucas adds a step to the ladder.
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
