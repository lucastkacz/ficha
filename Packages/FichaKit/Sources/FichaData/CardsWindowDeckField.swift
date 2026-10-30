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
    /// A Deck field, which takes the deck New Deck… names there.
    public enum DeckField: Sendable, Equatable {
        /// The card form's.
        case form
        /// The editor's, while Lucas edits a card.
        case editor
    }

    /// The decks the Deck field `field` offers, before New Deck…, in the
    /// order a tree lists them: Default first, always, then every deck the
    /// sidebar lists, and the deck the field holds, which New Deck… may have
    /// named, with the decks it sits inside. Empty while the field isn't
    /// there: the card form's while it's closed, and the editor's while
    /// Lucas edits no card.
    public func deckFieldChoices(_ field: DeckField) -> [Deck] {
        guard let held = deck(in: field) else { return [] }
        let listed = Dictionary(decks.map { ($0.deck.name, $0.deck) }, uniquingKeysWith: { first, _ in first })
        let named = TagPath.lineages(of: [held] + listed.keys).subtracting([Deck.defaultName])
        return ([Deck.defaultName] + TagPath.sortedAsTree(named)).map { listed[$0] ?? Deck(name: $0) }
    }

    /// Moves the card Lucas edits to the deck `deck`, by its whole name, or
    /// to Default, as Save will, while he edits one.
    public mutating func setDeckInEditor(_ deck: String) {
        guard case .card = editing else { return }
        editedDeck = deck
    }

    /// Asks for a new deck's whole name, in the New Deck sheet, after New
    /// Deck… in the Deck field `field`, while it's there: the card form's,
    /// while it's open, or the editor's, while Lucas edits a card.
    public mutating func askForNewDeck(in field: DeckField) {
        guard deck(in: field) != nil else { return }
        question = .newDeck(field)
    }

    /// Puts the deck `deck`, which New Deck… named, in the Deck field
    /// `field`, while it's there.
    mutating func putInDeckField(_ deck: String, _ field: DeckField) {
        switch field {
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
        return decks.contains { $0.deck.name == lastDeckAddedTo } ? lastDeckAddedTo : Deck.defaultName
    }

    /// The deck the Deck field `field` holds, or nil while it isn't there.
    private func deck(in field: DeckField) -> String? {
        switch field {
        case .form:
            return cardForm?.draft.deck
        case .editor:
            guard case .card = editing else { return nil }
            return editedDeck
        }
    }
}
