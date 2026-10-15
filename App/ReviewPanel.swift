import FichaCore
import FichaData
import Observation

/// The cards a review now brought, which the review panel goes through one at
/// a time: Lucas ends a new card's first view with "Entendido", and flips and
/// rates a due card. Each answer goes into the review log as he gives it, so
/// the cards he doesn't get to stay as they were.
@Observable
final class ReviewPanel {
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

    private let engine: Engine
    private let settings: ReviewSettings
    private let cards: [PanelCard]
    private var position = 0
    private var isFlipped = false
    /// When the panel showed the current card: Lucas's response time runs from
    /// then to his answer. It's measured on the system's steady clock, since
    /// it's how long he took, not a time of day, so moving Ficha Dev's time
    /// doesn't change it.
    private var shownAt = ContinuousClock.now
    /// Why Lucas's last answer couldn't be saved, while the panel says so.
    var failure: EngineError?

    /// The cards review now brings, from `engine`.
    init(engine: Engine, settings: ReviewSettings) throws(EngineError) {
        self.engine = engine
        self.settings = settings
        cards = try engine.reviewNow(settings)
    }

    var content: Content {
        guard !cards.isEmpty else {
            return .nothingToReview
        }
        guard position < cards.count else {
            return .done
        }
        return switch cards[position] {
        case .firstView(let card): .firstView(card)
        case .review(let card): isFlipped ? .back(card) : .front(card)
        }
    }

    /// Whether Lucas answered every card.
    var isDone: Bool {
        if case .done = content { true } else { false }
    }

    /// Turns the due card to its back.
    func flip() {
        guard case .front = content else { return }
        isFlipped = true
    }

    /// Ends the new card's first view, which puts it on the ladder's first
    /// step: "Entendido".
    func endFirstView() {
        guard case .firstView(let card) = content else { return }
        answer { responseTime throws(EngineError) in
            try engine.recordFirstView(of: card.id, responseTime: responseTime, trigger: .reviewNow)
        }
    }

    /// Rates the due card, once flipped, which moves it on the ladder.
    func rate(_ rating: Rating) {
        guard case .back(let card) = content else { return }
        answer { responseTime throws(EngineError) in
            try engine.recordReview(
                of: card.id, rating: rating, responseTime: responseTime, trigger: .reviewNow,
                ladder: settings.ladder)
        }
    }

    /// Saves an answer with Lucas's response time, and moves on to the next
    /// card. When it can't be saved, the card stays, and the panel says why.
    private func answer(_ save: (Duration) throws(EngineError) -> Void) {
        do {
            try save(ContinuousClock.now - shownAt)
        } catch {
            failure = error
            return
        }
        position += 1
        isFlipped = false
        shownAt = .now
    }
}
