/// What waits in the inbox to be refined: Lucas's captures, the expansions of
/// his cards, and the cards he flagged. The `ficha` CLI prints it as JSON.
public struct Inbox: Sendable, Encodable {
    /// The captures that expand no card, oldest first.
    public let captures: [Capture]
    /// The captures Lucas chose to expand a card with, each with its card,
    /// oldest first.
    public let expansions: [Expansion]
    /// The flagged cards, each with Lucas's note on what to fix, the first
    /// flagged first.
    public let flaggedCards: [Card]
}

/// A capture that repeats a card's front, which Lucas chose to expand: it
/// waits in the inbox for refining to add it to that card.
public struct Expansion: Sendable, Equatable, Encodable {
    public let capture: Capture
    /// The card it expands, as it is now.
    public let card: Card
}
