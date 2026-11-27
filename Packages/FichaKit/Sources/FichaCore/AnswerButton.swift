/// The review panel's three buttons once a card's lower side shows (ADR
/// 0039): Forgot, which records again, Kind of, which records hard, and Got
/// it, which records good. A new way's first review names them New to me,
/// Kind of and Knew it, which record the same. Each has its rating key, 1, 2
/// and 3, as Anki's keys for those three ratings (`RatingKey`), and Got it
/// takes Space too. No key records easy in the panel, though a review still
/// stores one of Anki's four ratings (ADR 0025). The panel's view keeps the
/// buttons, their names, their look and their shortcuts; this map is here so
/// it's tested. Pass and fail grading is FSRS's, and Hard Anki's; the names,
/// and key 4 left without a rating, are our own.
public enum AnswerButton: CaseIterable, Sendable {
    /// Lucas didn't remember the card.
    case forgot
    /// He remembered it, with effort.
    case kindOf
    /// He remembered it.
    case gotIt

    /// The key a button's label shows, which presses it.
    public enum Key: Sendable, Equatable {
        /// A rating key, by its place on the keyboard (`RatingKey`).
        case digit(Character)
        /// Space, which answers good once the answer shows, as in Anki.
        case space
    }

    /// The rating the button records.
    public var rating: Rating {
        switch self {
        case .forgot: .again
        case .kindOf: .hard
        case .gotIt: .good
        }
    }

    /// The rating key that presses it, "1" to "3", Anki's keys for its
    /// rating, which its shortcut takes. 4, Anki's key for easy, presses
    /// none (ADR 0039).
    public var ratingKey: Character {
        switch self {
        case .forgot: "1"
        case .kindOf: "2"
        case .gotIt: "3"
        }
    }

    /// The key its label shows, which presses it: its rating key, or Space
    /// for Got it, whose rating key, 3, presses it too.
    public var key: Key {
        switch self {
        case .forgot, .kindOf: .digit(ratingKey)
        case .gotIt: .space
        }
    }
}
