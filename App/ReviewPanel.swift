import FichaCore
import FichaData

/// The review panel, one at a time: opened by Lucas with review now, or on its
/// own, by an appearance.
final class ReviewPanel {
    private let model: AppModel
    private let mac: SystemMacSignals
    /// The panel's window, from the last time it showed.
    private var window: ReviewPanelWindow?

    init(model: AppModel, mac: SystemMacSignals) {
        self.model = model
        self.mac = mac
    }

    /// Whether the panel is open.
    var isOpen: Bool {
        window?.isVisible == true
    }

    /// Opens the panel with the cards a review now brings, or, when it's
    /// already open, brings it forward, so Lucas goes on with its cards.
    /// Either way it takes the keyboard.
    func openReviewNow() {
        if let window, window.isVisible {
            window.bringForward()
            return
        }
        let window = ReviewPanelWindow(model: model.startReviewNow())
        window.show()
        self.window = window
    }

    /// Shows the panel on its own with these cards, an appearance, or why it
    /// couldn't open them.
    func showAppearance(_ cards: [PanelCard]) {
        showOnItsOwn(model.startAppearance(with: cards))
    }

    /// Shows the panel on its own, saying why there's no appearance: the
    /// engine couldn't check for one.
    func showFailure(_ failure: EngineError) {
        showOnItsOwn(.failure(failure))
    }

    /// Closes the open panel: Lucas closes it, as Ficha quits, or it closes
    /// on its own, as the Mac or its screens go to sleep.
    func close(_ closing: ReviewPanelState.Closing) {
        guard let window, window.isVisible else { return }
        window.close(closing)
    }

    private func showOnItsOwn(_ content: Result<ReviewPanelModel, EngineError>) {
        let window = ReviewPanelWindow(model: content)
        window.showOnItsOwn(mac: mac)
        self.window = window
    }
}
