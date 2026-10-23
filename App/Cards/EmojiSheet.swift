import AppKit
import FichaData
import SwiftUI

/// The sheet the Cards window opens from Emoji… in a tag's context menu,
/// with one field for the tag's emoji, which starts with the one it has.
/// Lucas types an emoji, or picks one from the Mac's Emoji & Symbols, which
/// the button beside the field opens, since Ficha has no menu bar for the
/// Edit menu's. OK gives the tag the emoji, or takes its emoji away when the
/// field is empty, and refuses anything else, which the sheet says under the
/// field. `CardsWindowState` decides what OK takes.
struct EmojiSheet: View {
    let tag: CardTag
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
        tag: CardTag, failure: Binding<Failure?>, entry: @escaping (String) -> CardsWindowState.EmojiEntry,
        choose: @escaping (String) -> Void
    ) {
        self.tag = tag
        self.failure = failure
        self.entry = entry
        self.choose = choose
        _emoji = State(initialValue: tag.emoji ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Emoji for “\(tag.name)”",
                    comment: "The title of the Cards window's sheet that gives a tag an emoji, with the tag's name."
                )
                .font(.headline)
                Text(
                    "It shows before the tag's name. Leave the field empty for none.",
                    comment: "Under the title of the Cards window's sheet that gives a tag an emoji."
                )
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField(
                    String(localized: "Emoji", comment: "The field of the sheet that gives a tag an emoji."),
                    text: $emoji,
                    prompt: Text("None", comment: "The empty field of the sheet that gives a tag an emoji.")
                )
                .textFieldStyle(.roundedBorder)
                .focused($fieldIsFocused)
                // A focused text field keeps Return from reaching the default
                // button.
                .onSubmit(submit)
                Button {
                    fieldIsFocused = true
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Label {
                        Text(
                            "Emoji & Symbols",
                            comment: "A button beside the emoji field: it opens the Mac's emoji picker.")
                    } icon: {
                        Image(systemName: "face.smiling")
                    }
                    .labelStyle(.iconOnly)
                }
                .help(
                    Text(
                        "Emoji & Symbols (⌃⌘Space)",
                        comment: "The tooltip of the button beside the emoji field that opens the Mac's emoji picker."))
            }
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

    /// Why OK refuses what the field holds, while it does.
    private var refusal: EngineError? {
        guard case .refused(let error) = entry(emoji) else { return nil }
        return error
    }

    /// Gives the tag the field's emoji, or takes its emoji away, unless OK
    /// refuses it.
    private func submit() {
        guard refusal == nil else { return }
        choose(emoji)
    }
}
