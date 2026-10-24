/// What waits in the inbox to be refined: Lucas's captures, the expansions of
/// his cards, his follow-ups on them, and the cards he flagged. The `ficha`
/// CLI prints it as JSON.
public struct Inbox: Sendable, Encodable {
    /// The captures that expand no card and follow none up, oldest first.
    public let captures: [Capture]
    /// The captures Lucas chose to expand a card with, each with its card,
    /// oldest first.
    public let expansions: [Expansion]
    /// The captures Lucas asked about a card in the review panel, each with
    /// its card, oldest first.
    public let followUps: [FollowUp]
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

/// A capture Lucas jotted down in the review panel about the card in front of
/// him, such as a question it raised: it waits in the inbox, tied to that
/// card, for refining to turn it into new cards beside it, and leaves the
/// card as it is.
public struct FollowUp: Sendable, Equatable, Encodable {
    public let capture: Capture
    /// The card it follows up, as it is now.
    public let card: Card
}
