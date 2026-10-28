import FichaCore
import FichaData

/// The review panel, one at a time: opened by Lucas with review now, or on its
/// own, by an appearance.
final class ReviewPanel {
    private let model: AppModel
    private let mac: SystemMacSignals
    /// The panel's window, from the last time it showed.
    private var window: ReviewPanelWindow?
    /// What to do as a panel opens, and once it closed, however it closes:
    /// the widget's reloads wait for it.
    var whenOpened: () -> Void = {}
    var whenClosed: () -> Void = {}

    init(model: AppModel, mac: SystemMacSignals) {
        self.model = model
        self.mac = mac
    }

    /// Whether the panel is open.
    var isOpen: Bool {
        window?.isVisible == true
    }

    /// Opens the panel with the cards a review now brings, starting with
    /// `first`, the card the widget showed, while review now still brings it.
    /// When it's already open, it comes forward, so Lucas goes on with its
    /// cards, unless he went through them and the widget showed a card: then
    /// the review now opens in its place. Either way it takes the keyboard.
    func openReviewNow(startingWith first: CardWay? = nil) {
        if let window, window.isVisible {
            guard window.givesWay(toAReviewNowStartingWith: first) else {
                window.bringForward()
                return
            }
            window.close(.byLucas)
        }
        let window = ReviewPanelWindow(model: model.startReviewNow(startingWith: first))
        window.show()
        opened(window)
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
        opened(window)
    }

    /// Keeps `window`, which just showed, as the panel's, and says so, and
    /// once it closed.
    private func opened(_ window: ReviewPanelWindow) {
        window.whenClosed = { [weak self] in self?.whenClosed() }
        self.window = window
        whenOpened()
    }
}
