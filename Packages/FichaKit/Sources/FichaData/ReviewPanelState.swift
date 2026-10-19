import FichaCore
import Foundation

/// An appearance or a review now while the review panel shows it: the cards
/// it brought, which Lucas goes through one at a time, whether the panel may
/// have the keyboard, and how it closes. He answers, flags or buries each
/// card, which is saved as he does it, and ⌘Z undoes it, one card at a time,
/// while the panel is open. Once he went through every card, the panel stays
/// open and offers more cards, if there are any, until he closes it. The
/// panel goes into the appearance log as it closes. It runs on the engine's
/// time, which Ficha Dev's debug menu moves forward.
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
    /// The cards, in the order the panel shows them: those the panel brought,
    /// and those "See more" added.
    public private(set) var cards: [PanelCard]
    /// The cards "See more" would add, once Lucas went through every card, or
    /// none: the due cards that didn't fit, and then the cards closest to
    /// being due, as reviews ahead. Review now with nothing due offers them
    /// from the start.
    public private(set) var moreCards: [PanelCard] = []
    /// Why the panel couldn't look for the cards "See more" would add, if it
    /// couldn't: then it offers none.
    public private(set) var moreCardsFailure: EngineError?
    /// How many cards the panel brought, before "See more" added any: once
    /// Lucas went through them, closing the panel finishes it.
    private let broughtCount: Int
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
        broughtCount = cards.count
        self.engine = engine
        self.settings = settings
        mayHaveKeyboard = trigger == .reviewNow
        shownAt = engine.now
        touchedAt = shownAt
        lookForMore()
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
    /// long he took, and moves on to the next card: in a review ahead, as one.
    public mutating func answer(_ kind: ReviewLogEntry.Kind, responseTime: Duration) throws(EngineError) {
        guard outcome == nil, let answering = current else { return }
        try engine.record(
            kind, of: answering.card.id, responseTime: responseTime, trigger: trigger, settings: settings,
            reviewingAhead: answering.isAhead)
        moveOn(after: .answered)
    }

    /// Adds the cards "See more" offers, and goes on to the first of them.
    public mutating func seeMore() {
        guard outcome == nil, current == nil else { return }
        cards += moreCards
        moreCards = []
        touch()
    }

    /// Flags the current card with Lucas's note on what to fix, which sends
    /// it to the inbox, and moves on to the next card.
    public mutating func flag(note: FlagNote) throws(EngineError) {
        guard outcome == nil, let flagging = current else { return }
        try engine.flag(flagging.card.id, note: note)
        moveOn(after: .flagged)
    }

    /// Buries the current card, which takes it out of Lucas's reviews for
    /// good, and moves on to the next card.
    public mutating func bury() throws(EngineError) {
        guard outcome == nil, let burying = current else { return }
        try engine.bury(burying.card.id)
        moveOn(after: .buried)
    }

    /// Undoes what Lucas did with the last card he went through, which puts
    /// the card back where it stood, and goes back to it: ⌘Z, also once he
    /// went through every card. Nothing is left to undo once the panel
    /// closed.
    public mutating func undo() throws(EngineError) {
        guard outcome == nil, let last = wentThrough.last else { return }
        try engine.undo(last, to: cards[wentThrough.count - 1].card.id)
        wentThrough.removeLast()
        moreCards = []
        touch()
    }

    /// Moves on to the next card, once Lucas did `action` with the current
    /// one. After the last one, the panel looks for more cards to offer.
    private mutating func moveOn(after action: PanelAction) {
        wentThrough.append(action)
        touch()
        if current == nil {
            lookForMore()
        }
    }

    /// Finds the cards "See more" would add, now that Lucas went through
    /// every card. When they can't be found, the panel offers none, and says
    /// why.
    private mutating func lookForMore() {
        guard current == nil else { return }
        do {
            moreCards = try engine.seeMoreCards(after: Set(cards.map(\.card.id)), from: trigger, settings: settings)
            moreCardsFailure = nil
        } catch {
            moreCards = []
            moreCardsFailure = error
        }
    }

    /// Closes the panel on its own once it's been untouched for the
    /// auto-close.
    public mutating func closeIfUntouched() {
        guard engine.now >= touchedAt.adding(settings.autoClose) else { return }
        close(.onItsOwn)
    }

    /// Closes the panel, once: as finished when no card it brought was left,
    /// even if some that "See more" added were, and otherwise as a snooze,
    /// Lucas's or the panel's own. It goes into the
    /// appearance log, unless it brought no cards: an empty review now holds
    /// no appearance back (Lucas, 2026-10-15). When it can't be recorded, the
    /// panel closes anyway, and the engine logs why.
    public mutating func close(_ closing: Closing) {
        guard outcome == nil else { return }
        let outcome: AppearanceLogEntry.Outcome =
            switch (wentThrough.count >= broughtCount, closing) {
            case (true, _): .finished
            case (false, .byLucas): .snoozed
            case (false, .onItsOwn): .autoClosed
            }
        self.outcome = outcome
        guard !cards.isEmpty else { return }
        do {
            try engine.recordClosing(of: trigger, shownAt: shownAt, outcome: outcome)
            let opener = trigger.rawValue
            logger.info(
                "The review panel (\(opener, privacy: .public)) closed: \(outcome.columns.outcome, privacy: .public)")
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
    /// card stands where it stood before it. His answer leaves the review
    /// log, as an answer undone never happened, the way Anki's undo deletes it
    /// too; his flag or burial leaves the card. When the card changed outside
    /// the panel since, nothing is undone.
    fileprivate func undo(_ action: PanelAction, to cardID: Int64) throws(EngineError) {
        try write { db in
            let card = try existingCard(cardID, in: db)
            switch action {
            case .answered:
                // The panel's answer is the card's last entry.
                try db.execute(
                    sql: "DELETE FROM reviewLog WHERE id = (SELECT max(id) FROM reviewLog WHERE cardId = ?)",
                    arguments: [cardID]
                )
                guard db.changesCount == 1 else {
                    throw EngineError.cannotUndo(cardID)
                }
            case .flagged:
                guard card.flag != nil, card.buriedAt == nil else {
                    throw EngineError.cannotUndo(cardID)
                }
                _ = try updateCard(cardID, setting: "flagNote = NULL, flaggedAt = NULL", in: db)
            case .buried:
                guard card.buriedAt != nil else {
                    throw EngineError.cannotUndo(cardID)
                }
                _ = try updateCard(cardID, setting: "buriedAt = NULL", in: db)
            }
        }
    }
}
