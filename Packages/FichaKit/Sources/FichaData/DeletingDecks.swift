import FichaCore
import Foundation
internal import GRDB

// Deleting a deck (ADR 0024), as Anki deletes one: the deck goes with every
// deck inside it and every card that lives in them, buried ones too, each as
// deleting a card deletes it (`Deleting.swift`), with its review log, while
// its expansions and follow-ups stay in the inbox as plain captures; and
// their rows go, with what they had of their own. Default is never deleted.
// The deletion reaches every device as a change to the deck
// (`DeckChanges.swift`), which names the cards it deleted: each deletes them
// there, whether or not they sync, as Lucas decided on 2026-10-31, and of
// the other cards in it there, such as one this device never held, deletes
// those that sync and moves those that don't to Default. Nothing undoes it,
// but the daily backups keep what it deleted.

/// What deleting a deck does on this device, as Delete…'s question says it
/// before, and the `ficha` CLI prints it after.
public struct DeckDeletion: Sendable, Equatable, Encodable {
    /// The deck deleted, by its whole name.
    public let deck: String
    /// The decks inside it that go with it, as this device lists them, in
    /// the order a tree lists them.
    public let decksInside: [String]
    /// How many cards on this device live in it or in a deck inside it,
    /// buried ones too, each of which is deleted, here and on every device.
    public let cards: Int
}

extension Engine {
    /// What deleting the deck `deck` would do on this device now, as Delete…
    /// asks before it deletes it. Refuses Default, and a deck that isn't
    /// there.
    public func deletion(ofDeck deck: String) throws(EngineError) -> DeckDeletion {
        try read { db in
            try checkDeckToChange(deck, in: db)
            return try DeckDeletion(of: deck, in: db)
        }
    }

    /// Deletes the deck `deck`, with every deck inside it and every card that
    /// lives in them, in one write, as the file's header says, and then their
    /// images and sounds that no other card uses. The deletion reaches the
    /// user's other devices as a change to the deck. Returns what it did.
    /// Refuses Default, and a deck that isn't there, deleting nothing.
    @discardableResult
    public func deleteDeck(_ deck: String) throws(EngineError) -> DeckDeletion {
        let (deletion, deleted) = try write { db in
            try checkDeckToChange(deck, in: db)
            let deletion = try DeckDeletion(of: deck, in: db)
            // The cards first, while the rows still say whether each syncs,
            // which decides whether its deletion is sent. The change names
            // them all, those that don't sync first, whose deletions reach
            // no other device otherwise, should there be more than it holds.
            let whatSyncs = try WhatSyncs(in: db)
            let cards = try cardsLiving(within: deck, in: db)
            let deleted = try cards.map { try deleteCard($0.id, in: db) }
            try deleteRows(ofDeck: deck, in: db)
            let named =
                cards.filter { !whatSyncs.cardSyncs(inDeck: $0.deck) }
                + cards.filter { whatSyncs.cardSyncs(inDeck: $0.deck) }
            try recordDeckChange(.deletion(deck), deletedCards: named.map(\.uuid), in: db)
            return (deletion, deleted)
        }
        removeFilesNoCardUses(images: Set(deleted.flatMap(\.images)), sounds: Set(deleted.flatMap(\.sounds)))
        return deletion
    }
}

extension DeckDeletion {
    /// What deleting the deck `deck` does in `db` now.
    fileprivate init(of deck: String, in db: Database) throws {
        self.deck = deck
        let own = try OwnDecks(in: db)
        decksInside = try listedDeckNames(of: own, livedInBy: allCards(in: db), in: db).filter { name in
            name != deck && TagPath.isTag(name, within: deck)
        }
        cards = try cardsLiving(within: deck, in: db).count
    }
}
