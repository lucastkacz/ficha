import FichaCore
import Foundation

// The Cards window's Ficha's Decks (#458): a sidebar section after Decks
// lists the decks of Ficha's the user hasn't added (`FichaDecks.swift`), each
// with its emoji, name and how many cards it holds, until all are added.
// Choosing one shows it in the table's and the detail's place: its emoji,
// name and "40 cards · one of Ficha's decks", its first card, front and
// back, and Add Deck…, which asks How fast? for it before it comes in
// (`HowFast.swift`). Start adds it, sets the pace and its place, and the
// sidebar then chooses the deck in Decks.

extension CardsWindowState {
    /// Takes Ficha's decks as the app read them from its bundle
    /// (`Engine.readFichaDeck(_:at:)`), which the sidebar's Ficha's Decks
    /// section, after Decks, lists while the user hasn't added them, in
    /// `FichaDeck`'s order, and leaves out once all are. Not worked out yet
    /// (#458): it takes none.
    public mutating func offerFichaDecks(_ files: [FichaDeckFile]) {}

    /// The one of Ficha's decks the sidebar chose, as its file holds it,
    /// which the window shows in the table's and the detail's place, with its
    /// first card's front image among the images it shows (`images`): nil
    /// while the sidebar chose something else. Not worked out yet (#458):
    /// nil.
    public var shownFichaDeck: FichaDeckFile? {
        nil
    }

    /// Asks How fast? for the one of Ficha's decks the sidebar chose, after
    /// its Add Deck…: before it comes in, with its cards counted as if they
    /// came in now, last. Its Start adds the deck, sets the pace and its
    /// place, and the sidebar then chooses the deck in Decks. Not worked out
    /// yet (#458): it asks nothing.
    public mutating func askToAddFichaDeck() {}
}
