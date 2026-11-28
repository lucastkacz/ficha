import FichaCore
import Foundation

extension CardsWindowState {
    /// The form that creates cards in the Cards window, a sheet over it,
    /// opened by New Card, and open until the user closes it. It stays open
    /// after each card, as Anki's Add window does.
    public struct CardForm: Sendable, Equatable {
        /// What the form's fields hold.
        public internal(set) var draft = Draft()
        /// The cards added since the form opened, oldest first.
        public internal(set) var addedCards: [Card] = []
        /// What the form says under the front, while it says something.
        public internal(set) var frontWarning: FrontWarning?
        /// The work converting a sound dropped or pasted on a side, by side,
        /// while it converts: `CardsWindowSounds.swift`.
        var soundsComingIn: [CardSide: UUID] = [:]

        /// What Add saves, checked as every card is, or nil while a side is
        /// blank: it has neither text, an image nor a sound. A card the form
        /// adds has no tags and no type, which the form doesn't show (#538).
        var content: CardContent? {
            CardContent(
                type: nil, front: draft.front.text, back: draft.back.text, tags: [], source: draft.source,
                frontImage: draft.front.image, backImage: draft.back.image, frontSound: draft.front.sound,
                backSound: draft.back.sound)
        }

        /// Whether Add is on: while both sides have text, an image or a
        /// sound, whatever the front repeats, and no sound is converting for
        /// a side.
        public var canAdd: Bool {
            content != nil && soundsComingIn.isEmpty
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
    /// What the form's fields hold, as the user types them.
    public struct Draft: Sendable, Equatable {
        public var front = Side()
        public var back = Side()
        public var source = ""
        /// Whether the card goes both ways, which the form starts off.
        public var bothWays = false
        /// The deck the Deck field holds, by its whole name, or Default's,
        /// which Add puts the card in, making it if it isn't there: the deck
        /// the form starts in, as `CardsWindowDecks.swift` decides it, until
        /// the user picks another, or names one with New Deck….
        public var deck = Deck.defaultName

        /// Empty fields, Both ways off, and Default.
        public init() {}

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
    /// holds it, and the image and the sound the user dragged or pasted on
    /// it, if any, which the window holds until Add keeps them
    /// (`CardsWindowImages.swift` and `CardsWindowSounds.swift`).
    public struct Side: Sendable, Equatable {
        public var text = ""
        public internal(set) var image: ImageName?
        public internal(set) var sound: SoundName?
    }
}

extension CardsWindowState {
    /// Opens the form on a new card: every field empty, Both ways off, and
    /// the deck a new card starts in (`CardsWindowDeckField.swift`); or
    /// brings back the form Show Card set aside, as it was, with what its
    /// front repeats checked again.
    public mutating func openNewCardForm() {
        guard cardForm == nil else { return }
        if let setAside = setAsideCardForm {
            setAsideCardForm = nil
            cardForm = setAside
        } else {
            var form = CardForm()
            form.draft.deck = deckANewCardStartsIn
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
    /// into the user's reviews as new, with the images and sounds on its
    /// sides, which Ficha keeps from then on, going both ways when the form
    /// says so, in the deck the Deck field holds, made if it isn't there,
    /// which becomes the deck the last card was added to. Then it clears the
    /// front and the back, their
    /// images and sounds too, and keeps the deck, the source and Both ways,
    /// for the next card. While the grid lists the card, at its end, as it
    /// lists cards in the order they came in, the window selects it and
    /// scrolls to it, unless Lucas is editing a card meanwhile; a card that
    /// went to a deck the grid doesn't list leaves the selection as it was.
    /// When the card can't be saved, it records why, and the fields stay as
    /// they were.
    public mutating func addCard() {
        guard let form = cardForm, form.canAdd, let content = form.content else { return }
        var added: Card?
        let files = heldFiles(of: content)
        perform(.addCard) { engine throws(EngineError) in
            added = try engine.create(keeping: files, content, deck: form.draft.deck, bothWays: form.draft.bothWays)
        }
        guard let added else { return }
        lastDeckAddedTo = added.deck
        cardForm?.addedCards.append(added)
        cardForm?.draft.front = CardForm.Side()
        cardForm?.draft.back = CardForm.Side()
        // A blank front repeats no card.
        cardForm?.frontWarning = nil
        readAgain()
        if editing == nil, gridCardIDs.contains(added.id) {
            select([added.id])
            cardToReveal = added.id
        }
    }

    /// Shows the card the front repeats, while the form warns about one: the
    /// form goes, set aside as it is, with the images and sounds on its
    /// sides, until it's opened the same way again, and the window chooses
    /// the card's deck, with no search, selects the card and scrolls to it,
    /// since the deck lists every card of its own, one the user set aside
    /// included (#539). One of Ficha's decks the review panel asked for
    /// meanwhile waits for the window's next read (`read(with:)`), so the
    /// window stays on the card.
    public mutating func showRepeatedCard() {
        guard case .repeats(let card)? = cardForm?.frontWarning else { return }
        setAsideCardForm = cardForm
        cardForm = nil
        choose(.cards(.deck(card.deck)))
        search(for: "")
        select([card.id])
        cardToReveal = card.id
    }

    /// Says the grid scrolled to the card it was to reveal.
    public mutating func cardRevealed() {
        cardToReveal = nil
    }

    /// Close: closes the form, and the images and sounds put on its last
    /// card, which Add never saved, go.
    public mutating func closeCardForm() {
        guard cardForm != nil else { return }
        cardForm = nil
        frontsInUse = nil
        showFiles()
        askForTheFichaDeckAskedToAdd()
    }
}
