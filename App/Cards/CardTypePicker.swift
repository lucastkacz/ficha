import FichaCore
import SwiftUI

/// The pop-up of a card's type, in the card form and in the card editor:
/// None, which is no type, then each type. `label` names it for VoiceOver,
/// since the label beside it is a view of its own.
struct CardTypePicker: View {
    @Binding var type: CardType?
    let label: Text

    var body: some View {
        Picker(selection: $type) {
            // A key of its own, since a tag's Color submenu says "None" too,
            // which a translation may word apart.
            Text(
                String(
                    localized: "card-type.none", defaultValue: "None",
                    comment: "The first item of a card's type picker in the Cards window: no type.")
            )
            .tag(CardType?.none)
            Divider()
            ForEach(CardType.allCases, id: \.self) { type in
                Text(type.name)
                    .tag(CardType?.some(type))
            }
        } label: {
            label
        }
        .labelsHidden()
        .fixedSize()
    }
}
