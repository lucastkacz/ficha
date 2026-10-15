import FichaCore
import Foundation

/// An appearance or a review now while the review panel shows it: the cards
/// it brought, which Lucas goes through one at a time, whether the panel may
/// have the keyboard, and how it closes. He answers, flags or buries each
/// card, which is saved as he does it, and ⌘Z undoes it, one card at a time,
/// while the panel is open. The panel goes into the appearance log as it
/// closes. It runs on the engine's time, which Ficha Dev's debug menu moves
/// forward.
public struct ReviewPanelState: Sendable {
    /// Who closes the panel.
    public enum Closing: Sendable {
        /// Lucas: with Esc or the close button, or by quitting Ficha.
        case byLucas
        /// The panel itself: left untouched for a while, or as the Mac or its
        /// screens go to sleep.
        case onItsOwn
    }

    /// What opened the panel: Lucas, with review now, or an appearance.
    public let trigger: Trigger
    /// The cards, in the order the panel shows them.
    public let cards: [PanelCard]
    /// Whether the panel may have the keyboard: from the start when Lucas
    /// opened it, and in an appearance, once the focus mode says so or Lucas
    /// clicks it.
    public private(set) var mayHaveKeyboard: Bool
    /// How the panel closed, once it did.
    public private(set) var outcome: AppearanceLogEntry.Outcome?
    private let engine: Engine
    private let settings: ReviewSettings
    private let shownAt: Date
    /// When Lucas last did something in the panel, or when it showed.
    private var touchedAt: Date
    /// What Lucas did with each card he went through, in order: ⌘Z undoes
    /// the last one.
    private var wentThrough: [PanelAction] = []

    init(trigger: Trigger, cards: [PanelCard], engine: Engine, settings: ReviewSettings) {
        self.trigger = trigger
        self.cards = cards
        self.engine = engine
        self.settings = settings
        mayHaveKeyboard = trigger == .reviewNow
        shownAt = engine.now
        touchedAt = shownAt
    }

    /// The card Lucas is on, or nil once he went through every one.
    public var current: PanelCard? {
        wentThrough.count < cards.count ? cards[wentThrough.count] : nil
    }

    /// Whether ⌘Z has something to undo: what Lucas did with a card, while
    /// the panel is open.
    public var canUndo: Bool {
        outcome == nil && !wentThrough.isEmpty
    }

    /// Notes that Lucas did something in the panel, like flipping a card: the
    /// panel closes on its own once it's been untouched for a while.
    public mutating func touch() {
        touchedAt = engine.now
    }

    /// Notes that Lucas clicked the panel, which gives it the keyboard: it
    /// doesn't take the keyboard on its own after that.
    public mutating func clicked() {
        mayHaveKeyboard = true
        touch()
    }

    /// Whether the panel takes the keyboard now, by how long `mac` says Lucas
    /// has been idle: an appearance's panel takes it once, when the focus mode
    /// says so, unless Lucas gave it the keyboard first.
    public mutating func takesKeyboard(on mac: some MacSignals) -> Bool {
        guard !mayHaveKeyboard,
            settings.focusMode.takesKeyboard(idle: mac.idleTime, after: settings.idleBeforeTakingKeyboard)
        else {
            return false
        }
        mayHaveKeyboard = true
        return true
    }

    /// Records Lucas's answer to the current card in the review log, with how
    /// long he took, and moves on to the next card. After the last one, the
    /// panel closes as finished.
    public mutating func answer(_ kind: ReviewLogEntry.Kind, responseTime: Duration) throws(EngineError) {
        guard outcome == nil, let answering = current else { return }
        try engine.record(
            kind, of: answering.card.id, responseTime: responseTime, trigger: trigger, settings: settings)
        moveOn(after: .answered)
    }

    /// Flags the current card with Lucas's note on what to fix, which sends
    /// it to the inbox, and moves on to the next card. After the last one, the
    /// panel closes as finished.
    public mutating func flag(note: FlagNote) throws(EngineError) {
        guard outcome == nil, let flagging = current else { return }
        try engine.flag(flagging.card.id, note: note)
        moveOn(after: .flagged)
    }

    /// Buries the current card, which takes it out of Lucas's reviews for
    /// good, and moves on to the next card. After the last one, the panel
    /// closes as finished.
    public mutating func bury() throws(EngineError) {
        guard outcome == nil, let burying = current else { return }
        try engine.bury(burying.card.id)
        moveOn(after: .buried)
    }

    /// Undoes what Lucas did with the last card he went through, which puts
    /// the card back where it stood, and goes back to it: ⌘Z. Nothing is left
    /// to undo once the panel closed.
    public mutating func undo() throws(EngineError) {
        guard outcome == nil, let last = wentThrough.last else { return }
        try engine.undo(last, to: cards[wentThrough.count - 1].card.id)
        wentThrough.removeLast()
        touch()
    }

    /// Moves on to the next card, once Lucas did `action` with the current
    /// one. After the last one, the panel closes as finished.
    private mutating func moveOn(after action: PanelAction) {
        wentThrough.append(action)
        touch()
        if current == nil {
            close(.byLucas)
        }
    }

    /// Closes the panel on its own once it's been untouched for the
    /// auto-close.
    public mutating func closeIfUntouched() {
        guard engine.now >= touchedAt.adding(settings.autoClose) else { return }
        close(.onItsOwn)
    }

    /// Closes the panel, once: as finished when no card was left, and
    /// otherwise as a snooze, Lucas's or the panel's own. It goes into the
    /// appearance log, unless it brought no cards: an empty review now holds
    /// no appearance back (Lucas, 2026-10-15). When it can't be recorded, the
    /// panel closes anyway, and the engine logs why.
    public mutating func close(_ closing: Closing) {
        guard outcome == nil else { return }
        let outcome: AppearanceLogEntry.Outcome =
            switch (current, closing) {
            case (nil, _): .finished
            case (_?, .byLucas): .snoozed
            case (_?, .onItsOwn): .autoClosed
            }
        self.outcome = outcome
        guard !cards.isEmpty else { return }
        do {
            try engine.recordClosing(of: trigger, shownAt: shownAt, outcome: outcome)
            let opener = trigger.rawValue
            logger.info("The review panel (\(opener, privacy: .public)) closed: \(outcome.rawValue, privacy: .public)")
        } catch {
            logger.error("Couldn't record how the review panel closed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// What Lucas did with a card in the review panel, which ⌘Z undoes.
enum PanelAction: Sendable {
    /// He answered it: he ended its first view, or rated it.
    case answered
    /// He flagged it.
    case flagged
    /// He buried it.
    case buried
}

extension Engine {
    /// Opens the review panel with `cards`, which `trigger` brought: the panel
    /// shows them from now on.
    public func openPanel(_ trigger: Trigger, with cards: [PanelCard], settings: ReviewSettings) -> ReviewPanelState {
        ReviewPanelState(trigger: trigger, cards: cards, engine: self, settings: settings)
    }

    /// Undoes `action`, which Lucas did to a card in the review panel, so the
    /// card stands where it stood before it.
    fileprivate func undo(_ action: PanelAction, to cardID: Int64) throws(EngineError) {
        switch action {
        case .answered: try undoLastAnswer(to: cardID)
        case .flagged: try unflag(cardID)
        case .buried: try unbury(cardID)
        }
    }
}
