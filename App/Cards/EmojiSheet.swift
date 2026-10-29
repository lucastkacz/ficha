import AppKit
import FichaCore
import FichaData
import SwiftUI

/// What the Cards window's emoji sheet or rename sheet asks about: a tag, or
/// a card type of the user's own.
enum SheetSubject: Equatable {
    case tag(CardTag)
    case type(UserType)

    /// Its emoji, its own, or nil when it has none.
    var emoji: String? {
        switch self {
        case .tag(let tag): tag.emoji
        case .type(let type): type.emoji
        }
    }
}

/// The sheet the Cards window opens from Emoji… in the context menu of a tag
/// or of a card type of the user's own, with one field for its emoji, which
/// starts with the one it has. Lucas types an emoji, or picks one from the
/// Mac's Emoji & Symbols, which the button beside the field opens, since
/// Ficha has no menu bar for the Edit menu's. OK gives the tag or the type
/// the emoji, or takes its emoji away when the field is empty, and refuses
/// anything else, which the sheet says under the field. `CardsWindowState`
/// decides what OK takes.
struct EmojiSheet: View {
    let subject: SheetSubject
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
        subject: SheetSubject, failure: Binding<Failure?>, entry: @escaping (String) -> CardsWindowState.EmojiEntry,
        choose: @escaping (String) -> Void
    ) {
        self.subject = subject
        self.failure = failure
        self.entry = entry
        self.choose = choose
        _emoji = State(initialValue: subject.emoji ?? "")
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

    /// The sheet's title, with the tag's or the type's name.
    private var title: Text {
        switch subject {
        case .tag(let tag):
            Text(
                "Emoji for “\(TagPath.shown(tag.name))”",
                comment: "The title of the Cards window's sheet that gives a tag an emoji, with the tag's name.")
        case .type(let type):
            Text(
                "Emoji for the type “\(type.name)”",
                comment:
                    "The title of the Cards window's sheet that gives a card type of the user's own an emoji, with the type's name."
            )
        }
    }

    /// What the sheet says under its title.
    private var explanation: Text {
        switch subject {
        case .tag:
            Text(
                "It shows before the tag's name. Leave the field empty for none.",
                comment: "Under the title of the Cards window's sheet that gives a tag an emoji.")
        case .type:
            Text(
                "It shows before the type's name. Leave the field empty for none.",
                comment:
                    "Under the title of the Cards window's sheet that gives a card type of the user's own an emoji.")
        }
    }

    /// Why OK refuses what the field holds, while it does.
    private var refusal: EngineError? {
        guard case .refused(let error) = entry(emoji) else { return nil }
        return error
    }

    /// Gives the tag or the type the field's emoji, or takes its emoji away,
    /// unless OK refuses it.
    private func submit() {
        guard refusal == nil else { return }
        choose(emoji)
    }
}

/// The field for an emoji, in the emoji sheet and the New Type sheet, empty
/// for none, with the button beside it that opens the Mac's Emoji & Symbols.
/// Return in it submits the sheet.
struct EmojiField: View {
    @Binding var emoji: String
    var isFocused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        HStack {
            TextField(
                String(localized: "Emoji", comment: "The field of the sheet that gives a tag or a card type an emoji."),
                text: $emoji,
                prompt: Text("None", comment: "The empty field of the sheet that gives a tag or a card type an emoji.")
            )
            .textFieldStyle(.roundedBorder)
            .focused(isFocused)
            // A focused text field keeps Return from reaching the default
            // button.
            .onSubmit(submit)
            Button {
                isFocused.wrappedValue = true
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
    }
}
