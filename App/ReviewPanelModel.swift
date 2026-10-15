import FichaCore
import FichaData
import Foundation
import Observation
import os

/// The review panel's log.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "review panel")

/// The cards a review now or an appearance brought, which the review panel
/// goes through one at a time: Lucas ends a new card's first view with "Got
/// it", and flips and rates a due card. Each answer goes into the review log
/// as he gives it, so the cards he doesn't get to stay as they were. When the
/// panel closes, it goes into the appearance log, with how it closed.
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

    /// What opened the panel: Lucas, with review now, or an appearance.
    let trigger: Trigger
    private let cards: [PanelCard]
    private let engine: Engine
    private let settings: ReviewSettings
    private var position = 0
    private var isFlipped = false
    /// When the panel showed, by the engine's time.
    private let shownAt: Date
    /// When Lucas last did something in the panel, or when it showed, by the
    /// engine's time, which Ficha Dev's debug menu moves forward: untouched
    /// for the auto-close since then, the panel closes on its own.
    private var touchedAt: Date
    /// When the panel showed the current card: Lucas's response time runs from
    /// then to his answer. It's measured on the system's steady clock, since
    /// it's how long he took, not a time of day, so moving Ficha Dev's time
    /// doesn't change it.
    private var cardShownAt = ContinuousClock.now
    /// How the panel closed, once it did.
    private(set) var outcome: AppearanceLogEntry.Outcome?
    /// Why Lucas's last answer couldn't be saved, while the panel says so.
    var failure: EngineError?

    /// The cards review now brings, from `engine`.
    static func reviewNow(engine: Engine, settings: ReviewSettings) throws(EngineError) -> ReviewPanelModel {
        ReviewPanelModel(trigger: .reviewNow, cards: try engine.reviewNow(settings), engine: engine, settings: settings)
    }

    /// The panel for `cards`, which `trigger` brought: it shows now.
    init(trigger: Trigger, cards: [PanelCard], engine: Engine, settings: ReviewSettings) {
        self.trigger = trigger
        self.cards = cards
        self.engine = engine
        self.settings = settings
        shownAt = engine.time.now
        touchedAt = shownAt
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

    /// Whether the panel closed: Lucas answered every card, closed it, or
    /// left it untouched.
    var isClosed: Bool {
        outcome != nil
    }

    /// Turns the due card to its back.
    func flip() {
        guard case .front = content else { return }
        isFlipped = true
        touchedAt = engine.time.now
    }

    /// Ends the new card's first view, which puts it on the ladder's first
    /// step: "Got it".
    func endFirstView() {
        guard case .firstView(let card) = content else { return }
        answer(card, .firstView)
    }

    /// Rates the due card, once flipped, which moves it on the ladder.
    func rate(_ rating: Rating) {
        guard case .back(let card) = content else { return }
        answer(card, .review(rating))
    }

    /// Closes the panel as Lucas asks, with Esc or its close button: a
    /// snooze, unless no card was left.
    func close() {
        close(as: hasCardsLeft ? .snoozed : .finished)
    }

    /// Closes the panel on its own, which counts as a snooze, unless no card
    /// was left.
    func closeOnItsOwn() {
        close(as: hasCardsLeft ? .autoClosed : .finished)
    }

    /// Closes the panel on its own once it's been untouched for the
    /// auto-close.
    func closeIfUntouched() {
        guard engine.time.now >= touchedAt + settings.autoClose / .seconds(1) else { return }
        closeOnItsOwn()
    }

    /// Whether some card is still waiting for Lucas's answer.
    private var hasCardsLeft: Bool {
        position < cards.count
    }

    /// Saves Lucas's answer to `card`, with his response time, and moves on to
    /// the next card, or closes the panel after the last one. When it can't be
    /// saved, the card stays, and the panel says why.
    private func answer(_ card: Card, _ kind: ReviewLogEntry.Kind) {
        do {
            try engine.record(
                kind, of: card.id, responseTime: ContinuousClock.now - cardShownAt, trigger: trigger,
                settings: settings)
        } catch {
            failure = error
            return
        }
        position += 1
        isFlipped = false
        cardShownAt = .now
        touchedAt = engine.time.now
        if !hasCardsLeft {
            close(as: .finished)
        }
    }

    /// Closes the panel, once, and records how in the appearance log. When it
    /// can't be recorded, the panel closes anyway, and the log says why.
    private func close(as outcome: AppearanceLogEntry.Outcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        logger.info(
            "The review panel (\(self.trigger.rawValue, privacy: .public)) closed: \(outcome.rawValue, privacy: .public)"
        )
        do {
            try engine.recordClosing(of: trigger, shownAt: shownAt, outcome: outcome)
        } catch {
            logger.error("Couldn't record how the review panel closed: \(String(describing: error), privacy: .public)")
        }
    }
}
