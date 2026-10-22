import FichaCore
import Foundation

/// An appearance or a review now while the review panel shows it: the cards
/// it brought, which Lucas goes through one at a time, what the panel shows of
/// the card he's on, whether the panel may have the keyboard, and how it
/// closes. He ends a new card's first view, and flips and rates a due card,
/// or one he reviews ahead. He can also flag any card with a note on what to
/// fix, or bury it. Each is saved as he does it, and ⌘Z undoes it, one card
/// at a time, while the panel is open, and shows the card again as he left
/// it. Once he went through every card, the panel stays open and offers more
/// cards, if there are any, until he closes it. The panel goes into the
/// appearance log as it closes. It runs on the engine's time, which Ficha
/// Dev's debug menu moves forward, and times Lucas on a steady clock, which
/// it doesn't.
public struct ReviewPanelState: Sendable {
    /// Who closes the panel.
    public enum Closing: Sendable {
        /// Lucas: with Esc or the close button, or by quitting Ficha.
        case byLucas
        /// The panel itself: left untouched for a while, or as the Mac or its
        /// screens go to sleep.
        case onItsOwn
    }

    /// What the panel shows.
    public enum Content: Sendable, Equatable {
        /// Review now brought no cards: none is due, and no new card is
        /// waiting today. "See more" can bring cards to review ahead.
        case nothingToReview
        /// A new card, whole, for its first view.
        case firstView(Card)
        /// A due card's front, or one Lucas reviews ahead, for him to
        /// remember its back.
        case front(Card, isAhead: Bool)
        /// A due card's front and back, or one Lucas reviews ahead, for him
        /// to rate it.
        case back(Card, isAhead: Bool)
        /// The card Lucas is on, as it showed, its back included or not,
        /// while he writes a note on what to fix in it.
        case flagging(Card, showsBack: Bool)
        /// Lucas went through every card. "See more" can bring more.
        case done
    }

    /// What Lucas did in the panel that couldn't be saved, and why, which the
    /// panel says until he closes it.
    public struct Failure: Sendable, Equatable {
        /// What he did.
        public let action: FailedAction
        /// Why the engine couldn't do it.
        public let error: EngineError
    }

    /// What Lucas did that couldn't be saved.
    public enum FailedAction: Sendable, Equatable {
        /// He ended a first view, or rated a card.
        case answer
        /// He flagged a card.
        case flag
        /// He buried a card.
        case bury
        /// He undid what he did with the last card.
        case undo
        /// He went through every card, and the panel looked for more to
        /// offer.
        case lookForMore
    }

    /// What opened the panel: Lucas, with review now, or an appearance.
    public let trigger: Trigger
    /// The cards, in the order the panel shows them: those the panel brought,
    /// and those "See more" added.
    public private(set) var cards: [PanelCard]
    /// The cards "See more" would add, once Lucas went through every card, or
    /// none: the due cards that didn't fit, and then the cards closest to
    /// being due, as reviews ahead. Review now with nothing due offers them
    /// from the start. When the panel couldn't look for them, it offers none,
    /// and its failure says why.
    public private(set) var moreCards: [PanelCard] = []
    /// How many cards the panel brought, before "See more" added any: once
    /// Lucas went through them, closing the panel finishes it.
    private let broughtCount: Int
    /// Whether the panel may have the keyboard: from the start when Lucas
    /// opened it, and in an appearance, once the focus mode says so or Lucas
    /// clicks it.
    public private(set) var mayHaveKeyboard: Bool
    /// How the panel closed, once it did.
    public private(set) var outcome: AppearanceLogEntry.Outcome?
    /// What Lucas did that couldn't be saved, while the panel says so.
    public private(set) var failure: Failure?
    private let engine: Engine
    private let settings: ReviewSettings
    private let shownAt: Date
    /// When Lucas last did something in the panel, or when it showed.
    private var touchedAt: Date
    /// How long the panel has been open, on the steady clock it opened with.
    private let sinceOpening: @Sendable () -> Duration
    /// When the card Lucas is on showed, as `sinceOpening` measured it: his
    /// response time runs from then to his answer.
    private var cardShownAt = Duration.zero
    /// Whether the card Lucas reviews shows its back: he flipped it.
    private var isFlipped = false
    /// The note Lucas is writing to flag the card he's on, while he writes
    /// it.
    private var flagging: Flagging?
    /// What Lucas did with each card he went through, in order, and how he
    /// left it: ⌘Z undoes the last one, and shows the card that way again.
    private var wentThrough: [Visit] = []

    init(
        trigger: Trigger, cards: [PanelCard], engine: Engine, settings: ReviewSettings, clock: some Clock<Duration>
    ) {
        self.trigger = trigger
        self.cards = cards
        broughtCount = cards.count
        self.engine = engine
        self.settings = settings
        mayHaveKeyboard = trigger == .reviewNow
        shownAt = engine.now
        touchedAt = shownAt
        let openedAt = clock.now
        sinceOpening = { openedAt.duration(to: clock.now) }
        lookForMore()
    }

    /// The card Lucas is on, or nil once he went through every one.
    public var current: PanelCard? {
        wentThrough.count < cards.count ? cards[wentThrough.count] : nil
    }

    /// What the panel shows: the card Lucas is on, its front or its back, or
    /// as it showed while he writes a note to flag it, or that there was
    /// nothing to review, or that he went through every card.
    public var content: Content {
        guard !cards.isEmpty else {
            return .nothingToReview
        }
        guard let current else {
            return .done
        }
        if flagging != nil {
            return switch current {
            case .firstView(let card): .flagging(card, showsBack: true)
            case .review(let card), .reviewAhead(let card): .flagging(card, showsBack: isFlipped)
            }
        }
        return switch current {
        case .firstView(let card): .firstView(card)
        case .review(let card), .reviewAhead(let card):
            isFlipped ? .back(card, isAhead: current.isAhead) : .front(card, isAhead: current.isAhead)
        }
    }

    /// Whether "See more" has cards to bring, now that Lucas went through
    /// every card, or review now brought none.
    public var canSeeMore: Bool {
        current == nil && !moreCards.isEmpty
    }

    /// The note Lucas is writing to flag the card he's on, while he writes it.
    public var note: String? {
        flagging?.note
    }

    /// Whether the note says what to fix, so the card can be flagged with it.
    public var noteSaysWhatToFix: Bool {
        note.flatMap(FlagNote.init) != nil
    }

    /// Whether ⌘Z has something to undo: what Lucas did with a card, while
    /// the panel is open and he isn't writing a note.
    public var canUndo: Bool {
        outcome == nil && !wentThrough.isEmpty && flagging == nil
    }

    /// Whether Lucas is on a card, as it shows, to answer, flag or bury it.
    private var isOnACard: Bool {
        switch content {
        case .firstView, .front, .back: true
        case .nothingToReview, .flagging, .done: false
        }
    }

    /// How long Lucas has been on the card he's on: while he writes a note to
    /// flag it, as long as when he started.
    private var timeOnCard: Duration {
        flagging?.timeOnCard ?? sinceOpening() - cardShownAt
    }

    /// Turns the card Lucas reviews to its back: Space, from its front.
    public mutating func flip() {
        guard case .front = content else { return }
        isFlipped = true
        touch()
    }

    /// Ends the new card's first view, which puts it on the ladder's first
    /// step, with how long Lucas took, and moves on to the next card: "Got
    /// it". When it can't be saved, the card stays, and the panel says why.
    public mutating func endFirstView() {
        guard case .firstView = content else { return }
        perform(.answer) { panel throws(EngineError) in
            try panel.answer(.firstView, responseTime: panel.timeOnCard)
        }
    }

    /// Rates the card Lucas reviews, once its back shows, which moves it on
    /// the ladder, with how long he took, and moves on to the next card: in a
    /// review ahead, only again moves it. When it can't be saved, the card
    /// stays, and the panel says why.
    public mutating func rate(_ rating: Rating) {
        guard case .back = content else { return }
        perform(.answer) { panel throws(EngineError) in
            try panel.answer(.review(rating), responseTime: panel.timeOnCard)
        }
    }

    /// Starts flagging the card Lucas is on: the panel asks for a note on
    /// what to fix, and the card's response time waits while he writes it.
    public mutating func startFlagging() {
        guard isOnACard else { return }
        flagging = Flagging(note: "", timeOnCard: timeOnCard)
        touch()
    }

    /// Takes the note as Lucas writes it, which keeps the panel open.
    public mutating func write(note: String) {
        guard flagging != nil else { return }
        flagging?.note = note
        touch()
    }

    /// Stops flagging the card: it stays as it showed, and its response time
    /// goes on from where it waited.
    public mutating func cancelFlagging() {
        guard let flagging else { return }
        self.flagging = nil
        startTiming(from: flagging.timeOnCard)
        touch()
    }

    /// Flags the card with the note Lucas wrote, which sends it to the inbox
    /// until it's fixed, and moves on to the next card. When it can't be
    /// saved, the card stays, with the note, and the panel says why.
    public mutating func finishFlagging() {
        guard let note = note.flatMap(FlagNote.init) else { return }
        perform(.flag) { panel throws(EngineError) in try panel.flag(note: note) }
    }

    /// Buries the card Lucas is on, which takes it out of his reviews for
    /// good, and moves on to the next card. When it can't be saved, the card
    /// stays, and the panel says why.
    public mutating func buryCard() {
        guard isOnACard else { return }
        perform(.bury) { panel throws(EngineError) in try panel.bury() }
    }

    /// Undoes what Lucas did with the last card he went through, and shows it
    /// again as he left it: ⌘Z. When it can't be undone, the panel stays
    /// where it is, and says why.
    public mutating func undoLastCard() {
        guard canUndo else { return }
        perform(.undo) { panel throws(EngineError) in try panel.undo() }
    }

    /// Clears what failed, once the panel said so and Lucas closed it.
    public mutating func dismissFailure() {
        failure = nil
    }

    /// Does what Lucas asked with `work`, or records why it couldn't, as a
    /// failure of `action`.
    private mutating func perform(
        _ action: FailedAction, _ work: (inout ReviewPanelState) throws(EngineError) -> Void
    ) {
        do throws(EngineError) {
            try work(&self)
        } catch {
            failure = Failure(action: action, error: error)
        }
    }

    /// Starts timing the card Lucas is on, from `timeOnCard`, how long he had
    /// already been on it: none for a card that just showed.
    private mutating func startTiming(from timeOnCard: Duration = .zero) {
        cardShownAt = sinceOpening() - timeOnCard
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
    public mutating func takesKeyboard(on mac: some DeviceSignals) -> Bool {
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
    /// The panel's buttons answer through `endFirstView()` and `rate(_:)`,
    /// which time him on the steady clock, and say what failed.
    public mutating func answer(_ kind: ReviewLogEntry.Kind, responseTime: Duration) throws(EngineError) {
        guard outcome == nil, let answering = current else { return }
        try engine.record(
            kind, of: answering.card.id, responseTime: responseTime, trigger: trigger, settings: settings,
            reviewingAhead: answering.isAhead)
        moveOn(after: .answered, timeOnCard: responseTime)
    }

    /// Adds the cards "See more" offers, and goes on to the first of them,
    /// from its front, with its time starting now.
    public mutating func seeMore() {
        guard outcome == nil, current == nil else { return }
        cards += moreCards
        moreCards = []
        startTiming()
        touch()
    }

    /// Flags the current card with Lucas's note on what to fix, which sends
    /// it to the inbox, and moves on to the next card. The panel's button
    /// flags it through `finishFlagging()`, with the note he wrote, which
    /// says what failed.
    public mutating func flag(note: FlagNote) throws(EngineError) {
        guard outcome == nil, let flagging = current else { return }
        let timeOnCard = self.timeOnCard
        try engine.flag(flagging.card.id, note: note)
        moveOn(after: .flagged, timeOnCard: timeOnCard)
    }

    /// Buries the current card, which takes it out of Lucas's reviews for
    /// good, and moves on to the next card. The panel's button buries it
    /// through `buryCard()`, which says what failed.
    public mutating func bury() throws(EngineError) {
        guard outcome == nil, let burying = current else { return }
        let timeOnCard = self.timeOnCard
        try engine.bury(burying.card.id)
        moveOn(after: .buried, timeOnCard: timeOnCard)
    }

    /// Undoes what Lucas did with the last card he went through, which puts
    /// the card back where it stood, and goes back to it, as he left it, its
    /// back showing or not, with its time going on from where it was: ⌘Z,
    /// also once he went through every card. Nothing is left to undo once
    /// the panel closed. The panel's ⌘Z undoes through `undoLastCard()`,
    /// which says what failed.
    public mutating func undo() throws(EngineError) {
        guard canUndo, let last = wentThrough.last else { return }
        try engine.undo(last.action, to: cards[wentThrough.count - 1].card.id)
        wentThrough.removeLast()
        moreCards = []
        isFlipped = last.showedBack
        startTiming(from: last.timeOnCard)
        touch()
    }

    /// Moves on to the next card, from its front, with its time starting now,
    /// once Lucas did `action` with the current one after `timeOnCard` on it.
    /// After the last one, the panel looks for more cards to offer.
    private mutating func moveOn(after action: PanelAction, timeOnCard: Duration) {
        wentThrough.append(Visit(action: action, showedBack: isFlipped, timeOnCard: timeOnCard))
        isFlipped = false
        flagging = nil
        startTiming()
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
        } catch {
            moreCards = []
            failure = Failure(action: .lookForMore, error: error)
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

/// A card Lucas went through in the review panel: what he did with it, which
/// ⌘Z undoes, and how he left it, which ⌘Z shows again: whether its back
/// showed, and how long he had been on it.
private struct Visit: Sendable {
    let action: PanelAction
    let showedBack: Bool
    let timeOnCard: Duration
}

/// The note Lucas is writing to flag the card he's on, and how long he had
/// been on the card when he started.
private struct Flagging: Sendable {
    var note: String
    let timeOnCard: Duration
}

extension Engine {
    /// Opens the review panel with `cards`, which `trigger` brought: the panel
    /// shows them from now on, and times Lucas on each on `clock`, a steady
    /// one, which moving the engine's time doesn't move: the system's
    /// continuous clock in the app.
    public func openPanel(
        _ trigger: Trigger, with cards: [PanelCard], settings: ReviewSettings, clock: some Clock<Duration>
    ) -> ReviewPanelState {
        ReviewPanelState(trigger: trigger, cards: cards, engine: self, settings: settings, clock: clock)
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
                guard case .inInbox = card.standing else {
                    throw EngineError.cannotUndo(cardID)
                }
                _ = try updateCard(cardID, setting: "flagNote = NULL, flaggedAt = NULL", in: db)
            case .buried:
                guard case .buried = card.standing else {
                    throw EngineError.cannotUndo(cardID)
                }
                _ = try updateCard(cardID, setting: "buriedAt = NULL", in: db)
            }
        }
    }
}
