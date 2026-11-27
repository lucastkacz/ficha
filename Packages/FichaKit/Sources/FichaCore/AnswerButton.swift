/// The review panel's two buttons once a card's lower side shows (ADR 0033):
/// Forgot, which records again, and Got it, which records good. A new way's
/// first review names them New to me and Knew it, which record the same.
/// Keys 2 and 4 record hard and easy with no button, for whoever comes from
/// Anki, and 3 records good, as before (`RatingKey`), so a review still
/// stores one of Anki's four ratings (ADR 0025). The panel's view keeps the
/// buttons, their names and their shortcuts; this map is here so it's
/// tested. Pass and fail grading is FSRS's; the names, and keys 2 and 4 kept
/// without buttons, are our own.
public enum AnswerButton: CaseIterable, Sendable {
    /// Lucas didn't remember the card.
    case forgot
    /// He remembered it.
    case gotIt

    /// A stub that compiles and fails #517's tests until its code: Kind of,
    /// between Forgot and Got it.
    public static let kindOf = AnswerButton.forgot

    /// A stub that compiles and fails #517's tests until its code: the button
    /// the rating key `digit` presses.
    public init?(ratingKey digit: Character) {
        return nil
    }

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
        case .gotIt: .good
        }
    }

    /// The key its label shows, which presses it: Forgot's rating key, 1, and
    /// Space for Got it, whose rating key, 3, records good too.
    public var key: Key {
        switch self {
        case .forgot: .digit(RatingKey.digit(of: rating))
        case .gotIt: .space
        }
    }
}
