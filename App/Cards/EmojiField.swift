import AppKit
import SwiftUI

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
