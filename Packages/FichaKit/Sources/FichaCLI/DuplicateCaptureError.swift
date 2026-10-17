import FichaData
import Foundation

/// A capture `ficha capture` didn't save because it repeats a card or a
/// capture in the inbox. Its message says what it repeats and how to expand
/// or ignore it.
struct DuplicateCaptureError: LocalizedError {
    /// The capture's text, as it was typed.
    let text: String
    /// What it repeats.
    let repeated: Repeated

    var errorDescription: String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch repeated {
        case .card(let card):
            """
            “\(text)” repeats card \(card.id), “\(card.front)”, so it wasn't saved. To add it to that \
            card when you refine, capture it again with --expand; to ignore it, do nothing.
            """
        case .capture(let capture):
            """
            “\(text)” repeats capture \(capture.id) in the inbox, “\(capture.text)”, so it wasn't saved. To keep it \
            next to that capture and refine them together, capture it again with --expand; to ignore it, do nothing.
            """
        }
    }
}
