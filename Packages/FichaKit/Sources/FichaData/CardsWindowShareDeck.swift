import Foundation

// Share Deck…, among the actions of a deck the user has added (ADR 0044,
// #557): the window writes the deck's `.ficha` (`DeckFile.swift`), named
// after the deck, and the app hands it to macOS's Share menu, through AppKit's
// `NSSharingServicePicker`, whose last item, Save to File…, saves it.
//
// Stub for #557: the code round replaces it.

extension CardsWindowState {
    /// Chooses Share Deck… in the menu of the deck `deck`, by its whole name,
    /// while the sidebar lists it: writes the deck's `.ficha`, named after the
    /// deck, to a temporary folder of its own, and returns the file, which the
    /// app hands to the Share menu; or records why it couldn't, and returns
    /// nil. Stub for #557: it writes nothing, and returns nil.
    public mutating func shareDeck(_ deck: String) -> URL? {
        // Stub for #557: the code round replaces it.
        nil
    }
}
