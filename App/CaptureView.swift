import FichaCore
import FichaData
import SwiftUI

/// The small window where Lucas jots down a capture: its text, plus a note and
/// a source if he wants. Enter saves it to the inbox, Option-Enter starts a new
/// line, and Esc closes the window. A capture that repeats a card or a capture
/// asks him first whether to expand it or ignore it.
struct CaptureView: View {
    static let windowID = "capture"

    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var note = ""
    @State private var source = ""
    @State private var failure: Failure?
    /// What the capture repeats, while the window asks Lucas what to do.
    @State private var duplicate: Duplicate?
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
            duplicateTitle,
            isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
            presenting: duplicate
        ) { _ in
            Button("Expand", action: expand)
                .keyboardShortcut(.defaultAction)
            Button("Ignore", role: .cancel) {
                dismiss()
            }
        } message: { duplicate in
            switch duplicate {
            case .card(let card):
                Text(
                    """
                    Card: “\(card.front)”

                    Expand keeps your capture in the inbox, attached to that card, so that refining adds it to the \
                    card. Ignore drops it.
                    """
                )
            case .capture(let capture):
                Text(
                    """
                    Capture: “\(capture.text)”

                    Expand keeps yours next to it, so that refining takes both together. Ignore drops yours.
                    """
                )
            }
        }
    }

    /// What heads the question about a duplicate: what the capture repeats.
    private var duplicateTitle: Text {
        switch duplicate {
        case .card: Text("This repeats a card")
        case .capture, nil: Text("This is already in the inbox")
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
            case .duplicate(let repeated):
                duplicate = repeated
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
