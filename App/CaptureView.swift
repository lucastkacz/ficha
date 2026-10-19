import FichaCore
import FichaData
import SwiftUI

/// The small window where Lucas jots down a capture: its text, plus a note and
/// a source if he wants. Enter saves it to the inbox, Option-Enter starts a new
/// line, and Esc closes the window. A capture that repeats a card or a capture
/// asks him first whether to expand it or ignore it.
struct CaptureView: View {
    let model: AppModel
    /// Closes the window.
    let dismiss: () -> Void
    @State private var text = ""
    @State private var note = ""
    @State private var source = ""
    @State private var failure: Failure?
    /// What the capture repeats, while the window asks Lucas what to do with
    /// the duplicate.
    @State private var repeated: Repeated?
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
        .failureAlert($failure)
        .alert(
            repeated.map { warning(about: $0).title } ?? Text(verbatim: ""),
            isPresented: Binding(get: { repeated != nil }, set: { if !$0 { repeated = nil } }),
            presenting: repeated
        ) { _ in
            Button(action: expand) {
                Text(
                    "Expand",
                    comment: """
                        A button that keeps a capture that repeats a card or a capture, to add to that card or \
                        capture when Lucas refines.
                        """)
            }
            .keyboardShortcut(.defaultAction)
            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Ignore", comment: "A button that drops a capture that repeats a card or a capture.")
            }
        } message: { repeated in
            warning(about: repeated).message
        }
    }

    /// What the window says about a duplicate: what it repeats, and what
    /// "Expand" and "Ignore" do with it.
    private func warning(about repeated: Repeated) -> (title: Text, message: Text) {
        switch repeated {
        case .card(let card):
            (
                Text("This repeats a card"),
                Text(
                    """
                    Card: “\(card.front)”

                    Expand keeps your capture in the inbox, attached to that card, so that refining adds it to the \
                    card. Ignore drops it.
                    """
                )
            )
        case .capture(let capture):
            (
                Text("This is already in the inbox"),
                Text(
                    """
                    Capture: “\(capture.text)”

                    Expand keeps yours next to it, so that refining takes both together. Ignore drops yours.
                    """
                )
            )
        }
    }

    /// Whether the fields hold a capture yet, by the same rule the engine
    /// saves it with: until there's text, "Save" and Enter wait for it.
    private var fieldsMakeACapture: Bool {
        CaptureContent(text: text, note: note, source: source) != nil
    }

    private func save() {
        guard fieldsMakeACapture else { return }
        do {
            switch try model.capture(text: text, note: note, source: source) {
            case .saved:
                dismiss()
            case .duplicate(let original):
                repeated = original
            }
        } catch {
            failure = Failure(title: "Couldn't save the capture", error: error)
        }
    }

    /// Saves the capture Lucas chose to expand.
    private func expand() {
        do {
            try model.expand(text: text, note: note, source: source)
            dismiss()
        } catch {
            failure = Failure(title: "Couldn't save the capture", error: error)
        }
    }
}
