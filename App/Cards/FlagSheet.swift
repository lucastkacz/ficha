import FichaCore
import FichaData
import SwiftUI

/// The sheet that asks for Lucas's note on what to fix in the card he flags,
/// as the review panel asks for it: Return flags the card, Option-Return
/// starts a new line, and Escape cancels. A blank note can't flag it. The
/// window closes it once the card is flagged. When the card can't be flagged,
/// an alert says why, and the sheet keeps the note.
struct FlagSheet: View {
    let card: Card
    /// What couldn't be saved, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    /// Flags the card with the note.
    let flag: (FlagNote) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Flag “\(card.front)”",
                    comment: "The title of the Cards window's sheet that flags a card, with the card's front."
                )
                .font(.headline)
                Text(
                    "It waits in the inbox, out of your reviews, until it's fixed.",
                    comment: "Under the title of the Cards window's sheet that flags a card."
                )
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField("Note", text: $note, prompt: Text("What needs fixing?"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .focused($noteIsFocused)
                // A focused text field keeps Return from reaching the default
                // button.
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    Text("Flag", comment: "The button that flags the card with the note written above it.")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(FlagNote(note) == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            noteIsFocused = true
        }
        .failureAlert(failure)
    }

    /// Flags the card with the note, unless it's blank.
    private func submit() {
        guard let note = FlagNote(note) else { return }
        flag(note)
    }
}
