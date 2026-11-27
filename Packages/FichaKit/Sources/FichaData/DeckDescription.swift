import FichaCore
import Foundation

// A deck's description (ADR 0044): one or two lines on what it holds, which
// any deck can have, Default too, kept in the deck's row, which syncs it
// (`SyncedDecks.swift`), as its emoji (`DeckColorAndEmoji.swift`). It's the
// deck's own alone: the decks inside it never take it.

extension Deck {
    /// The most characters a description holds, as the user sees them, a flag
    /// or an accented letter being one (ADR 0044, provisional).
    /// `EngineError.descriptionTooLong`'s message names it.
    public static let longestDescription = 160

    /// `text` as a deck keeps it for its description: without the spaces and
    /// line breaks around it, or nil, for none, when it's nil or blank; or an
    /// error when it's longer than `longestDescription`.
    static func checkedDescription(_ text: String?) throws(EngineError) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard trimmed.count <= longestDescription else {
            throw .descriptionTooLong
        }
        return trimmed
    }
}

extension Engine {
    /// Gives the deck `deck`, by its whole name, or Default by
    /// `Deck.defaultName`, `description`, as `Deck.checkedDescription(_:)`
    /// keeps it, or takes its own away when that's none, as `setEmoji(_:ofDeck:)`
    /// does with an emoji: a deck that isn't there is made, but no
    /// description for a deck with none changes nothing. Refuses a
    /// description longer than `Deck.longestDescription`, and a name
    /// `makeDeck(named:)` refuses.
    public func setDescription(_ description: String?, ofDeck deck: String) throws(EngineError) {
        let deck = try checkedDeckOrDefault(deck)
        let kept = try Deck.checkedDescription(description)
        try write { db in
            try changeOwnDecks([deck], in: db) { $0.description = kept }
        }
    }
}
