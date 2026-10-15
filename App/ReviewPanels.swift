import FichaCore
import FichaData

/// The review panel, one at a time: opened by Lucas with review now, or on its
/// own, by an appearance.
final class ReviewPanels {
    private let model: AppModel
    private let mac: SystemMacSignals
    /// The last panel shown, open or not.
    private var panel: ReviewPanelWindow?

    init(model: AppModel, mac: SystemMacSignals) {
        self.model = model
        self.mac = mac
    }

    /// Whether the panel is open.
    var isOpen: Bool {
        panel?.isVisible == true
    }

    /// Opens the panel with the cards a review now brings, or, when it's
    /// already open, brings it forward, so Lucas goes on with its cards.
    /// Either way it takes the keyboard.
    func openReviewNow() {
        if let panel, panel.isVisible {
            panel.bringForward()
            return
        }
        let panel = ReviewPanelWindow(model: model.startReviewNow())
        panel.show()
        self.panel = panel
    }

    /// Shows the panel on its own with these cards: an appearance.
    func showAppearance(_ cards: [PanelCard]) {
        let panel = ReviewPanelWindow(model: .success(model.startAppearance(with: cards)))
        panel.showOnItsOwn(settings: model.settings, mac: mac)
        self.panel = panel
    }

    /// Closes the open panel on its own: as the Mac or its screens go to
    /// sleep.
    func closeOnItsOwn() {
        guard let panel, panel.isVisible else { return }
        panel.closeOnItsOwn()
    }

    /// Closes the open panel as Esc does: as Ficha quits.
    func closeAsLucasWould() {
        guard let panel, panel.isVisible else { return }
        panel.closeAsLucasWould()
    }
}
