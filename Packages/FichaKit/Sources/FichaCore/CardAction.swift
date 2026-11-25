/// What Lucas can do with the card the review panel shows, besides answering
/// it, in the order its ⋯ menu offers them (ADR 0033): ask a question about
/// it, flag it with a note on what to fix, and bury it. Each keeps its key,
/// A, M and E, also on a layout of another script (`LetterKey`). The panel's
/// view keeps the menu and the shortcuts, and its state does each; this map
/// is here so it's tested. The ⋯ menu is provisional (ADR 0033).
public enum CardAction: CaseIterable, Sendable {
    /// Asks a question about the card, which waits in the inbox as a
    /// follow-up.
    case ask
    /// Flags the card with a note on what to fix.
    case flag
    /// Buries the card: it never shows up again.
    case bury

    /// The key that does it, without modifiers.
    public var key: Character {
        switch self {
        case .ask: "a"
        case .flag: "m"
        case .bury: "e"
        }
    }
}
