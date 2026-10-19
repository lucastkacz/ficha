/// A card in the review panel, and what Lucas does with it.
public enum PanelCard: Sendable, Equatable {
    /// A new card, which the panel shows whole and marked as new: Lucas meets
    /// it in its first view.
    case firstView(Card)
    /// A due card, which the panel shows front first: Lucas flips it and
    /// rates it.
    case review(Card)
    /// A card that isn't due yet, which "See more" brings: Lucas flips it and
    /// rates it like a due card, but only again counts, unless the card came
    /// due by the time he answers.
    case reviewAhead(Card)

    /// The card, however the panel shows it.
    public var card: Card {
        switch self {
        case .firstView(let card), .review(let card), .reviewAhead(let card): card
        }
    }

    /// Whether Lucas reviews the card ahead.
    public var isAhead: Bool {
        switch self {
        case .reviewAhead: true
        case .firstView, .review: false
        }
    }
}
