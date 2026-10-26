import FichaCore

/// A card in the review panel, the way it shows, and what Lucas does with it.
/// A card shows front first unless it's said to show back first, as the panel
/// marks only back first.
public enum PanelCard: Sendable, Equatable {
    /// A new way of a card, which the panel shows whole and marked as new:
    /// Lucas meets it in its first view.
    case firstView(Card, Way = .frontFirst)
    /// A due way of a card: Lucas flips it and rates it.
    case review(Card, Way = .frontFirst)
    /// A way of a card that isn't due yet, which "See more" brings: Lucas
    /// flips it and rates it like a due one, but only again counts, unless
    /// it came due by the time he answers.
    case reviewAhead(Card, Way = .frontFirst)

    /// The card, however the panel shows it.
    public var card: Card {
        switch self {
        case .firstView(let card, _), .review(let card, _), .reviewAhead(let card, _): card
        }
    }

    /// The way the panel shows the card.
    public var way: Way {
        switch self {
        case .firstView(_, let way), .review(_, let way), .reviewAhead(_, let way): way
        }
    }

    /// The card, by id, and the way the panel shows it.
    var cardWay: CardWay {
        CardWay(cardID: card.id, way: way)
    }

    /// Whether Lucas reviews the card ahead.
    public var isAhead: Bool {
        switch self {
        case .reviewAhead: true
        case .firstView, .review: false
        }
    }
}

extension Way {
    /// The side the review panel shows on top, which Lucas sees first: the
    /// front front first, and the back back first.
    public var upperSide: CardSide {
        switch self {
        case .frontFirst: .front
        case .backFirst: .back
        }
    }

    /// The side the review panel shows under the upper one once Lucas flips
    /// the card: the other side.
    public var lowerSide: CardSide {
        switch self {
        case .frontFirst: .back
        case .backFirst: .front
        }
    }
}
