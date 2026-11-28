import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Deletes the cards with these ids for good, as Lucas does in the Cards
    /// window, with their review logs, in one write, or none of them when one
    /// doesn't exist. What the database keeps unread from before ADR 0041 lets
    /// go of them, as `deleteCard(_:in:)` says. Their images and sounds go too,
    /// those no other card uses. Nothing undoes it. Returns the cards as they
    /// were, in the order they came in.
    @discardableResult
    public func delete(_ cardIDs: Set<Int64>) throws(EngineError) -> [Card] {
        let deleted = try write { db in
            try cardIDs.sorted().map { try deleteCard($0, in: db) }
        }
        removeFilesNoCardUses(images: Set(deleted.flatMap(\.images)), sounds: Set(deleted.flatMap(\.sounds)))
        return deleted
    }
}

/// Deletes the card with this id, with its review log, and returns it as it
/// was, or throws when it doesn't exist. The rows the database keeps unread
/// from before ADR 0041 that point to it let go of it first, as the schema's
/// references to cards need, and stay. Its images and sounds stay, for the
/// engine to remove those no card uses once the write is done.
func deleteCard(_ cardID: Int64, in db: Database) throws -> Card {
    let card = try existingCard(cardID, in: db)
    try db.execute(sql: "DELETE FROM reviewLog WHERE cardId = ?", arguments: [cardID])
    try letGoOfCard(cardID, in: db)
    try db.execute(sql: "DELETE FROM card WHERE id = ?", arguments: [cardID])
    return card
}
