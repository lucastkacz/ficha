import Foundation

// Open Deck…, in the Cards window's sidebar beside New Deck…, and a file
// opened from Finder, which the app opens the same way (ADR 0044, #554): the
// window opens a deck's `.ficha` alone (`DeckFile.swift`), reading it away
// from the main actor, and asks How fast? for the deck before it comes in, as
// Add Deck… does for one of Ficha's decks (`CardsWindowFichaDecks.swift`).
//
// Stub for #554: the code round replaces it.

/// Work Open Deck… starts, reading a deck's `.ficha` for How fast?, which the
/// app runs away from the main actor and hands back to the window, as the
/// Import sheet's `ImportWork`. Stub for #554: it holds nothing yet.
public struct OpenDeckWork: Sendable {
    // Stub for #554: the code round replaces it.
}

extension CardsWindowState {
    /// Opens `file`, which the user chose with Open Deck… or opened from
    /// Finder: starts reading it while it's a deck's `.ficha`, and returns
    /// the work, which the app runs away from the main actor, and after which
    /// How fast? asks for the deck; or refuses it at once, while it's anything
    /// else, recording an error that says Ficha opens a deck's `.ficha` file,
    /// and returns nil. Stub for #554: it opens and refuses nothing, and
    /// returns nil.
    public mutating func openDeck(_ file: URL) -> OpenDeckWork? {
        // Stub for #554: the code round replaces it.
        nil
    }
}
