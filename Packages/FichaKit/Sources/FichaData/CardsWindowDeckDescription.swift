import Foundation

// A deck's description in the Cards window (ADR 0044, #557): it shows above
// the deck's cards, and Description…, among the deck's actions, edits it in
// place, one or two lines, as Emoji… gives the deck its emoji
// (`CardsWindowDecks.swift`), through `Engine.setDescription(_:ofDeck:)`.
//
// Stub for #557: the code round replaces it.

extension CardsWindowState {
    /// The deck whose description Description… edits in place, as the window
    /// last read it, whose field starts with the deck's own description: nil
    /// while it edits none. Stub for #557: it's always nil.
    public var describedDeck: Deck? {
        // Stub for #557: the code round replaces it.
        nil
    }

    /// Chooses Description… in the menu of the deck `deck`, by its whole name,
    /// or Default's by `Deck.defaultName`, while the sidebar lists it: its
    /// description shows as a field, in place, which `describedDeck` says.
    /// Stub for #557: it does nothing.
    public mutating func askForDescription(onDeck deck: String) {
        // Stub for #557: the code round replaces it.
    }

    /// Chooses Done in the field of the deck Description… edits, which holds
    /// `text`: gives the deck that description, without the spaces and line
    /// breaks around it, or takes its own away when `text` is blank, as
    /// `Engine.setDescription(_:ofDeck:)` does, ends the edit and reads the
    /// cards again; or records why it couldn't and goes on with the edit.
    /// Stub for #557: it does nothing.
    public mutating func chooseDescription(_ text: String) {
        // Stub for #557: the code round replaces it.
    }
}
