import FichaCore
import FichaData

/// What the Cards window's emoji sheet or rename sheet asks about: a tag, a
/// deck, or a card type of the user's own.
enum SheetSubject: Equatable {
    case tag(CardTag)
    case deck(Deck)
    case type(UserType)

    /// Its emoji, its own, or nil when it has none.
    var emoji: String? {
        switch self {
        case .tag(let tag): tag.emoji
        case .deck(let deck): deck.emoji
        case .type(let type): type.emoji
        }
    }
}
