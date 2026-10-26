import FichaCore
import Foundation

/// An appearance or a review now while the review panel shows it: the cards
/// it brought, which Lucas goes through one at a time, what the panel shows of
/// the card he's on, its tags included, whether the panel may have the
/// keyboard, and how it closes. Each card comes one of its ways, front first
/// or back first, and his answers move only that way. He ends a new way's
/// first view, back first once he flipped it, and flips and rates a due way,
/// or one he reviews ahead. He plays a side's sound
/// only when he asks, one at a time, until he answers the card, writes about
/// it or leaves it, or the panel closes. He can also flag any card
/// with a note on what to fix, or bury it, and ask questions about it, each a
/// follow-up in the inbox, without leaving it. When his rating of again makes
/// a card forgotten often, the panel offers to flag it, with a note that says
/// how many times he forgot it. Each is saved as he does it,
/// and ⌘Z undoes it, the last first, while the panel is open, and shows the
/// card again as he left it. Once he went through every card, the panel stays
/// open and offers more cards, if there are any, until he closes it. The
/// panel goes into the appearance log as it closes. It runs on the engine's
/// time, which Ficha Dev's debug menu moves forward, and times Lucas on a
/// steady clock, which it doesn't.
public struct ReviewPanelState: Sendable {
    /// Who closes the panel.
    public enum Closing: Sendable {
        /// Lucas: with Esc or the close button, or by quitting Ficha.
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
        /// A new way of a card, whole, for its first view: front first from
        /// the start, and back first once Lucas flipped it.
        case firstView(Card, Way = .frontFirst)
        /// A way of a card, its upper side alone, for Lucas to remember the
        /// other: a due way, one he reviews ahead, or a new back-first way,
        /// in its first view, marked as new.
        case upperSide(Card, Way = .frontFirst, isNew: Bool = false, isAhead: Bool = false)
        /// A due way of a card, or one Lucas reviews ahead, its upper side
        /// and its lower side, for him to rate it.
        case bothSides(Card, Way = .frontFirst, isAhead: Bool = false)
        /// The card Lucas is on, as it showed, its lower side included or
        /// not, while he writes a note on what to fix in it, also when the
        /// panel offers to flag it.
        case flagging(Card, Way = .frontFirst, showsLowerSide: Bool)
        /// The card Lucas is on, as it showed, its lower side included or
        /// not, while he writes a question about it, to follow it up.
        case asking(Card, Way = .frontFirst, showsLowerSide: Bool)
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
        /// He asked a question about a card, to follow it up.
        case ask
        /// He undid the last thing he did.
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
    /// The images on the cards' sides, read once the panel has the cards,
    /// as it opens and as "See more" adds them.
    public private(set) var images = ShownImages()
    /// The sounds on the sides of the card Lucas is on, with their lengths,
    /// read as it shows.
    public internal(set) var sounds = ShownSounds()
    /// The sound that plays, which Lucas asked for, if any.
    public internal(set) var playingSound: PlayingSound?
    /// What every tag has of its own, as it was when the panel opened: a tag
    /// changed while it's open shows from the next panel on, so the card
    /// Lucas is on doesn't change under him.
    private let ownTags: OwnTags
    let engine: Engine
    private let settings: ReviewSettings
    /// The note the panel offers to flag a card forgotten often with, for
    /// how many times Lucas forgot it, in the Mac's language.
    private let forgottenOftenNote: @Sendable (Int) -> String
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
    /// The note Lucas is writing to flag the card he's on, while he writes
    /// it.
    private var flagging: Flagging?
    /// The question Lucas is writing about the card he's on, while he writes
    /// it.
    private var asking: Asking?
    /// What Lucas did with each card he went through, in order, and how he
    /// left it: ⌘Z undoes the last one, and shows the card that way again.
    private var wentThrough: [Visit] = []
    /// The ids of the follow-ups Lucas asked about the card he's on, in the
    /// order he asked them: ⌘Z deletes the last one before it goes back to
    /// the card before.
    private var followUpsOnCard: [Int64] = []

    init(
        trigger: Trigger, cards: [PanelCard], ownTags: OwnTags, engine: Engine, settings: ReviewSettings,
        clock: some Clock<Duration>, forgottenOftenNote: @escaping @Sendable (Int) -> String
    ) {
        self.trigger = trigger
        self.cards = cards
        broughtCount = cards.count
        self.ownTags = ownTags
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

    /// The tags of the card Lucas is on, in the card's order, each with its
    /// color and emoji as they were when the panel opened, which the panel
    /// shows at the card's top, or none once he went through every card.
    public var tags: [CardTag] {
        current?.card.tags.map(ownTags.tag) ?? []
    }

    /// What the panel shows: the card Lucas is on, the way it came, its
    /// upper side alone or with its lower side, or as it showed while he
    /// writes a note to flag it or a question about it, or that there was
    /// nothing to review, or that he went through every card. A first view
    /// front first shows the whole card from the start; back first, its back
    /// until he flips it, as a review does.
    public var content: Content {
        guard !cards.isEmpty else {
            return .nothingToReview
        }
        guard let current else {
            return .done
        }
        let (card, way) = (current.card, current.way)
        let showsLowerSide =
            switch current {
            case .firstView(_, .frontFirst): true
            case .firstView, .review, .reviewAhead: isFlipped
            }
        if flagging != nil {
            return .flagging(card, way, showsLowerSide: showsLowerSide)
        }
        if asking != nil {
            return .asking(card, way, showsLowerSide: showsLowerSide)
        }
        return switch (current, showsLowerSide) {
        case (.firstView, true): .firstView(card, way)
        case (.firstView, false): .upperSide(card, way, isNew: true)
        case (.review, false), (.reviewAhead, false): .upperSide(card, way, isAhead: current.isAhead)
        case (.review, true), (.reviewAhead, true): .bothSides(card, way, isAhead: current.isAhead)
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

    /// Whether the panel offers to flag the card Lucas is on, which he just
    /// rated again and forgot often: then cancelling moves on without
    /// flagging it.
    public var offersToFlag: Bool {
        flagging?.isOffer == true
    }

    /// The question Lucas is writing about the card he's on, while he writes
    /// it.
    public var question: String? {
        asking?.question
    }

    /// Whether the question asks something, so it can be saved as a
    /// follow-up: a blank one can't.
    public var questionAsksSomething: Bool {
        question.flatMap { CaptureContent(text: $0, note: nil, source: nil) } != nil
    }

    /// Whether ⌘Z has something to undo: a follow-up Lucas asked about the
    /// card he's on, or what he did with a card he went through, while the
    /// panel is open and he isn't writing a note or a question.
    public var canUndo: Bool {
        outcome == nil && (!followUpsOnCard.isEmpty || !wentThrough.isEmpty) && flagging == nil && asking == nil
    }

    /// Whether Lucas is on a card, as it shows, to answer, flag, bury or ask
    /// about it.
    var isOnACard: Bool {
        switch content {
        case .firstView, .upperSide, .bothSides: true
        case .nothingToReview, .flagging, .asking, .done: false
        }
    }

    /// How long Lucas has been on the card he's on: while he writes a note to
    /// flag it or a question about it, as long as when he started.
    private var timeOnCard: Duration {
        flagging?.timeOnCard ?? asking?.timeOnCard ?? sinceOpening() - cardShownAt
    }

    /// Shows the lower side of the card Lucas is on under its upper side:
    /// Space, from its upper side alone, in a review or in a back-first first
    /// view.
    public mutating func flip() {
        guard case .upperSide = content else { return }
        isFlipped = true
        touch()
    }

    /// Ends the first view of the new way of a card, once it shows whole,
    /// which puts that way on the ladder's first step, with how long Lucas
    /// took, and moves on to the next card: "Got it". When it can't be
    /// saved, the card stays, and the panel says why.
    public mutating func endFirstView() {
        guard case .firstView = content else { return }
        perform(.answer) { panel throws(EngineError) in
            try panel.answer(.firstView, responseTime: panel.timeOnCard)
        }
    }

    /// Rates the way of the card Lucas reviews, once its lower side shows,
    /// which moves that way on the ladder, with how long he took, and moves
    /// on to the next card: in a review ahead, only again moves it. When a
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

    /// Flags the card with the note Lucas wrote, which sends it to the inbox
    /// until it's fixed, and moves on to the next card, also when the panel
    /// offered it, after his rating. When it can't be saved, the card stays,
    /// with the note, and the panel says why.
    public mutating func finishFlagging() {
        guard let note = note.flatMap(FlagNote.init) else { return }
        perform(.flag) { panel throws(EngineError) in try panel.flag(note: note) }
    }

    /// Starts asking about the card Lucas is on, its upper side alone or with
    /// its lower side: the panel asks for his question, the card's response
    /// time waits while he writes it, and its sound stops.
    public mutating func startAsking() {
        guard isOnACard else { return }
        asking = Asking(question: "", timeOnCard: timeOnCard)
        playingSound = nil
        touch()
    }

    /// Takes the question as Lucas writes it, which keeps the panel open.
    public mutating func write(question: String) {
        guard asking != nil else { return }
        asking?.question = question
        touch()
    }

    /// Stops asking about the card: it stays as it showed, and its response
    /// time goes on from where it waited.
    public mutating func cancelAsking() {
        guard let asking else { return }
        self.asking = nil
        startTiming(from: asking.timeOnCard)
        touch()
    }

    /// Saves the question Lucas wrote as a follow-up on the card he's on,
    /// which waits in the inbox tied to it, without rating the card: the
    /// panel stays on it, its side as it was, and its response time goes on
    /// from where it waited. He can ask again. A blank question isn't saved.
    /// When it can't be saved, the question stays, and the panel says why.
    public mutating func finishAsking() {
        guard let asking, questionAsksSomething, outcome == nil, let current else { return }
        perform(.ask) { panel throws(EngineError) in
            let followUp = try panel.engine.followUp(current.card.id, text: asking.question)
            panel.followUpsOnCard.append(followUp.id)
            panel.asking = nil
            panel.startTiming(from: asking.timeOnCard)
            panel.touch()
        }
    }

    /// Buries the card Lucas is on, which takes it out of his reviews for
    /// good, and moves on to the next card. When it can't be saved, the card
    /// stays, and the panel says why.
    public mutating func buryCard() {
        guard isOnACard else { return }
        perform(.bury) { panel throws(EngineError) in try panel.bury() }
    }

    /// Undoes the last thing Lucas did: the last follow-up he asked about the
    /// card he's on, or else what he did with the last card he went through,
    /// and shows that card again as he left it: ⌘Z. When it can't be undone,
    /// the panel stays where it is, and says why.
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
    /// When the engine says a rating of again made the card forgotten often,
    /// the panel stays on it instead, flagging it, with the note written as
    /// how many times he forgot it, and the card's time stopped at his
    /// answer. The panel's buttons answer through `endFirstView()` and
    /// `rate(_:)`, which time him on the steady clock, and say what failed.
    public mutating func answer(_ kind: ReviewLogEntry.Kind, responseTime: Duration) throws(EngineError) {
        guard outcome == nil, let answering = current else { return }
        let forgottenOften = try engine.record(
            kind, of: answering.card.id, way: answering.way, responseTime: responseTime, trigger: trigger,
            settings: settings, reviewingAhead: answering.isAhead)
        // Also when the panel stays on the card, to offer to flag it.
        playingSound = nil
        guard let forgottenOften else {
            moveOn(after: [.answered], timeOnCard: responseTime)
            return
        }
        flagging = Flagging(note: forgottenOftenNote(forgottenOften.times), timeOnCard: responseTime, isOffer: true)
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

    /// Flags the current card with Lucas's note on what to fix, which sends
    /// it to the inbox, and moves on to the next card. When the panel offered
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

    /// Buries the current card, which takes it out of Lucas's reviews for
    /// good, and moves on to the next card. The panel's button buries it
    /// through `buryCard()`, which says what failed.
    public mutating func bury() throws(EngineError) {
        guard outcome == nil, let burying = current else { return }
        let timeOnCard = self.timeOnCard
        try engine.bury(burying.card.id)
        moveOn(after: [.buried], timeOnCard: timeOnCard)
    }

    /// Undoes the last thing Lucas did, ⌘Z, the last first. On the card he's
    /// on, the engine takes back the last follow-up he asked about it, and
    /// the panel stays on the card as it shows. With none left there, it
    /// undoes what he did with the last card he went through, which puts the
    /// card's way back where it stood, and goes back to it, as he left it,
    /// its lower side showing or not, with its time going on from where it
    /// was, and with the follow-ups he asked about it, which the next ⌘Z
    /// takes back: also once he went through every card. The engine takes
    /// back his answer to that way, unflags the card or unburies it, or, for
    /// a card he flagged when the panel offered it, unflags it and then takes
    /// back his answer. When the card
    /// or the follow-up changed outside the panel since, nothing more is
    /// undone. Nothing is left to undo once the panel closed. The panel's ⌘Z
    /// undoes through `undoLastCard()`, which says what failed.
    public mutating func undo() throws(EngineError) {
        guard canUndo else { return }
        if let followUpID = followUpsOnCard.last, let current {
            try engine.takeBackFollowUp(followUpID, of: current.card.id)
            followUpsOnCard.removeLast()
            touch()
            return
        }
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
        followUpsOnCard = last.followUps
        moreCards = []
        isFlipped = last.showedLowerSide
        startTiming(from: last.timeOnCard)
        touch()
    }

    /// Takes back `action`, which Lucas did with `undone`, a card the panel
    /// showed one of its ways, in the engine: his answer to that way, or the
    /// card's flag or its burial. When a refine session or the Cards window
    /// fixed, buried or unburied the card since, it can't be undone.
    private func takeBack(_ action: PanelAction, of undone: PanelCard) throws(EngineError) {
        let cardID = undone.card.id
        do throws(EngineError) {
            switch action {
            case .answered: try engine.takeBackAnswer(of: cardID, way: undone.way)
            case .flagged: try engine.unflag(cardID)
            case .buried: try engine.unbury(cardID)
            }
        } catch .cardNotFlagged, .cardBuried, .cardNotBuried {
            throw .cannotUndo(cardID)
        }
    }

    /// Moves on to the next card, from its upper side, with its time starting
    /// now, once Lucas did `actions`, in order, with the current one after
    /// `timeOnCard` on it. After the last one, the panel looks for more cards
    /// to offer.
    private mutating func moveOn(after actions: [PanelAction], timeOnCard: Duration) {
        wentThrough.append(
            Visit(
                actions: actions, followUps: followUpsOnCard, showedLowerSide: isFlipped, timeOnCard: timeOnCard))
        showSounds()
        followUpsOnCard = []
        isFlipped = false
        flagging = nil
        asking = nil
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
    /// He answered it: he ended its first view, or rated it.
    case answered
    /// He flagged it.
    case flagged
    /// He buried it.
    case buried
}

/// A card Lucas went through in the review panel: what he did with it, which
/// ⌘Z undoes, the follow-ups he asked about it, which ⌘Z takes back once it's
/// back on the card, and how he left it, which ⌘Z shows again: whether its
/// lower side showed, and how long he had been on it.
private struct Visit: Sendable {
    /// What he did with it, in order: one thing, or his answer and then a
    /// flag, when the panel offered it. One ⌘Z undoes them all, the last
    /// first.
    var actions: [PanelAction]
    /// The ids of the follow-ups, in the order he asked them.
    let followUps: [Int64]
    let showedLowerSide: Bool
    let timeOnCard: Duration
}

/// The note Lucas is writing to flag the card he's on, how long he had been
/// on the card when he started, and whether the panel offered it, after his
/// rating of again made the card forgotten often, rather than him asking.
private struct Flagging: Sendable {
    var note: String
    let timeOnCard: Duration
    let isOffer: Bool
}

/// The question Lucas is writing about the card he's on, and how long he had
/// been on the card when he started.
private struct Asking: Sendable {
    var question: String
    let timeOnCard: Duration
}

extension Engine {
    /// Opens the review panel with `cards`, which `trigger` brought: the panel
    /// shows them from now on, with their tags' colors and emoji as they are
    /// now, and times Lucas on each on `clock`, a steady one, which moving the
    /// engine's time doesn't move: the system's continuous clock in the app.
    /// `forgottenOftenNote` writes the note the panel offers to flag a card
    /// forgotten often with, for how many times Lucas forgot it, in the Mac's
    /// language, which the app translates.
    public func openPanel(
        _ trigger: Trigger, with cards: [PanelCard], settings: ReviewSettings, clock: some Clock<Duration>,
        forgottenOftenNote: @escaping @Sendable (Int) -> String
    ) throws(EngineError) -> ReviewPanelState {
        ReviewPanelState(
            trigger: trigger, cards: cards, ownTags: try read(OwnTags.init(in:)), engine: self,
            settings: settings, clock: clock, forgottenOftenNote: forgottenOftenNote)
    }
}
