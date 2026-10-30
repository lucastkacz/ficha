import FichaCore
import Foundation

// A deck's color and emoji (ADR 0024), as a tag's (`TagColorAndEmoji.swift`):
// each optional, kept in the deck's row, which syncs them
// (`SyncedDecks.swift`), and taken by a deck without its own from the
// nearest deck it sits inside (`Deck.shownColor`, `Deck.shownEmoji`). The
// Cards window's deck menu sets them, Default's too, and the sidebar, the bar
// above the card list, the review panel and the menu bar's Prioritize
// submenu show them.

extension Engine {
    /// Gives the deck `deck`, by its whole name, or Default by
    /// `Deck.defaultName`, `color`, one of Finder's seven, or takes its color
    /// away when `color` is nil, so that it shows the nearest one of a deck
    /// it sits inside again. A deck that isn't there is made, as Change Deck
    /// makes one, but no color for a deck with none changes nothing. A name
    /// `makeDeck(named:)` refuses is refused.
    public func setColor(_ color: TagColor?, ofDeck deck: String) throws(EngineError) {
        let deck = try checkedDeckForCards(deck)
        try write { db in
            try changeOwnDecks([deck], in: db) { $0.color = color }
        }
    }

    /// Gives the deck `deck` `emoji`, or takes its emoji away when `emoji` is
    /// nil, as `setColor(_:ofDeck:)` does with a color.
    public func setEmoji(_ emoji: Emoji?, ofDeck deck: String) throws(EngineError) {
        let deck = try checkedDeckForCards(deck)
        try write { db in
            try changeOwnDecks([deck], in: db) { $0.emoji = emoji?.text }
        }
    }
}
