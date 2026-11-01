import FichaCore
import Foundation

extension Rating {
    /// The rating, as the review panel's buttons and the Cards window's
    /// review log name it: Anki's names for its four buttons, in each
    /// language Anki's own.
    var name: String {
        switch self {
        case .again:
            String(
                localized: "Again",
                comment: """
                    A rating, Anki's first button, as the review panel's button names it and the Cards window's \
                    review log shows it: Lucas didn't know the card. Anki's own name for it, “Otra vez” in Spanish.
                    """)
        case .hard:
            String(
                localized: "Hard",
                comment: """
                    A rating, Anki's second button, as the review panel's button names it and the Cards window's \
                    review log shows it: Lucas knew the card with effort. Anki's own name for it, “Difícil” in \
                    Spanish.
                    """)
        case .good:
            String(
                localized: "Good",
                comment: """
                    A rating, Anki's third button, as the review panel's button names it and the Cards window's \
                    review log shows it: Lucas knew the card. Anki's own name for it, “Bien” in Spanish.
                    """)
        case .easy:
            String(
                localized: "Easy",
                comment: """
                    A rating, Anki's fourth button, as the review panel's button names it and the Cards window's \
                    review log shows it: Lucas knew the card at once. Anki's own name for it, “Fácil” in Spanish.
                    """)
        }
    }
}
