import FichaCore
import FichaData
import SwiftUI

/// The pop-up of a card's deck, its Deck field, in the card form and in the
/// card editor, and of the deck every card comes into, in the Import sheet:
/// each deck the window offers, Default first, then the others in the order
/// a tree lists them, each by its whole name, as “Idiomas › Inglés”, and last
/// New Deck…, which asks for a new deck's name, in the New Deck sheet or in
/// the Import sheet's preview's place, and leaves the deck as it was until
/// one is named. `label` names it for VoiceOver, since the label beside it is
/// a view of its own.
struct DeckPicker: View {
    /// The deck it holds, by its whole name, or Default's.
    let deck: String
    /// The decks it offers, as `CardsWindowState.deckFieldChoices(_:)` or
    /// `CardsWindowState.importDeckChoices` lists them.
    let decks: [Deck]
    let label: Text
    /// Picks a deck, by its whole name, or Default's.
    let choose: (String) -> Void
    /// New Deck….
    let newDeck: () -> Void

    var body: some View {
        Picker(selection: choice) {
            ForEach(decks, id: \.name) { deck in
                Text(verbatim: Deck.shownName(deck.name))
                    .tag(Choice.deck(deck.name))
            }
            Divider()
            Text(
                "New Deck…",
                comment: """
                    The last item of a menu of decks in the Cards window, a card's Deck field or the Import sheet's: it \
                    asks for a new deck's name.
                    """
            )
            .tag(Choice.newDeck)
        } label: {
            label
        }
        .labelsHidden()
        .fixedSize()
    }

    /// An item of the pop-up: a deck, or New Deck….
    private enum Choice: Hashable {
        case deck(String)
        case newDeck
    }

    /// The item the pop-up shows, the card's deck, and what picking one does.
    private var choice: Binding<Choice> {
        Binding {
            .deck(deck)
        } set: { choice in
            switch choice {
            case .deck(let deck): choose(deck)
            case .newDeck: newDeck()
            }
        }
    }
}
