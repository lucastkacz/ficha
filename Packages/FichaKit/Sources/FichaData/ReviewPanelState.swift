import FichaCore
import Foundation

/// An appearance or a review now while the review panel shows it: the cards it
/// brought, which Lucas goes through one at a time, what the panel shows of the
/// card he's on, the card alone (ADR 0033), what its ⋯ menu offers, whether the
/// panel may have the keyboard, and how it closes. Each card comes one of its
/// ways, front first or back first, and his answers move only that way. He
/// flips and rates a new way, in its first review, a due way, or one he reviews
/// ahead. He plays a side's sound only when he asks, one at a time, until he
/// answers the card, writes about it or leaves it, or the panel closes. He can
/// also flag any card with a note on what to fix, or set it aside. When
/// his rating of again makes a card forgotten often, the panel offers to flag
/// it, with a note that says how many times he forgot it, and back first when
/// it was that way. Each is saved as he does it, and ⌘Z undoes it, the last
/// first, while the panel is open, and shows the card again as he left it.
/// Once he went through every card, the panel stays open and offers more
/// cards, if there are any, until he closes it, and says which decks his
/// answers met in full, with what comes next in the queue new cards come from
/// (`metThemAll`). The panel goes into the appearance log as it closes. It
/// runs on the engine's time, which Ficha Dev's debug menu moves forward, and
/// times Lucas on a steady clock, which it doesn't.
public struct ReviewPanelState: Sendable {
    /// Who closes the panel.
    public enum Closing: Sendable {
        /// Lucas: with Esc, the ⋯ menu's Close, or the close button of a
        /// panel with no card, or by quitting Ficha.
        case byLucas
        /// The panel itself: left untouched for a while, or as the Mac or its
        /// screens go to sleep.
        case onItsOwn
    }

    /// What the panel shows. A card shows the way the panel brought it, front
    /// first unless it's said to show back first: its upper side on top, the
    /// front front first and the back back first, and its lower side under
    /// it, the other side, once it shows, with the mark "Back first" back
    /// first.
    public enum Content: Sendable, Equatable {
        /// Review now brought no cards: none is due, and no new card is
        /// waiting today. "See more" can bring cards to review ahead.
        case nothingToReview
        /// A way of a card, its upper side alone, for Lucas to remember the
        /// other: a due way, one he reviews ahead, or a new way, in its first
        /// review, which `isNew` says.
        case upperSide(Card, Way = .frontFirst, isNew: Bool = false, isAhead: Bool = false)
        /// A way of a card, its upper side and its lower side, for Lucas to
        /// rate it: a due way, one he reviews ahead, or a new way, whose
        /// buttons the panel names for a first review (`AnswerButton`).
        case bothSides(Card, Way = .frontFirst, isNew: Bool = false, isAhead: Bool = false)
        /// The card Lucas is on, as it showed, its lower side included or
        /// not, while he writes a note on what to fix in it, also when the
        /// panel offers to flag it.
        case flagging(Card, Way = .frontFirst, showsLowerSide: Bool)
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
        /// He rated a card.
        case answer
        /// He flagged a card.
        case flag
        /// He set a card aside.
        case setAside
        /// He undid the last thing he did.
        case undo
        /// He went through every card, and the panel looked for more to
        /// offer.
        case lookForMore
    }

    /// What the panel says once Lucas went through its cards, under its done
    /// title, after an answer in it met the last new card of a deck at the
    /// top of the tree, which was in the queue new cards come from and no
    /// longer is once the answer's in (ADR 0034, #491): "You've met them
    /// all", for each such deck, and then what comes next.
    public struct MetThemAll: Sendable, Equatable {
        /// The decks whose last new card an answer in the panel met, in the
        /// order it met them, with what each has of its own: "You've met them
        /// all: <emoji> <deck>".
        public let decks: [Deck]
        /// The deck first in the queue now, whose first card comes with the
        /// next new one: "Next in the queue: <emoji> <deck>."; or nil when
        /// nothing waits in the queue: "Nothing waits in the queue."
        public let nextInQueue: Deck?
        /// While nothing waits in the queue, the first of Ficha's decks the
        /// user hasn't added, in `FichaDeck`'s order, among those the app
        /// could read for the panel (`offerFichaDecks(_:)`): "Another of
        /// Ficha's decks?", with a button named after it, which opens the
        /// Cards window on it with How fast? (#458). Nil while something
        /// waits, or while the user has added all of them.
        public let fichaDeck: FichaDeck?
        /// The emoji of `fichaDeck`, as its file's `deck.json` holds it, which
        /// its button shows before its name: nil for none (#554).
        public let fichaDeckEmoji: String?
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
    /// The images on the cards' sides, read once the panel has the cards,
    /// as it opens and as "See more" adds them.
    public private(set) var images = ShownImages()
    /// The sounds on the sides of the card Lucas is on, with their lengths,
    /// read as it shows.
    public internal(set) var sounds = ShownSounds()
    /// The sound that plays, which Lucas asked for, if any.
    public internal(set) var playingSound: PlayingSound?
    let engine: Engine
    private let settings: ReviewSettings
    /// The note the panel offers to flag a card forgotten often with, for
    /// how many times Lucas forgot it and which way, from the app's String
    /// Catalog.
    private let forgottenOftenNote: @Sendable (ForgottenOften) -> String
    private let shownAt: Date
    /// When Lucas last did something in the panel, or when it showed.
    private var touchedAt: Date
    /// How long the panel has been open, on the steady clock it opened with.
    private let sinceOpening: @Sendable () -> Duration
    /// When the card Lucas is on showed, as `sinceOpening` measured it: his
    /// response time runs from then to his answer.
    private var cardShownAt = Duration.zero
    /// Whether the card Lucas is on shows its lower side: he flipped it.
    private var isFlipped = false
    /// The interval each rating would set for the card Lucas is on, as the
    /// scheduler worked them out when its lower side showed, and when, which
    /// his rating keeps (#404); or nil until it shows, or when they couldn't
    /// be worked out.
    private var shownIntervals: (preview: IntervalPreview, at: Date)?
    /// The note Lucas is writing to flag the card he's on, while he writes
    /// it.
    private var flagging: Flagging?
    /// What Lucas did with each card he went through, in order, and how he
    /// left it: ⌘Z undoes the last one, and shows the card that way again.
    private var wentThrough: [Visit] = []
    /// The deck at the top of the tree whose last new card Lucas's answer to
    /// the card he's on met, by its whole name, until he moves on, as when
    /// the panel offers to flag the card first: his visit to it keeps it.
    private var answerMetInFull: String?
    /// What the panel says it met in full, as it read it once Lucas last went
    /// through its cards, which `metThemAll` says while the panel's done.
    private var metInFull: MetThemAll?
    /// Ficha's decks, as the app read them from its bundle once the panel
    /// asked for them (`asksForFichaDecks`), in `FichaDeck`'s order, those
    /// it could read: nil until then.
    private var fichaDecks: [FichaDeckFile]?

    init(
        trigger: Trigger, cards: [PanelCard], engine: Engine, settings: ReviewSettings, clock: some Clock<Duration>,
        forgottenOftenNote: @escaping @Sendable (ForgottenOften) -> String
    ) {
        self.trigger = trigger
        self.cards = cards
        broughtCount = cards.count
        self.engine = engine
        self.settings = settings
        self.forgottenOftenNote = forgottenOftenNote
        mayHaveKeyboard = trigger == .reviewNow
        shownAt = engine.now
        touchedAt = shownAt
        let openedAt = clock.now
        sinceOpening = { openedAt.duration(to: clock.now) }
        showImages()
        showSounds()
        lookForMore()
    }

    /// The card Lucas is on, or nil once he went through every one.
    public var current: PanelCard? {
        wentThrough.count < cards.count ? cards[wentThrough.count] : nil
    }

    /// What the panel shows: the card Lucas is on, the way it came, its
    /// upper side alone or with its lower side, or as it showed while he
    /// writes a note to flag it, or that there was
    /// nothing to review, or that he went through every card. A new way
    /// shows its upper side until he flips it, as a review does, and says it's
    /// new.
    public var content: Content {
        guard !cards.isEmpty else {
            return .nothingToReview
        }
        guard let current else {
            return .done
        }
        let (card, way) = (current.card, current.way)
        if flagging != nil {
            return .flagging(card, way, showsLowerSide: showsLowerSide)
        }
        return switch (current, showsLowerSide) {
        case (.new, false): .upperSide(card, way, isNew: true)
        case (.new, true): .bothSides(card, way, isNew: true)
        case (.review, false), (.reviewAhead, false): .upperSide(card, way, isAhead: current.isAhead)
        case (.review, true), (.reviewAhead, true): .bothSides(card, way, isAhead: current.isAhead)
        }
    }

    /// What the panel says it met in full, once Lucas went through its cards
    /// (`.done`): the decks whose last new card an answer in it met, which
    /// undoing that answer forgets, and what comes next; nil while he's on a
    /// card, and when no answer met a deck's last new card.
    public var metThemAll: MetThemAll? {
        content == .done ? metInFull : nil
    }

    /// Whether the panel asks the app for Ficha's decks, to offer one in
    /// `metThemAll` (`offerFichaDecks(_:)`): once it says nothing waits in the
    /// queue, until the app gives them. Reading them takes a while, so the
    /// app reads them only then, away from the main actor.
    public var asksForFichaDecks: Bool {
        fichaDecks == nil && metThemAll != nil && metThemAll?.nextInQueue == nil
    }

    /// Takes Ficha's decks as the app read them from its bundle
    /// (`Engine.readFichaDeck(_:at:)`), each deck's file or why it couldn't
    /// be read, which `metThemAll` offers the first of, in `FichaDeck`'s
    /// order, the user hasn't added, while nothing waits in the queue. One
    /// whose file couldn't be read, such as one missing from a damaged copy
    /// of the app, isn't offered, and the log says why.
    public mutating func offerFichaDecks(_ read: [FichaDeck: Result<FichaDeckFile, EngineError>]) {
        fichaDecks = FichaDeck.files(in: read).files
        if metInFull != nil {
            readMetThemAll()
        }
    }

    /// What the panel's ⋯ menu offers to do with the card Lucas is on, each
    /// also on its key (`CardAction`): flagging it and setting it aside while
    /// it shows, and nothing while he writes about it
    /// or once he went through every card.
    public var cardActions: [CardAction] {
        isOnACard ? CardAction.allCases : []
    }

    /// Whether the ⋯ menu offers Undo after what it does with the card: while
    /// a card shows and once Lucas went through every card, but not while he
    /// writes about one, when it holds Close alone. Undo is dimmed while
    /// there's nothing to undo (`canUndo`).
    public var menuOffersUndo: Bool {
        switch content {
        case .upperSide, .bothSides, .done: true
        case .nothingToReview, .flagging: false
        }
    }

    /// Whether "See more" has cards to bring, now that Lucas went through
    /// every card, or review now brought none.
    public var canSeeMore: Bool {
        current == nil && !moreCards.isEmpty
    }

    /// Whether a click on the widget, on `first`, the card it showed, starts
    /// a review now in the open panel's place: once Lucas went through the
    /// panel's cards, at its end, where "See more" brings no new card, so the
    /// widget's new card would wait otherwise. While the panel has cards to
    /// go, or when the widget showed none, the click brings it forward
    /// instead, with its cards (Lucas, 2026-10-28, #308's P15).
    public func givesWay(toAReviewNowStartingWith first: CardWay?) -> Bool {
        first != nil && current == nil && outcome == nil
    }

    /// The note Lucas is writing to flag the card he's on, while he writes it.
    public var note: String? {
        flagging?.note
    }

    /// Whether the note says what to fix, so the card can be flagged with it.
    public var noteSaysWhatToFix: Bool {
        note.flatMap(FlagNote.init) != nil
    }

    /// Whether the panel offers to flag the card Lucas is on, which he just
    /// rated again and forgot often: then cancelling moves on without
    /// flagging it.
    public var offersToFlag: Bool {
        flagging?.isOffer == true
    }

    /// Whether ⌘Z has something to undo: what Lucas did with a card he went
    /// through, while the panel is open and he isn't writing a note.
    public var canUndo: Bool {
        outcome == nil && !wentThrough.isEmpty && flagging == nil
    }

    /// Whether the card Lucas is on shows its lower side under its upper one:
    /// once he flipped it, also while he writes about it.
    var showsLowerSide: Bool {
        current != nil && isFlipped
    }

    /// Whether Lucas is on a card, as it shows, to answer, flag or set aside
    /// it.
    var isOnACard: Bool {
        switch content {
        case .upperSide, .bothSides: true
        case .nothingToReview, .flagging, .done: false
        }
    }

    /// How long Lucas has been on the card he's on: while he writes a note to
    /// flag it, as long as when he started.
    private var timeOnCard: Duration {
        flagging?.timeOnCard ?? sinceOpening() - cardShownAt
    }

    /// Shows the lower side of the card Lucas is on under its upper side:
    /// Space, from its upper side alone.
    public mutating func flip() {
        guard case .upperSide = content else { return }
        isFlipped = true
        workOutIntervals()
        touch()
    }

    /// Works out the interval each rating would set for the card Lucas is
    /// on, now, while its lower side shows, for his rating to keep, as Anki
    /// keeps the intervals its buttons showed (#404), though the panel shows
    /// none (ADR 0033); or none otherwise. When the scheduler can't work them
    /// out, as when the card was deleted meanwhile, a rating keeps the
    /// interval worked out as he answers, and says why when it can't.
    private mutating func workOutIntervals() {
        guard showsLowerSide, let current else {
            shownIntervals = nil
            return
        }
        let now = engine.now
        do throws(EngineError) {
            shownIntervals = (try engine.intervals(of: current.cardWay, at: now, settings: settings), now)
        } catch {
            shownIntervals = nil
            logger.error(
                "Couldn't work out the flipped card's intervals: \(String(describing: error), privacy: .public)")
        }
    }

    /// Rates the way of the card Lucas reviews, once its lower side shows,
    /// which the scheduler spaces from then on, with how long he took, and
    /// moves on to the next card: a new way's first review too. When a
    /// rating of again makes the card forgotten often, the panel stays on it
    /// and offers to flag it instead. When it can't be saved, the card stays,
    /// and the panel says why.
    public mutating func rate(_ rating: Rating) {
        guard case .bothSides = content else { return }
        perform(.answer) { panel throws(EngineError) in
            try panel.answer(.review(rating), responseTime: panel.timeOnCard)
        }
    }

    /// Starts flagging the card Lucas is on: the panel asks for a note on
    /// what to fix, the card's response time waits while he writes it, and
    /// its sound stops.
    public mutating func startFlagging() {
        guard isOnACard else { return }
        flagging = Flagging(note: "", timeOnCard: timeOnCard, isOffer: false)
        playingSound = nil
        touch()
    }

    /// Takes the note as Lucas writes it, which keeps the panel open.
    public mutating func write(note: String) {
        guard flagging != nil else { return }
        flagging?.note = note
        touch()
    }

    /// Stops flagging the card: it stays as it showed, and its response time
    /// goes on from where it waited. When the panel offered to flag it, the
    /// card stays in Lucas's reviews, with his rating, and the panel moves on
    /// to the next card.
    public mutating func cancelFlagging() {
        guard let flagging else { return }
        if flagging.isOffer {
            moveOn(after: [.answered], timeOnCard: flagging.timeOnCard)
            return
        }
        self.flagging = nil
        startTiming(from: flagging.timeOnCard)
        touch()
    }

    /// Flags the card with the note Lucas wrote, which takes it out of his
    /// reviews, to wait in its deck until it's fixed, and moves on to the
    /// next card, also when the panel offered it, after his rating. When it
    /// can't be saved, the card stays, with the note, and the panel says why.
    public mutating func finishFlagging() {
        guard let note = note.flatMap(FlagNote.init) else { return }
        perform(.flag) { panel throws(EngineError) in try panel.flag(note: note) }
    }

    /// Does `action` with the card Lucas is on, which he chose from the ⋯
    /// menu or with its key: starts flagging it, or sets it aside.
    public mutating func choose(_ action: CardAction) {
        switch action {
        case .flag: startFlagging()
        case .setAside: setCardAside()
        }
    }

    /// Sets the card Lucas is on aside, which takes it out of his reviews
    /// until he puts it back in the Cards window, and moves on to the next
    /// card. When it can't be saved, the card stays, and the panel says why.
    public mutating func setCardAside() {
        guard isOnACard else { return }
        perform(.setAside) { panel throws(EngineError) in try panel.setAside() }
    }

    /// Undoes what Lucas did with the last card he went through, and shows
    /// that card again as he left it: ⌘Z. When it can't be undone, the panel
    /// stays where it is, and says why.
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

    /// Notes that Lucas pressed a key that changes the card size, which the
    /// app keeps, so the panel doesn't close on its own while he adjusts it,
    /// at a limit too, where the press changes nothing.
    public mutating func cardSizeKeyPressed() {
        touch()
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
    /// Once the card's lower side showed, a review keeps the interval the
    /// scheduler worked out for its rating then. When the engine says a
    /// rating of again made the card forgotten often,
    /// the panel stays on it instead, flagging it, with the note written as
    /// how many times he forgot it the way it showed, and the card's time
    /// stopped at his answer. The panel's buttons answer through
    /// `rate(_:)`, which times him on the steady clock,
    /// and say what failed. When a new way's first review puts the deck at
    /// the top of the tree its card lives in among those met in full, out of
    /// the queue new cards come from (`Engine.decksMetInFull()`), the answer
    /// met the deck in full, which the panel says once it's done
    /// (`metThemAll`).
    public mutating func answer(_ kind: ReviewLogEntry.Kind, responseTime: Duration) throws(EngineError) {
        guard outcome == nil, let answering = current else { return }
        let deck = TagPath.top(of: answering.card.deck)
        var wasQueued = false
        if case .new = answering {
            wasQueued = decksMetInFull()?.contains(deck) == false
        }
        let forgottenOften = try engine.record(
            kind, of: answering.card.id, way: answering.way, responseTime: responseTime, trigger: trigger,
            settings: settings, reviewingAhead: answering.isAhead, intervalsWorkedOutAt: shownIntervals?.at)
        answerMetInFull = wasQueued && decksMetInFull()?.contains(deck) == true ? deck : nil
        // Also when the panel stays on the card, to offer to flag it.
        playingSound = nil
        guard let forgottenOften else {
            moveOn(after: [.answered], timeOnCard: responseTime)
            return
        }
        flagging = Flagging(note: forgottenOftenNote(forgottenOften), timeOnCard: responseTime, isOffer: true)
        touch()
    }

    /// Adds the cards "See more" offers, and goes on to the first of them,
    /// from its upper side, with its time starting now.
    public mutating func seeMore() {
        guard outcome == nil, current == nil else { return }
        cards += moreCards
        moreCards = []
        showImages()
        showSounds()
        startTiming()
        touch()
    }

    /// Reads the images on the sides of the panel's cards.
    private mutating func showImages() {
        images.show(Set(cards.flatMap(\.card.images)), readingWith: engine)
    }

    /// Flags the current card with Lucas's note on what to fix, which takes
    /// it out of his reviews, to wait in its deck, and moves on to the next
    /// card. When the panel offered
    /// it, ⌘Z then undoes his rating along with the flag. The panel's button
    /// flags it through `finishFlagging()`, with the note he wrote, which
    /// says what failed.
    public mutating func flag(note: FlagNote) throws(EngineError) {
        guard outcome == nil, let flagging = current else { return }
        let timeOnCard = self.timeOnCard
        let answered: [PanelAction] = offersToFlag ? [.answered] : []
        try engine.flag(flagging.card.id, note: note)
        moveOn(after: answered + [.flagged], timeOnCard: timeOnCard)
    }

    /// Sets the current card aside, which takes it out of Lucas's reviews
    /// until he puts it back, and moves on to the next card: the engine
    /// buries it, as the database keeps a card set aside on its own (ADR
    /// 0041). The panel's menu sets it aside through `setCardAside()`, which
    /// says what failed.
    public mutating func setAside() throws(EngineError) {
        guard outcome == nil, let settingAside = current else { return }
        let timeOnCard = self.timeOnCard
        try engine.bury(settingAside.card.id)
        moveOn(after: [.setAside], timeOnCard: timeOnCard)
    }

    /// Undoes the last thing Lucas did, ⌘Z, the last first: what he did with
    /// the last card he went through, which puts the card's way back where
    /// it stood, and goes back to it, as he left it, its lower side showing
    /// or not, with its time going on from where it was: also once he went
    /// through every card. The engine takes back his answer to that way,
    /// unflags the card or puts it back, or, for a card he flagged when the
    /// panel offered it, unflags it and then takes back his answer. When the
    /// card changed outside the panel since, nothing more is undone. Nothing
    /// is left to undo once the panel closed. The panel's ⌘Z undoes through
    /// `undoLastCard()`, which says what failed.
    public mutating func undo() throws(EngineError) {
        guard canUndo else { return }
        guard let last = wentThrough.last else { return }
        let undone = cards[wentThrough.count - 1]
        // The last first. What's taken back leaves the visit at once, so
        // when the next can't be, the next ⌘Z tries only what's left.
        for action in last.actions.reversed() {
            try takeBack(action, of: undone)
            wentThrough[wentThrough.count - 1].actions.removeLast()
        }
        wentThrough.removeLast()
        showSounds()
        moreCards = []
        isFlipped = last.showedLowerSide
        workOutIntervals()
        startTiming(from: last.timeOnCard)
        touch()
    }

    /// Takes back `action`, which Lucas did with `undone`, a card the panel
    /// showed one of its ways, in the engine: his answer to that way, or the
    /// card's flag, or its setting aside, which the engine undoes by
    /// unburying it. When the Cards window or `ficha fix` fixed the card, or
    /// the Cards window set it aside or put it back since, it can't be
    /// undone.
    private func takeBack(_ action: PanelAction, of undone: PanelCard) throws(EngineError) {
        let cardID = undone.card.id
        do throws(EngineError) {
            switch action {
            case .answered: try engine.takeBackAnswer(of: cardID, way: undone.way)
            case .flagged: try engine.unflag(cardID)
            case .setAside: try engine.unbury(cardID)
            }
        } catch .cardNotFlagged, .cardBuried, .cardNotBuried {
            throw .cannotUndo(cardID)
        }
    }

    /// Moves on to the next card, from its upper side, with its time starting
    /// now, once Lucas did `actions`, in order, with the current one after
    /// `timeOnCard` on it, and the deck his answer to it met in full, if any.
    /// After the last one, the panel looks for more cards to offer, and reads
    /// what it met in full.
    private mutating func moveOn(after actions: [PanelAction], timeOnCard: Duration) {
        wentThrough.append(
            Visit(
                actions: actions, showedLowerSide: isFlipped, timeOnCard: timeOnCard, metInFull: answerMetInFull))
        showSounds()
        answerMetInFull = nil
        isFlipped = false
        shownIntervals = nil
        flagging = nil
        startTiming()
        touch()
        if current == nil {
            lookForMore()
            readMetThemAll()
        }
    }

    /// Reads what the panel says it met in full, once Lucas went through its
    /// cards: the decks his answers met in full, as they are now, in the
    /// order they were met, each once, and the deck first in the queue new
    /// cards come from now, with the panel's settings, or, with none, the
    /// first of Ficha's decks the user hasn't added, among those the app gave
    /// it. When they can't be read, it says nothing of them, and the log says
    /// why.
    private mutating func readMetThemAll() {
        let met = wentThrough.compactMap(\.metInFull).uniqued()
        guard !met.isEmpty else {
            metInFull = nil
            return
        }
        do throws(EngineError) {
            let decks = try engine.decks()
            let next = try engine.queue(settings).first?.deck
            let fichaDeck = try next == nil ? engine.fichaDecks(among: fichaDecks ?? []).first : nil
            metInFull = MetThemAll(
                decks: met.compactMap { name in decks.first { $0.name == name } },
                nextInQueue: next.flatMap { name in decks.first { $0.name == name } }, fichaDeck: fichaDeck?.deck,
                fichaDeckEmoji: fichaDeck?.emoji)
        } catch {
            metInFull = nil
            logger.error("Couldn't read the decks met in full: \(String(describing: error), privacy: .public)")
        }
    }

    /// The decks at the top of the tree met in full now, out of the queue new
    /// cards come from, by their whole names, as the Cards window's rows say
    /// "Met them all" (`Engine.decksMetInFull()`): nil when they can't be
    /// read, and the log says why.
    private func decksMetInFull() -> Set<String>? {
        do throws(EngineError) {
            return try engine.decksMetInFull()
        } catch {
            logger.error("Couldn't read the decks met in full: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Finds the cards "See more" would add, now that Lucas went through
    /// every card. When they can't be found, the panel offers none, and says
    /// why.
    private mutating func lookForMore() {
        guard current == nil else { return }
        do {
            moreCards = try engine.seeMoreCards(after: Set(cards.map(\.cardWay)), from: trigger, settings: settings)
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
    /// Lucas's or the panel's own. A card the panel offers to flag isn't
    /// left: he answered it, and it stays in his reviews. It goes into the
    /// appearance log, unless it brought no cards: an empty review now holds
    /// no appearance back (Lucas, 2026-10-15). When it can't be recorded, the
    /// panel closes anyway, and the engine logs why.
    public mutating func close(_ closing: Closing) {
        guard outcome == nil else { return }
        let answered = wentThrough.count + (offersToFlag ? 1 : 0)
        let outcome: AppearanceLogEntry.Outcome =
            switch (answered >= broughtCount, closing) {
            case (true, _): .finished
            case (false, .byLucas): .snoozed
            case (false, .onItsOwn): .autoClosed
            }
        self.outcome = outcome
        playingSound = nil
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
private enum PanelAction: Sendable {
    /// He answered it: he rated it.
    case answered
    /// He flagged it.
    case flagged
    /// He set it aside.
    case setAside
}

/// A card Lucas went through in the review panel: what he did with it, which
/// ⌘Z undoes, how he left it, which ⌘Z shows again: whether its
/// lower side showed, and how long he had been on it, and the deck his
/// answer to it met in full, which ⌘Z forgets along with the visit.
private struct Visit: Sendable {
    /// What he did with it, in order: one thing, or his answer and then a
    /// flag, when the panel offered it. One ⌘Z undoes them all, the last
    /// first.
    var actions: [PanelAction]
    let showedLowerSide: Bool
    let timeOnCard: Duration
    /// The deck at the top of the tree whose last new card his answer met,
    /// by its whole name, or nil.
    let metInFull: String?
}

/// The note Lucas is writing to flag the card he's on, how long he had been
/// on the card when he started, and whether the panel offered it, after his
/// rating of again made the card forgotten often, rather than him asking.
private struct Flagging: Sendable {
    var note: String
    let timeOnCard: Duration
    let isOffer: Bool
}

extension Engine {
    /// Opens the review panel with `cards`, which `trigger` brought: the panel
    /// shows them from now on, and times Lucas on each on `clock`, a steady one,
    /// which moving the engine's time doesn't move: the system's continuous
    /// clock in the app. `forgottenOftenNote` writes the note the panel
    /// offers to flag a card forgotten often with, for how many times Lucas
    /// forgot it and which way, which the app words from its String
    /// Catalog.
    public func openPanel(
        _ trigger: Trigger, with cards: [PanelCard], settings: ReviewSettings, clock: some Clock<Duration>,
        forgottenOftenNote: @escaping @Sendable (ForgottenOften) -> String
    ) throws(EngineError) -> ReviewPanelState {
        ReviewPanelState(
            trigger: trigger, cards: cards, engine: self, settings: settings, clock: clock,
            forgottenOftenNote: forgottenOftenNote)
    }
}
