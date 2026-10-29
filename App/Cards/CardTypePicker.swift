import FichaCore
import SwiftUI

/// The pop-up of a card's type, in the card form and in the card editor:
/// None, which is no type, then each type the window offers, the four Ficha
/// comes with and then the user's, each with its emoji, and last New Type…,
/// which opens the New Type sheet and leaves the type as it was until the
/// sheet makes one. `label` names it for VoiceOver, since the label beside
/// it is a view of its own.
struct CardTypePicker: View {
    /// The card's type, or nil for None.
    let type: CardType?
    /// The types it offers, as `CardsWindowState.pickerTypes` lists them.
    let types: [CardType]
    let label: Text
    /// Picks a type, or None when it's nil.
    let choose: (CardType?) -> Void
    /// New Type….
    let newType: () -> Void

    var body: some View {
        Picker(selection: choice) {
            // A key of its own, since a tag's Color submenu says "None" too,
            // which a translation may word apart.
            Text(
                String(
                    localized: "card-type.none", defaultValue: "None",
                    comment: "The first item of a card's type picker in the Cards window: no type.")
            )
            .tag(Choice.type(nil))
            Divider()
            ForEach(types, id: \.self) { type in
                Text(verbatim: type.title)
                    .tag(Choice.type(type))
            }
            Divider()
            Text(
                "New Type…",
                comment: "The last item of a card's type picker in the Cards window: it asks for a new type's name."
            )
            .tag(Choice.newType)
        } label: {
            label
        }
        .labelsHidden()
        .fixedSize()
    }

    /// An item of the pop-up: a type, or None, or New Type….
    private enum Choice: Hashable {
        case type(CardType?)
        case newType
    }

    /// The item the pop-up shows, the card's type, and what picking one does.
    private var choice: Binding<Choice> {
        Binding {
            .type(type)
        } set: { choice in
            switch choice {
            case .type(let type): choose(type)
            case .newType: newType()
            }
        }
    }
}
