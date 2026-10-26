/// Which way the review panel shows a card: front first, as every card goes,
/// or back first, its back on top and its front once Lucas flips it, as a
/// card that goes both ways also does. Each way has its own progress
/// (ADR 0016). The glossary's words are Both ways and Back first: the code
/// avoids "reverse", since the Spanish "reverso" is a card's back. Each raw
/// value is how the review log names it.
public enum Way: String, Sendable, Hashable {
    /// The front on top, and the back once flipped.
    case frontFirst
    /// The back on top, and the front once flipped.
    case backFirst
}

/// One of a card's ways, which the planners pick and the review panel brings:
/// the card, by id, and the way it shows.
public struct CardWay: Sendable, Hashable {
    public let cardID: Int64
    public let way: Way

    public init(cardID: Int64, way: Way) {
        self.cardID = cardID
        self.way = way
    }
}
