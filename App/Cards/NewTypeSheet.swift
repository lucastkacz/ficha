import FichaCore
import FichaData
import SwiftUI

/// The sheet New Type… in a card's type picker opens, in the card form or
/// the editor, with a field for the new type's name and one for its emoji,
/// which can stay empty. OK makes the type, which the picker then shows. It
/// stays off while the name is blank, and refuses a name of one of the four
/// types Ficha comes with, or another type's, and anything in the emoji
/// field but one emoji, which the sheet says under the fields.
/// `CardsWindowState` decides what OK takes.
struct NewTypeSheet: View {
    /// What couldn't be saved, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    /// What OK makes of what the name field and the emoji field hold, or nil
    /// while the window asks for no new type.
    let entry: (_ name: String, _ emoji: String) -> CardsWindowState.NewTypeEntry?
    /// OK, with what the name field and the emoji field hold.
    let choose: (_ name: String, _ emoji: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = ""
    @FocusState private var isNameFocused: Bool
    @FocusState private var isEmojiFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "New Type",
                    comment: "The title of the Cards window's sheet that makes a card type of the user's own."
                )
                .font(.headline)
                Text(
                    "Its emoji shows before its name. Leave the emoji empty for none.",
                    comment: "Under the title of the Cards window's sheet that makes a card type of the user's own."
                )
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField(
                String(
                    localized: "Name",
                    comment: "The field of the sheet that makes a card type of the user's own: its name."
                ),
                text: $name
            )
            .textFieldStyle(.roundedBorder)
            .focused($isNameFocused)
            // A focused text field keeps Return from reaching the default
            // button.
            .onSubmit(submit)
            EmojiField(emoji: $emoji, isFocused: $isEmojiFocused, submit: submit)
            if case .refused(let error)? = entry(name, emoji) {
                Text(error.localizedDescription)
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
                .disabled(!canChoose)
            }
        }
        .padding(20)
        .frame(width: 340)
        // Once the sheet is up, after the update that showed it: a field of
        // the window that takes the focus in that update, as the editor's
        // does as it opens, would take it from the sheet otherwise.
        .task {
            isNameFocused = true
        }
        .failureAlert(failure)
    }

    /// Whether OK takes what the fields hold.
    private var canChoose: Bool {
        guard case .type? = entry(name, emoji) else { return false }
        return true
    }

    /// Makes the type, unless OK doesn't take what the fields hold.
    private func submit() {
        guard canChoose else { return }
        choose(name, emoji)
    }
}
