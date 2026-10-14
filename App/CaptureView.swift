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
                "Texto",
                text: $text,
                prompt: Text("Una palabra, un concepto, una frase o una pregunta"),
                axis: .vertical
            )
            .lineLimit(3...8)
            .focused($textIsFocused)
            TextField("Nota", text: $note, prompt: Text("Nota (opcional)"), axis: .vertical)
                .lineLimit(1...4)
            TextField("Fuente", text: $source, prompt: Text("Fuente (opcional): un libro, un podcast…"))
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Guardar", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(textIsBlank)
            }
        }
        .textFieldStyle(.roundedBorder)
        // A focused text field keeps Return from reaching the default button.
        .onSubmit(save)
        .padding()
        .frame(width: 420)
        .defaultFocus($textIsFocused, true)
        .alert(
            "No se pudo guardar la captura",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { _ in
            Button("Aceptar") {}
        } message: { failure in
            Text(failure.localizedDescription)
        }
    }

    /// Whether there's no text to save yet, so "Guardar" waits for it.
    private var textIsBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard !textIsBlank else { return }
        do {
            try model.capture(text: text, note: note, source: source)
            dismiss()
        } catch {
            failure = error
        }
    }
}
