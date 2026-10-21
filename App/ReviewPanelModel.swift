import FichaCore
import FichaData
import Foundation
import Observation

/// The cards a review now or an appearance brought, as the review panel shows
/// them, one at a time: Lucas ends a new card's first view with "Got it", and
/// flips and rates a due card, or one he reviews ahead. He can also flag any
/// card with a note on what to fix, or bury it, and undo what he did, one card
/// at a time. At the end, he can ask for more cards. The engine's
/// `ReviewPanelState` keeps what happens to the cards and to the panel, and
/// this model adds what only the panel shows: a card's back, the note he's
/// writing, how long he took, and why something couldn't be saved.
@Observable
final class ReviewPanelModel {
    /// What the panel shows.
    enum Content {
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

    private var state: ReviewPanelState
    private var isFlipped = false
    /// When the panel showed the current card: Lucas's response time runs from
    /// then to his answer. It's measured on the system's steady clock, since
    /// it's how long he took, not a time of day, so moving Ficha Dev's time
    /// doesn't change it.
    private var cardShownAt = ContinuousClock.now
    /// The note Lucas is writing to flag the current card, while he writes
    /// it, and how long he had been on the card when he started: the card's
    /// response time waits while he writes.
    private var flagging: (note: String, timeOnCard: Duration)?
    /// How Lucas left each card he went through, by id: ⌘Z shows it that way
    /// again.
    private var visits: [Int64: Visit] = [:]
    /// What Lucas did that couldn't be saved, while the panel says so.
    var failure: Failure?

    /// The panel for the cards in `state`, which shows them from now on.
    init(_ state: ReviewPanelState) {
        self.state = state
        sayIfMoreCardsFailed()
    }

    var content: Content {
        guard !state.cards.isEmpty else {
            return .nothingToReview
        }
        guard let current = state.current else {
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
    var canSeeMore: Bool {
        state.current == nil && !state.moreCards.isEmpty
    }

    /// The note Lucas is writing to flag the card he's on, while he writes it.
    var note: String? {
        flagging?.note
    }

    /// Whether the panel closed: Lucas closed it, or it closed on its own.
    var isClosed: Bool {
        state.outcome != nil
    }

    /// Whether the panel may have the keyboard: when Lucas opened it, or in
    /// an appearance, once the focus mode says so or Lucas clicks it.
    var mayHaveKeyboard: Bool {
        state.mayHaveKeyboard
    }

    /// Whether ⌘Z has something to undo, while Lucas isn't writing a note.
    var canUndo: Bool {
        state.canUndo && flagging == nil
    }

    /// Whether the note says what to fix, so the card can be flagged with it.
    var noteSaysWhatToFix: Bool {
        note.flatMap(FlagNote.init) != nil
    }

    /// Brings the cards "See more" offers, and shows the first of them.
    func seeMore() {
        guard canSeeMore else { return }
        state.seeMore()
        isFlipped = false
        cardShownAt = .now
    }

    /// Turns the card Lucas reviews to its back.
    func flip() {
        guard case .front = content else { return }
        isFlipped = true
        state.touch()
    }

    /// Ends the new card's first view, which puts it on the ladder's first
    /// step: "Got it".
    func endFirstView() {
        guard case .firstView = content else { return }
        goThrough(failing: "Couldn't save your answer", after: timeOnCard) { responseTime throws(EngineError) in
            try state.answer(.firstView, responseTime: responseTime)
        }
    }

    /// Rates the card Lucas reviews, once flipped, which moves it on the
    /// ladder: in a review ahead, only again does.
    func rate(_ rating: Rating) {
        guard case .back = content else { return }
        goThrough(failing: "Couldn't save your answer", after: timeOnCard) { responseTime throws(EngineError) in
            try state.answer(.review(rating), responseTime: responseTime)
        }
    }

    /// Starts flagging the card Lucas is on: the panel asks for a note on
    /// what to fix.
    func startFlagging() {
        guard isOnACard else { return }
        flagging = ("", timeOnCard)
        state.touch()
    }

    /// Takes the note as Lucas writes it, which keeps the panel open.
    func write(note: String) {
        guard flagging != nil else { return }
        flagging?.note = note
        state.touch()
    }

    /// Stops flagging the card: it stays as it was, and its response time
    /// goes on from where it waited.
    func cancelFlagging() {
        guard let flagging else { return }
        self.flagging = nil
        cardShownAt = .now - flagging.timeOnCard
        state.touch()
    }

    /// Flags the card with the note, which sends it to the inbox until it's
    /// fixed, and moves on to the next card.
    func flag() {
        guard let flagging, let note = FlagNote(flagging.note) else { return }
        goThrough(failing: "Couldn't flag the card", after: flagging.timeOnCard) { _ throws(EngineError) in
            try state.flag(note: note)
        }
    }

    /// Buries the card Lucas is on, which takes it out of his reviews for
    /// good, and moves on to the next card.
    func bury() {
        guard isOnACard else { return }
        goThrough(failing: "Couldn't bury the card", after: timeOnCard) { _ throws(EngineError) in
            try state.bury()
        }
    }

    /// Undoes what Lucas did with the last card he went through, and shows it
    /// again as he left it: ⌘Z.
    func undo() {
        guard canUndo else { return }
        do {
            try state.undo()
        } catch {
            failure = Failure(title: "Couldn't undo", error: error)
            return
        }
        guard let card = state.current?.card, let visit = visits[card.id] else { return }
        isFlipped = visit.showedBack
        cardShownAt = .now - visit.timeOnCard
    }

    /// Notes that Lucas clicked the panel, which gives it the keyboard.
    func clicked() {
        state.clicked()
    }

    /// Whether the panel takes the keyboard now, as the focus mode says, by
    /// how long `mac` says Lucas has been idle.
    func takesKeyboard(on mac: some DeviceSignals) -> Bool {
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

    /// Whether Lucas is on a card, as it shows, to answer, flag or bury it.
    private var isOnACard: Bool {
        switch content {
        case .firstView, .front, .back: true
        case .nothingToReview, .flagging, .done: false
        }
    }

    /// How long Lucas has been on the current card.
    private var timeOnCard: Duration {
        ContinuousClock.now - cardShownAt
    }

    /// Does what Lucas asked with the card he's on, after `timeOnCard` on it,
    /// which moves the panel on to the next card, and notes how he left the
    /// card, for ⌘Z. When it can't be saved, the card stays, and the panel
    /// says why under `title`.
    private func goThrough(
        failing title: LocalizedStringResource,
        after timeOnCard: Duration,
        doing action: (_ responseTime: Duration) throws(EngineError) -> Void
    ) {
        guard let card = state.current?.card else { return }
        do {
            try action(timeOnCard)
        } catch {
            failure = Failure(title: title, error: error)
            return
        }
        visits[card.id] = Visit(showedBack: isFlipped, timeOnCard: timeOnCard)
        isFlipped = false
        flagging = nil
        cardShownAt = .now
        sayIfMoreCardsFailed()
    }

    /// Says why the panel couldn't look for the cards "See more" would add,
    /// if it couldn't, once Lucas went through every card.
    private func sayIfMoreCardsFailed() {
        guard state.current == nil, let error = state.moreCardsFailure else { return }
        failure = Failure(title: "Couldn't look for more cards", error: error)
    }
}

/// How Lucas left a card he went through in the review panel: whether its
/// back showed, and how long he had been on it.
private struct Visit {
    let showedBack: Bool
    let timeOnCard: Duration
}
