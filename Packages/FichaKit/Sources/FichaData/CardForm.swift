import FichaCore
import Foundation

extension CardsWindowState {
    /// The form that creates cards in the Cards window, a sheet over it,
    /// opened by New Card, or by Convert to Card on a capture or a follow-up
    /// in the inbox, and open until the user closes it. It stays open after
    /// each card, as Anki's Add window does.
    public struct CardForm: Sendable, Equatable {
        /// What opened the form.
        let openedBy: Opener
        /// What the form's fields hold.
        public internal(set) var draft = Draft()
        /// The cards added since the form opened, oldest first.
        public internal(set) var addedCards: [Card] = []
        /// What the form says under the front, while it says something.
        public internal(set) var frontWarning: FrontWarning?

        /// The capture the form was opened from, a follow-up's included,
        /// which it shows beside its fields, or nil for a new card.
        public var capture: Capture? {
            switch openedBy {
            case .newCard: nil
            case .capture(let capture): capture
            case .followUp(let followUp): followUp.capture
            }
        }

        /// The follow-up the form was opened from, with its card as it was
        /// then, which the form shows below the capture, or nil when it was
        /// opened from a plain capture or for a new card. The cards the form
        /// adds sit beside that card, which stays as it is.
        public var followUp: FollowUp? {
            guard case .followUp(let followUp) = openedBy else { return nil }
            return followUp
        }

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
    /// What opened the form.
    enum Opener: Sendable, Equatable {
        /// New Card.
        case newCard
        /// Convert to Card on this capture.
        case capture(Capture)
        /// Convert to Card on this follow-up, with its card as it was then.
        case followUp(FollowUp)
    }

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
    /// What the form's fields hold, as the user types them.
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
        /// blank: it has neither text nor an image.
        var content: CardContent? {
            CardContent(
                type: type, front: front.text, back: back.text, tags: CardContent.tags(inField: tags),
                source: source, frontImage: front.image, backImage: back.image)
        }

        /// The side `side` of the draft.
        subscript(side: CardSide) -> Side {
            get {
                switch side {
                case .front: front
                case .back: back
                }
            }
            set {
                switch side {
                case .front: front = newValue
                case .back: back = newValue
                }
            }
        }
    }

    /// One side of the card the form makes, a front or a back, as its field
    /// holds it, and the image the user dragged or pasted on it, if any, which
    /// the window holds until Add keeps it (`CardsWindowImages.swift`).
    public struct Side: Sendable, Equatable {
        public var text = ""
        public internal(set) var image: ImageName?
    }
}

extension CardsWindowState {
    /// Opens the form on a new card: every field empty, and the type None;
    /// or brings back the new card's form Show Card set aside, as it was.
    public mutating func openNewCardForm() {
        guard cardForm == nil else { return }
        openCardForm(CardForm(openedBy: .newCard))
    }

    /// Convert to Card: opens the form from the capture the detail shows,
    /// while it's offered, with the capture's source filled in, or from the
    /// follow-up it shows, with its card beside it and the card's tags filled
    /// in, so the new cards land next to it; or brings back the form from
    /// that capture or follow-up Show Card set aside, as it was.
    public mutating func convertToCard() {
        guard cardForm == nil, actions.contains(.convertToCard) else { return }
        var form: CardForm
        switch detail {
        case .capture(let capture):
            form = CardForm(openedBy: .capture(capture))
        case .followUp(let followUp):
            form = CardForm(openedBy: .followUp(followUp))
            form.draft.tags = CardContent.tagsField(of: followUp.card.tags)
        case .expansion, .card, .cards, .nothingSelectedInInbox, .noCardSelected:
            return
        }
        form.draft.source = form.capture?.source ?? ""
        openCardForm(form)
    }

    /// Opens `form`, or the form Show Card set aside when it was opened the
    /// same way, from the same capture or from none, with what its front
    /// repeats checked again. A form set aside that was opened another way
    /// closes for good first.
    private mutating func openCardForm(_ form: CardForm) {
        if let setAside = setAsideCardForm {
            setAsideCardForm = nil
            if setAside.capture?.id == form.capture?.id {
                cardForm = setAside
            } else {
                finishClosing(setAside)
                cardForm = form
            }
        } else {
            cardForm = form
        }
        readFrontsInUse()
    }

    /// Reads the cards' fronts, while the form is open, and checks again
    /// whether its front repeats one: when the form opens, and each time the
    /// window reads the cards.
    mutating func readFrontsInUse() {
        guard let front = cardForm?.draft.front else {
            frontsInUse = nil
            return
        }
        frontsInUse = Result { () throws(EngineError) in try engine.frontsInUse() }
        let warning = frontWarning(for: front)
        cardForm?.frontWarning = warning
    }

    /// Changes what the form's fields hold to `draft`, as the user types.
    /// When the front changes, the form checks again whether it repeats
    /// another card's, among the fronts as the window last read them.
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
        do throws(EngineError) {
            guard let frontsInUse, let cardID = try frontsInUse.get().cardID(repeatedBy: front.text) else {
                return nil
            }
            return .repeats(try engine.card(cardID))
        } catch {
            return .uncheckable(error)
        }
    }

    /// Add: saves what the form holds as a new card, while Add is on, straight
    /// into the user's reviews as new, with the images on its sides, which Ficha
    /// keeps from then on. A card added from a capture keeps it as its
    /// capture, and the capture stays in the inbox until the form closes.
    /// Then it clears the front and the back, their images too, and keeps the
    /// type, the tags and the source, for the next card. When the card can't
    /// be saved, it records why, and the fields stay as they were.
    public mutating func addCard() {
        guard let form = cardForm, let content = form.draft.content else { return }
        var added: Card?
        let images = heldImages(of: content)
        perform(.addCard) { engine throws(EngineError) in
            added = try engine.create(keeping: images, content, from: form.capture?.id)
        }
        guard let added else { return }
        cardForm?.addedCards.append(added)
        cardForm?.draft.front = CardForm.Side()
        cardForm?.draft.back = CardForm.Side()
        // A blank front repeats no card.
        cardForm?.frontWarning = nil
        read(on: ladder)
    }

    /// Shows the card the front repeats, while the form warns about one: the
    /// form goes, set aside as it is, with the images on its sides, until
    /// it's opened the same way again, and the window selects the card in
    /// All cards, or in Buried when it's buried, with no search, and scrolls
    /// to it. A capture the form came from stays in the inbox meanwhile.
    public mutating func showRepeatedCard() {
        guard case .repeats(let card)? = cardForm?.frontWarning else { return }
        setAsideCardForm = cardForm
        cardForm = nil
        choose(.cards(card.standing.isInAllCards ? .all : .buried))
        search(for: "")
        select([card.id])
        cardToReveal = card.id
    }

    /// Says the table scrolled to the card it was to reveal.
    public mutating func cardRevealed() {
        cardToReveal = nil
    }

    /// Close: closes the form. Opened from a capture, once a card was added
    /// from it, it approves the capture, which leaves the inbox, as approving
    /// it in a refine session does; with none, the capture stays there. When
    /// the capture can't be approved, it records why, and the form closes all
    /// the same, since its cards are saved.
    public mutating func closeCardForm() {
        guard let form = cardForm else { return }
        cardForm = nil
        frontsInUse = nil
        finishClosing(form)
    }

    /// Closes `form` for good, once it's no longer open, as Close does.
    private mutating func finishClosing(_ form: CardForm) {
        // Images put on the last card, which Add never saved, go.
        showImages()
        if form.approvesCaptureOnClose, let capture = form.capture {
            perform(.approveCapture) { engine throws(EngineError) in try engine.approve(capture.id) }
            read(on: ladder)
        }
    }
}
