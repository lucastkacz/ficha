import FichaCore
import Foundation

// A deck's description (ADR 0044): one or two lines on what it holds, which
// any deck can have, Default too. The tests of #556 fail on this stub until
// the engine keeps it.

extension Deck {
    /// The most characters a description holds, as the user sees them (ADR
    /// 0044, provisional).
    public static let longestDescription = 160
}

extension Engine {
    /// Gives the deck `deck` `description`: a stub that keeps nothing yet.
    public func setDescription(_ description: String?, ofDeck deck: String) throws(EngineError) {}
}
