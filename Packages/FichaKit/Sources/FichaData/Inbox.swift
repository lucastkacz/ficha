/// What waits in the inbox to be refined: Lucas's captures, and the cards he
/// flagged. The `ficha` CLI prints it as JSON.
public struct Inbox: Sendable, Encodable {
    /// The captures, oldest first.
    public let captures: [Capture]
    /// The flagged cards, each with Lucas's note on what to fix, the first
    /// flagged first.
    public let flaggedCards: [Card]
}
