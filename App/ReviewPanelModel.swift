import FichaData
import Observation

/// The review panel's state, which its window and its view share: the window
/// gives the panel the keyboard and closes it, and the view draws the state
/// and passes on what Lucas does. `ReviewPanelState` decides it all; this
/// holder only lets the two observe it.
@Observable
final class ReviewPanelModel {
    /// The cards a review now or an appearance brought, as the panel shows
    /// them.
    var state: ReviewPanelState

    /// The panel for the cards in `state`, which shows them from now on.
    init(_ state: ReviewPanelState) {
        self.state = state
    }
}
