import FichaCore
import FichaData
import Observation

/// The cards a review now or an appearance brought, as the review panel shows
/// them, one at a time: Lucas ends a new card's first view with "Got it", and
/// flips and rates a due card. He can also flag any card with a note on what
/// to fix, or bury it, and undo what he did, one card at a time. The engine's
/// `ReviewPanelState` keeps what happens to the cards and to the panel, and
/// this model adds what only the panel shows: a card's back, the note he's
/// writing, how long he took, and why something couldn't be saved.
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
        /// The card Lucas is on, as it showed, its back included or not,
        /// while he writes a note on what to fix in it.
        case flagging(Card, showsBack: Bool)
        /// Lucas went through every card.
        case done
    }

    /// What Lucas tried to do, when it couldn't be saved.
    enum Attempt {
        case answer
        case flag
        case bury
        case undo
    }

    private var state: ReviewPanelState
    private var isFlipped = false
    /// When the panel showed the current card: Lucas's response time runs from
    /// then to his answer. It's measured on the system's steady clock, since
    /// it's how long he took, not a time of day, so moving Ficha Dev's time
    /// doesn't change it.
    private var cardShownAt = ContinuousClock.now
    /// How Lucas left each card he went through, in order: flipped or not,
    /// and after how long. ⌘Z shows the card that way again, and its response
    /// time goes on from there.
    private var leftCards: [(isFlipped: Bool, timeOnCard: Duration)] = []
    /// The note Lucas is writing to flag the current card, while he writes
    /// it.
    private(set) var note: String?
    /// Why what Lucas tried last couldn't be saved, while the panel says so.
    var failure: EngineError?
    /// What Lucas tried when it failed.
    private(set) var failedAttempt = Attempt.answer

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
        if note != nil {
            return switch current {
            case .firstView(let card): .flagging(card, showsBack: true)
            case .review(let card): .flagging(card, showsBack: isFlipped)
            }
        }
        return switch current {
        case .firstView(let card): .firstView(card)
        case .review(let card): isFlipped ? .back(card) : .front(card)
        }
    }

    /// Whether the panel closed: Lucas went through every card or closed it,
    /// or it closed on its own.
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
        state.canUndo && note == nil
    }

    /// Whether the note says what to fix, so the card can be flagged with it.
    var noteSaysWhatToFix: Bool {
        note.flatMap(FlagNote.init) != nil
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
        goThrough(.answer) { responseTime throws(EngineError) in
            try state.answer(.firstView, responseTime: responseTime)
        }
    }

    /// Rates the due card, once flipped, which moves it on the ladder.
    func rate(_ rating: Rating) {
        guard case .back = content else { return }
        goThrough(.answer) { responseTime throws(EngineError) in
            try state.answer(.review(rating), responseTime: responseTime)
        }
    }

    /// Starts flagging the card Lucas is on: the panel asks for a note on
    /// what to fix.
    func startFlagging() {
        guard isOnACard else { return }
        note = ""
        state.touch()
    }

    /// Takes the note as Lucas writes it, which keeps the panel open.
    func write(note: String) {
        guard self.note != nil else { return }
        self.note = note
        state.touch()
    }

    /// Stops flagging the card: it stays as it was.
    func cancelFlagging() {
        note = nil
        state.touch()
    }

    /// Flags the card with the note, which sends it to the inbox until a
    /// refine session fixes it, and moves on to the next card.
    func flag() {
        guard let note, let flagNote = FlagNote(note) else { return }
        goThrough(.flag) { _ throws(EngineError) in
            try state.flag(note: flagNote)
        }
    }

    /// Buries the card Lucas is on, which takes it out of his reviews for
    /// good, and moves on to the next card.
    func bury() {
        guard isOnACard else { return }
        goThrough(.bury) { _ throws(EngineError) in
            try state.bury()
        }
    }

    /// Undoes what Lucas did with the last card he went through, and shows it
    /// again as he left it: ⌘Z.
    func undo() {
        guard canUndo, let left = leftCards.last else { return }
        do {
            try state.undo()
        } catch {
            fail(.undo, error)
            return
        }
        leftCards.removeLast()
        isFlipped = left.isFlipped
        cardShownAt = .now - left.timeOnCard
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

    /// Whether Lucas is on a card, as it shows, to answer, flag or bury it.
    private var isOnACard: Bool {
        switch content {
        case .firstView, .front, .back: true
        case .nothingToReview, .flagging, .done: false
        }
    }

    /// Does what Lucas asked with the card he's on, given how long he's been
    /// on it, which moves the panel on to the next card, and notes how he left
    /// it for ⌘Z. When it can't be saved, the card stays, and the panel says
    /// why.
    private func goThrough(
        _ attempt: Attempt,
        doing action: (_ responseTime: Duration) throws(EngineError) -> Void
    ) {
        let timeOnCard = ContinuousClock.now - cardShownAt
        do {
            try action(timeOnCard)
        } catch {
            fail(attempt, error)
            return
        }
        leftCards.append((isFlipped, timeOnCard))
        isFlipped = false
        note = nil
        cardShownAt = .now
    }

    /// Says that `attempt` couldn't be saved, and why.
    private func fail(_ attempt: Attempt, _ error: EngineError) {
        failedAttempt = attempt
        failure = error
    }
}
