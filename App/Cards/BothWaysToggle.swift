import SwiftUI

/// The Both ways checkbox of a card, in the card form and in the card
/// editor, with what it does under it, so that a word that says little on
/// its own still reads.
struct BothWaysToggle: View {
    @Binding var bothWays: Bool

    /// The label of its row in the form and in the editor. A key of its own,
    /// since the review panel's title says "Review" too, which a translation
    /// may word apart.
    static var label: Text {
        Text(
            String(
                localized: "both-ways.label", defaultValue: "Review",
                comment: "In the Cards window's card form and card editor, the label of the Both ways checkbox's row."))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $bothWays) {
                Text(
                    "Both ways",
                    comment: """
                        In the Cards window, the checkbox of a card that is also reviewed back first: its back, then its \
                        front.
                        """)
            }
            .toggleStyle(.checkbox)
            Text(
                "Also review it back first: its back, then its front once you flip it.",
                comment: "In the Cards window, under a card's Both ways checkbox."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
