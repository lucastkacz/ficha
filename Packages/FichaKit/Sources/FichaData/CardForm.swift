import FichaCore
import Foundation

extension CardsWindowState {
    /// The form that creates cards in the Cards window, a sheet over it,
    /// opened by New Card, or by Convert to Card on a capture in the inbox,
    /// and open until Lucas closes it. It stays open after each card, as
    /// Anki's Add window does.
    public struct CardForm: Sendable, Equatable {
        /// The capture the form was opened from, which it shows beside its
        /// fields, or nil for a new card.
        public let capture: Capture?
        /// What the form's fields hold.
        public internal(set) var draft = Draft()
        /// The cards added since the form opened, oldest first.
        public internal(set) var addedCards: [Card] = []
        /// What the form says under the front, while it says something.
        public internal(set) var frontWarning: FrontWarning?

        /// Whether Add is on: while both sides have text, whatever the front
        /// repeats.
        public var canAdd: Bool {
            draft.content != nil
        }

        /// Whether closing the form approves the capture it was opened from,
        /// which then leaves the inbox: once a card was added from it.
        public var approvesCaptureOnClose: Bool {
            capture != nil && !addedCards.isEmpty
        }
    }
}

extension CardsWindowState.CardForm {
    /// What the form says under the front.
    public enum FrontWarning: Sendable, Equatable {
        /// That it repeats this card's front, by the duplicate rule, which
        /// the window can show.
        case repeats(Card)
        /// That whether it repeats another card's couldn't be checked, and
        /// why.
        case uncheckable(EngineError)
    }
}

extension CardsWindowState.CardForm {
    /// What the form's fields hold, as Lucas types them.
    public struct Draft: Sendable, Equatable {
        /// The type, or nil for None, which the form starts at.
        public var type: CardType?
        public var front = Side()
        public var back = Side()
        /// The tags as the Tags field holds them, separated by commas.
        public var tags = ""
        public var source = ""

        /// Empty fields, and the type None.
        public init() {}

        /// What Add saves, checked as every card is, or nil while a side is
        /// blank.
        var content: CardContent? {
            CardContent(
                type: type, front: front.text, back: back.text, tags: tags.split(separator: ",").map(String.init),
                source: source)
        }
    }

    /// One side of the card the form makes, a front or a back, as its field
    /// holds it.
    public struct Side: Sendable, Equatable {
        public var text = ""
    }
}

extension CardsWindowState {
    /// Opens the form on a new card: every field empty, and the type None.
    public mutating func openNewCardForm() {
        guard cardForm == nil else { return }
        cardForm = CardForm(capture: nil)
    }

    /// Convert to Card: opens the form from the capture the detail shows,
    /// while it's offered, with the capture's source filled in.
    public mutating func convertToCard() {
        guard cardForm == nil, actions.contains(.convertToCard), case .capture(let capture) = detail else { return }
        var form = CardForm(capture: capture)
        form.draft.source = capture.source ?? ""
        cardForm = form
    }

    /// Changes what the form's fields hold to `draft`, as Lucas types. When
    /// the front changes, the form checks again whether it repeats another
    /// card's.
    public mutating func changeDraft(_ draft: CardForm.Draft) {
        guard let form = cardForm else { return }
        cardForm?.draft = draft
        if draft.front != form.draft.front {
            let warning = frontWarning(for: draft.front)
            cardForm?.frontWarning = warning
        }
    }

    /// What the form says under `front`: the card it repeats, if any. A blank
    /// front repeats none.
    private func frontWarning(for front: CardForm.Side) -> CardForm.FrontWarning? {
        guard !CardContent.isBlank(front.text) else { return nil }
        do throws(EngineError) {
            return try engine.cardRepeated(byFront: front.text).map(CardForm.FrontWarning.repeats)
        } catch {
            return .uncheckable(error)
        }
    }

    /// Add: saves what the form holds as a new card, while Add is on, straight
    /// into Lucas's reviews as new. A card added from a capture keeps it as
    /// its capture, and the capture stays in the inbox until the form closes.
    /// Then it clears the front and the back, and keeps the type, the tags
    /// and the source, for the next card. When the card can't be saved, it
    /// records why, and the fields stay as they were.
    public mutating func addCard() {
        guard let form = cardForm, let content = form.draft.content else { return }
        var added: Card?
        perform(.addCard) { engine throws(EngineError) in added = try engine.create(content, from: form.capture?.id) }
        guard let added else { return }
        cardForm?.addedCards.append(added)
        cardForm?.draft.front = CardForm.Side()
        cardForm?.draft.back = CardForm.Side()
        // A blank front repeats no card.
        cardForm?.frontWarning = nil
        read(on: ladder)
    }

    /// Shows the card the front repeats, while the form warns about one: the
    /// form closes, as Close closes it, and the window selects the card in
    /// All cards, or in Buried when it's buried, with no search.
    public mutating func showRepeatedCard() {
        guard case .repeats(let card)? = cardForm?.frontWarning else { return }
        closeCardForm()
        choose(.cards(card.standing.isInAllCards ? .all : .buried))
        search(for: "")
        select([card.id])
    }

    /// Close: closes the form. Opened from a capture, once a card was added
    /// from it, it approves the capture, which leaves the inbox, as approving
    /// it in a refine session does; with none, the capture stays there. When
    /// the capture can't be approved, it records why, and the form closes all
    /// the same, since its cards are saved.
    public mutating func closeCardForm() {
        guard let form = cardForm else { return }
        cardForm = nil
        if form.approvesCaptureOnClose, let capture = form.capture {
            perform(.approveCapture) { engine throws(EngineError) in try engine.approve(capture.id) }
            read(on: ladder)
        }
    }
}
