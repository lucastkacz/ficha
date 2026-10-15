import FichaCore
import FichaData
import SwiftUI

/// The small window where Lucas jots down a capture: its text, plus a note and
/// a source if he wants. Enter saves it to the inbox, Option-Enter starts a new
/// line, and Esc closes the window.
struct CaptureView: View {
    static let windowID = "capture"

    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var note = ""
    @State private var source = ""
    @State private var failure: EngineError?
    @FocusState private var textIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "Text",
                text: $text,
                prompt: Text("A word, a concept, a quote or a question"),
                axis: .vertical
            )
            .lineLimit(3...8)
            .focused($textIsFocused)
            TextField("Note", text: $note, prompt: Text("Note (optional)"), axis: .vertical)
                .lineLimit(1...4)
            TextField("Source", text: $source, prompt: Text("Source (optional): a book, a podcast…"))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!fieldsMakeACapture)
            }
        }
        .textFieldStyle(.roundedBorder)
        // A focused text field keeps Return from reaching the default button.
        .onSubmit(save)
        .padding()
        .frame(width: 420)
        .defaultFocus($textIsFocused, true)
        .failureAlert("Couldn't save the capture", failure: $failure)
    }

    /// Whether the fields hold a capture yet, by the same rule the engine
    /// saves it with: until there's text, "Save" and Enter wait for it.
    private var fieldsMakeACapture: Bool {
        CaptureContent(text: text, note: note, source: source) != nil
    }

    private func save() {
        guard fieldsMakeACapture else { return }
        do {
            try model.capture(text: text, note: note, source: source)
            dismiss()
        } catch {
            failure = error
        }
    }
}
