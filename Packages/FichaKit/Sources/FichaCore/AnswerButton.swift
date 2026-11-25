/// The review panel's two buttons once a card's lower side shows (#489): a
/// stub, which its tests fail until the panel has them.
public enum AnswerButton: CaseIterable, Sendable {
    case forgot
    case gotIt

    /// The key a button's label shows.
    public enum Key: Sendable, Equatable {
        case digit(Character)
        case space
    }

    /// The rating the button records.
    public var rating: Rating {
        .hard
    }

    /// The key its label shows.
    public var key: Key {
        .digit("2")
    }
}
