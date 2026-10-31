import FichaCore
import Foundation

// The Deck field (ADR 0024), in the Cards window's card form and in its
// editor, which says the deck a card lives in. It offers Default and every
// deck the sidebar lists, as a tree, then New Deck…, which names a deck in
// the New Deck sheet for the field to hold, and Add or Save makes it. A new
// card's form starts in the deck the sidebar chose, or else the deck Lucas
// last added a card to, as Anki's Add window does, which each device
// remembers on its own, as a preference the app keeps; a follow-up's form
// starts in its card's deck. The editor starts in the card's own deck, and
// Save moves the card to the one the field holds, as Change Deck does.

extension CardsWindowState {
    /// The decks the Deck field of the fields `fields` offers, before New
    /// Deck…, in the order a tree lists them: Default first, always, then
    /// every deck the sidebar lists, and the deck the field holds, which New
    /// Deck… may have named, with the decks it sits inside, as the Change
    /// Deck sheet's tree lists them (`decksToChoose(adding:)`). Empty while
    /// the field isn't there: the card form's while it's closed, and the
    /// editor's while Lucas edits no card.
    public func deckFieldChoices(_ fields: CardFields) -> [Deck] {
        guard let held = deck(in: fields) else { return [] }
        return decksToPick(holding: held)
    }

    /// Moves the card Lucas edits to the deck `deck`, by its whole name, or
    /// to Default, as Save will, while he edits one.
    public mutating func setDeckInEditor(_ deck: String) {
        guard case .card = editing else { return }
        editedDeck = deck
    }

    /// Asks for a new deck's whole name, in the New Deck sheet, after New
    /// Deck… in the Deck field of the fields `fields`, while they're there:
    /// the card form's, while it's open, or the editor's, while Lucas edits a
    /// card.
    public mutating func askForNewDeck(in fields: CardFields) {
        guard areOpen(fields) else { return }
        question = .newDeck(fields)
    }

    /// Puts the deck `deck`, which New Deck… named, in the Deck field of the
    /// fields `fields`, while they're there.
    mutating func putInDeckField(_ deck: String, _ fields: CardFields) {
        switch fields {
        case .form: cardForm?.draft.deck = deck
        case .editor: setDeckInEditor(deck)
        }
    }

    /// The deck a new card's form starts in: the deck the sidebar chose, or
    /// else the deck Lucas last added a card to, while the sidebar lists it,
    /// or else Default.
    var deckANewCardStartsIn: String {
        if case .cards(.deck(let deck)) = sidebarItem {
            return deck
        }
        return listedDeck(lastDeckAddedTo) != nil ? lastDeckAddedTo : Deck.defaultName
    }

    /// The deck the Deck field of the fields `fields` holds, or nil while
    /// they aren't there.
    private func deck(in fields: CardFields) -> String? {
        guard areOpen(fields) else { return nil }
        switch fields {
        case .form: return cardForm?.draft.deck
        case .editor: return editedDeck
        }
    }
}
