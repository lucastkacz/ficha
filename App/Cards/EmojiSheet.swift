import FichaCore
import FichaData
import SwiftUI

/// The sheet the Cards window opens from Emoji… in a deck's menu, with one
/// field for its emoji, which starts with the one it has of its own. Lucas
/// types an emoji, or picks one from the Mac's Emoji & Symbols, which the
/// button beside the field opens, since Ficha has no menu bar for the Edit
/// menu's. OK gives the deck the emoji, or takes its emoji away when the
/// field is empty, and refuses anything else, which the sheet says under the
/// field. `CardsWindowState` decides what OK takes.
struct EmojiSheet: View {
    let deck: Deck
    /// What couldn't be saved, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    /// What OK makes of what the field holds.
    let entry: (String) -> CardsWindowState.EmojiEntry
    /// OK, with what the field holds.
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var emoji: String
    @FocusState private var fieldIsFocused: Bool

    init(
        deck: Deck, failure: Binding<Failure?>, entry: @escaping (String) -> CardsWindowState.EmojiEntry,
        choose: @escaping (String) -> Void
    ) {
        self.deck = deck
        self.failure = failure
        self.entry = entry
        self.choose = choose
        _emoji = State(initialValue: deck.emoji ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.headline)
                explanation
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            EmojiField(emoji: $emoji, isFocused: $fieldIsFocused, submit: submit)
            if let refusal {
                Text(refusal.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("OK") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(refusal != nil)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            fieldIsFocused = true
        }
        .failureAlert(failure)
    }

    /// The sheet's title, with the deck's whole name.
    private var title: Text {
        Text(
            "Emoji for “\(Deck.shownName(deck.name))”",
            comment: "The title of the Cards window's sheet that gives a deck an emoji, with the deck's whole name.")
    }

    /// What the sheet says under its title.
    private var explanation: Text {
        Text(
            """
            It shows before the deck's name, and before the names of the decks inside it that have none. Leave the \
            field empty for none.
            """,
            comment: "Under the title of the Cards window's sheet that gives a deck an emoji.")
    }

    /// Why OK refuses what the field holds, while it does.
    private var refusal: EngineError? {
        guard case .refused(let error) = entry(emoji) else { return nil }
        return error
    }

    /// Gives the deck the field's emoji, or takes its emoji away, unless OK
    /// refuses it.
    private func submit() {
        guard refusal == nil else { return }
        choose(emoji)
    }
}
