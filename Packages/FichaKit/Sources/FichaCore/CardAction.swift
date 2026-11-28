/// What Lucas can do with the card the review panel shows, besides answering
/// it, in the order its ⋯ menu offers them (ADR 0033): flag it with a note on
/// what to fix, and set it aside. Each keeps its key, M and E, also on a
/// layout of another script (`LetterKey`). The
/// panel's view keeps the menu and the shortcuts, and its state does each;
/// this map is here so it's tested. The ⋯ menu is provisional (ADR 0033).
public enum CardAction: CaseIterable, Sendable {
    /// Flags the card with a note on what to fix.
    case flag
    /// Sets the card aside: it shows up no more until it's put back, in the
    /// Cards window (ADR 0041).
    case setAside

    /// The key that does it, without modifiers.
    public var key: Character {
        switch self {
        case .flag: "m"
        case .setAside: "e"
        }
    }
}
