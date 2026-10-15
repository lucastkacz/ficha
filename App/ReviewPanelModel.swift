import FichaCore
import FichaData
import Observation

/// The cards a review now or an appearance brought, as the review panel shows
/// them, one at a time: Lucas ends a new card's first view with "Got it", and
/// flips and rates a due card. The engine's `ReviewPanelState` keeps what
/// happens to the cards and to the panel, and this model adds what only the
/// panel shows: a card's back, how long Lucas took, and why an answer
/// couldn't be saved.
@Observable
final class ReviewPanelModel {
    /// What the panel shows.
    enum Content {
        /// Review now brought no cards: none is due, and no new card is
        /// waiting today.
        case nothingToReview
        /// A new card, whole, for its first view.
        case firstView(Card)
        /// A due card's front, for Lucas to remember its back.
        case front(Card)
        /// A due card's front and back, for Lucas to rate it.
        case back(Card)
        /// Lucas answered every card.
        case done
    }

    private var state: ReviewPanelState
    private var isFlipped = false
    /// When the panel showed the current card: Lucas's response time runs from
    /// then to his answer. It's measured on the system's steady clock, since
    /// it's how long he took, not a time of day, so moving Ficha Dev's time
    /// doesn't change it.
    private var cardShownAt = ContinuousClock.now
    /// Why Lucas's last answer couldn't be saved, while the panel says so.
    var failure: EngineError?

    /// The panel for the cards in `state`, which shows them from now on.
    init(_ state: ReviewPanelState) {
        self.state = state
    }

    var content: Content {
        guard !state.cards.isEmpty else {
            return .nothingToReview
        }
        guard let current = state.current else {
            return .done
        }
        return switch current {
        case .firstView(let card): .firstView(card)
        case .review(let card): isFlipped ? .back(card) : .front(card)
        }
    }

    /// Whether the panel closed: Lucas answered every card or closed it, or
    /// it closed on its own.
    var isClosed: Bool {
        state.outcome != nil
    }

    /// Whether the panel may have the keyboard: when Lucas opened it, or in
    /// an appearance, once the focus mode says so or Lucas clicks it.
    var mayHaveKeyboard: Bool {
        state.mayHaveKeyboard
    }

    /// Turns the due card to its back.
    func flip() {
        guard case .front = content else { return }
        isFlipped = true
        state.touch()
    }

    /// Ends the new card's first view, which puts it on the ladder's first
    /// step: "Got it".
    func endFirstView() {
        guard case .firstView = content else { return }
        answer(.firstView)
    }

    /// Rates the due card, once flipped, which moves it on the ladder.
    func rate(_ rating: Rating) {
        guard case .back = content else { return }
        answer(.review(rating))
    }

    /// Notes that Lucas clicked the panel, which gives it the keyboard.
    func clicked() {
        state.clicked()
    }

    /// Whether the panel takes the keyboard now, as the focus mode says, by
    /// how long `mac` says Lucas has been idle.
    func takesKeyboard(on mac: some MacSignals) -> Bool {
        state.takesKeyboard(on: mac)
    }

    /// Closes the panel: Lucas closes it, or it closes on its own.
    func close(_ closing: ReviewPanelState.Closing) {
        state.close(closing)
    }

    /// Closes the panel on its own once it's been untouched for a while.
    func closeIfUntouched() {
        state.closeIfUntouched()
    }

    /// Saves Lucas's answer to the current card, with his response time, and
    /// moves on to the next card, or closes the panel after the last one.
    /// When it can't be saved, the card stays, and the panel says why.
    private func answer(_ kind: ReviewLogEntry.Kind) {
        do {
            try state.answer(kind, responseTime: ContinuousClock.now - cardShownAt)
        } catch {
            failure = error
            return
        }
        isFlipped = false
        cardShownAt = .now
    }
}
