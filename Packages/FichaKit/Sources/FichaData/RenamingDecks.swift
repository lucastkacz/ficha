import FichaCore
import Foundation
internal import GRDB

// Renaming a deck (ADR 0024), which moves it too, as its whole name carries
// the decks it sits inside, as in Anki: the Cards window's Rename… and its
// drops in the sidebar, and the `ficha` CLI. A deck's name is how its cards
// name it and the `deck` table's key, so renaming one moves every card that
// lives in it or in a deck inside it, and moves their rows: an old row is
// deleted and a new one written, which sync as a deck's rows do, and each
// card records a change to its deck, whose latest change wins (ADR 0017).
// The rename is also recorded as a change to the deck, which reaches the
// cards the user's other devices hold that don't sync (`DeckChanges.swift`),
// as a deletion is (`DeletingDecks.swift`).

extension Engine {
    /// Renames the deck `deck` to `newName`, its levels cleaned up as
    /// `makeDeck(named:)` cleans them up, and every deck inside it along with
    /// it, in one write: each card that lives in one moves to its new name,
    /// keeping its step, its review log and its tags, and each row of the
    /// `deck` table moves to the new name with what it has of its own, its
    /// switch, color, emoji and choice to sync, made on this device. Onto a
    /// name that exists, as a row has it, a card lives in it or a deck inside
    /// it exists, the two join, as in Anki: the deck there keeps exactly what
    /// it had of its own, which may be nothing, as the moved deck's row is
    /// dropped; and so for each deck inside the renamed one. The rename
    /// reaches every card on the user's other devices, those that don't sync
    /// too, as a change to the deck. Returns the deck's new name; renaming it
    /// to its own name changes nothing. Refuses renaming Default, or a deck
    /// that isn't there, a name `makeDeck(named:)` refuses, and moving the
    /// deck inside itself or inside a deck inside it.
    @discardableResult
    public func renameDeck(_ deck: String, to newName: String) throws(EngineError) -> String {
        let name = try checkedDeckName(renaming: deck, to: newName)
        try write { db in
            try checkDeckToChange(deck, in: db)
            if name != deck {
                try makeDeckRename(deck, to: name, in: db)
            }
        }
        return name
    }

    /// Moves the deck `deck` inside the deck `parent`, or to the top when
    /// it's nil, as dropping it on a deck in the Cards window's sidebar, or
    /// on the Decks section's title, does: it's renamed `<parent>::<its last
    /// level>`, or its last level at the top, as `renameDeck(_:to:)` renames
    /// it, with every deck inside it, joining a deck of that name if there's
    /// one. Returns its new name, which is its name when it's right inside
    /// `parent` already, or at the top, which changes nothing. Refuses what
    /// `renameDeck(_:to:)` refuses, and moving a deck inside Default, which
    /// no deck sits inside.
    @discardableResult
    public func moveDeck(_ deck: String, into parent: String?) throws(EngineError) -> String {
        guard parent != Deck.defaultName else {
            throw .defaultDeckName(Deck.defaultShownName)
        }
        let level = TagPath.lastLevel(of: deck)
        return try renameDeck(deck, to: parent.map { $0 + TagPath.separator + level } ?? level)
    }
}

/// The name the deck `deck` takes when it's renamed `newName`: `newName` with
/// its levels cleaned up as `checkedDeckName(_:)` cleans them up; or an error
/// when `deck` is Default, which is never renamed, when `checkedDeckName(_:)`
/// refuses `newName`, or when it would put the deck inside itself or inside
/// a deck inside it.
func checkedDeckName(renaming deck: String, to newName: String) throws(EngineError) -> String {
    guard deck != Deck.defaultName else {
        throw .defaultDeckStays
    }
    let name = try checkedDeckName(newName)
    guard name == deck || !TagPath.isTag(name, within: deck) else {
        throw .deckInsideItself(deck)
    }
    return name
}

/// Renames the deck `deck` to `name`, which differs, as the user does on this
/// device, in the write `db`: the rows of it and the decks inside it move,
/// made on this device (`moveRows(ofDeck:to:among:markingMadeHere:in:)`), the
/// cards that live in them move along, and the rename is recorded as a change
/// to the deck, which reaches the user's other devices.
private func makeDeckRename(_ deck: String, to name: String, in db: Database) throws {
    try moveRows(ofDeck: deck, to: name, among: nil, markingMadeHere: true, in: db)
    for card in try cardsLiving(within: deck, in: db) {
        let newDeck = TagPath.renaming(card.deck, from: deck, to: name) ?? card.deck
        _ = try updateCard(card.id, setting: "deck = ?", to: [newDeck], in: db)
    }
    try recordDeckChange(.rename(deck, to: name), in: db)
}
