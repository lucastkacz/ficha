import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Deletes the cards with these ids for good, as Lucas does in the Cards
    /// window, with their review logs, in one write, or none of them when one
    /// doesn't exist. An expansion attached to one of them, or a follow-up
    /// tied to it, stays in the inbox as a plain capture, so nothing he jotted
    /// down is lost, and the capture a card was approved from stays as it is.
    /// Their images and sounds go too, those no other card uses. Nothing
    /// undoes it. Returns the cards as they were, in the order Lucas approved
    /// them.
    @discardableResult
    public func delete(_ cardIDs: Set<Int64>) throws(EngineError) -> [Card] {
        let deleted = try write { db in
            try cardIDs.sorted().map { try delete($0, in: db) }
        }
        removeFilesNoCardUses(images: Set(deleted.flatMap(\.images)), sounds: Set(deleted.flatMap(\.sounds)))
        return deleted
    }

    /// Deletes the card with this id, with its review log, and returns it as
    /// it was, or throws when it doesn't exist. The captures that expand it or
    /// follow it up let go of it first, as the schema's references to cards
    /// need: one in the inbox becomes a plain capture there, and one already
    /// refined stays out of it.
    private func delete(_ cardID: Int64, in db: Database) throws -> Card {
        let card = try existingCard(cardID, in: db)
        try db.execute(sql: "DELETE FROM reviewLog WHERE cardId = ?", arguments: [cardID])
        try db.execute(sql: "UPDATE capture SET expandsCardId = NULL WHERE expandsCardId = ?", arguments: [cardID])
        try db.execute(
            sql: "UPDATE capture SET followsUpCardId = NULL WHERE followsUpCardId = ?", arguments: [cardID])
        try db.execute(sql: "DELETE FROM card WHERE id = ?", arguments: [cardID])
        return card
    }
}
