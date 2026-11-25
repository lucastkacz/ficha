/// What the review panel's ⋯ menu offers to do with a card (#489): a stub,
/// which its tests fail until the panel has it.
public enum CardAction: CaseIterable, Sendable {
    case ask
    case flag
    case bury

    /// The key that does it.
    public var key: Character {
        " "
    }
}
