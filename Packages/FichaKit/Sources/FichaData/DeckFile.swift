import Foundation

// A deck's file, a `.ficha` (ADR 0044, #554): a zip, through ZIPFoundation
// (ADR 0014), holding the deck's cards as `CardsTextFile` reads them, their
// images and sounds, and `deck.json`, with the deck's emoji and description,
// and never the user's progress. The engine writes a deck as one
// (`Engine.export(_:to:)`), reads one without importing it, and brings it in
// as Add Deck… brings in one of Ficha's decks (`FichaDecks.swift`): what Open
// Deck… and a file opened from Finder do.
//
// Stub for #554: the code round replaces it.

/// A deck's `.ficha`, read without importing it, as `FichaDeckFile` holds one
/// of Ficha's decks: what Open Deck… and a file opened from Finder bring in.
/// Stub for #554: it holds nothing yet.
public struct DeckFile: Sendable, Equatable {
    // Stub for #554: the code round replaces it.
}

extension Engine {
    /// Reads the deck's `.ficha` at `file` without importing it, as
    /// `readFichaDeck(_:at:)` reads one of Ficha's decks: its cards, images
    /// and sounds through the import's preview, and the emoji and the
    /// description its `deck.json` holds. Stub for #554: it reads nothing,
    /// and returns a file that holds nothing.
    public func readDeckFile(at file: URL) async throws(EngineError) -> DeckFile {
        // Stub for #554: the code round replaces it.
        DeckFile()
    }

    /// Adds the deck `file` holds, as `addFichaDeck(_:)` adds one of Ficha's
    /// decks: its cards that repeat none of the user's, which stay as they
    /// are, with their progress, without the tag an import gives a file's
    /// cards after the file's name; and, when the import made the deck, the
    /// emoji and the description its `deck.json` holds, while a deck the user
    /// had keeps its own. Returns what the import did. Stub for #554: it adds
    /// nothing.
    @discardableResult
    public func addDeck(_ file: DeckFile) throws(EngineError) -> ImportOutcome {
        // Stub for #554: the code round replaces it.
        ImportOutcome(added: 0, updated: 0, skipped: 0, copyBeforeImport: nil)
    }
}
