import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Flags a card with Lucas's note on what to fix: it leaves his reviews
    /// and waits in the inbox until a refine session fixes it. Returns the
    /// card.
    @discardableResult
    public func flag(_ cardID: Int64, note: FlagNote) throws(EngineError) -> Card {
        let flaggedAt = time.now
        return try write { db in
            try db.execute(
                sql: "UPDATE card SET flagNote = ?, flaggedAt = ? WHERE id = ?",
                arguments: [note.text, flaggedAt, cardID]
            )
            return try existingCard(cardID, in: db)
        }
    }

    /// Takes Lucas's flag off a card, as it is: it leaves the inbox and goes
    /// back to his reviews. ⌘Z in the review panel, after he flagged it.
    func unflag(_ cardID: Int64) throws(EngineError) {
        try write { db in
            guard try existingCard(cardID, in: db).flag != nil else {
                throw EngineError.cardNotFlagged(cardID)
            }
            try db.execute(sql: "UPDATE card SET flagNote = NULL, flaggedAt = NULL WHERE id = ?", arguments: [cardID])
        }
    }

    /// Fixes a flagged card with `content`, as a refine session drafted it
    /// and Lucas approved it: the card leaves the inbox and goes back to his
    /// reviews, on the step its review log puts it on. Returns the card.
    @discardableResult
    public func fix(_ cardID: Int64, with content: CardContent) throws(EngineError) -> Card {
        try write { db in
            guard try existingCard(cardID, in: db).flag != nil else {
                throw EngineError.cardNotFlagged(cardID)
            }
            try db.execute(
                sql: """
                    UPDATE card
                    SET type = ?, front = ?, back = ?, tags = ?, source = ?, flagNote = NULL, flaggedAt = NULL
                    WHERE id = ?
                    """,
                arguments: [
                    content.type.rawValue, content.front, content.back, try tagsJSON(content.tags), content.source,
                    cardID,
                ]
            )
            return try existingCard(cardID, in: db)
        }
    }

    /// Buries a card: it leaves Lucas's reviews for good, and the inbox if
    /// it's flagged, without deleting it or its review log. Returns the card.
    @discardableResult
    public func bury(_ cardID: Int64) throws(EngineError) -> Card {
        let buriedAt = time.now
        return try write { db in
            guard try existingCard(cardID, in: db).buriedAt == nil else {
                throw EngineError.cardBuried(cardID)
            }
            try db.execute(sql: "UPDATE card SET buriedAt = ? WHERE id = ?", arguments: [buriedAt, cardID])
            return try existingCard(cardID, in: db)
        }
    }

    /// Unburies a card: it goes back to where it was before Lucas buried it,
    /// on the step its review log puts it on. Returns the card.
    @discardableResult
    public func unbury(_ cardID: Int64) throws(EngineError) -> Card {
        try write { db in
            guard try existingCard(cardID, in: db).buriedAt != nil else {
                throw EngineError.cardNotBuried(cardID)
            }
            try db.execute(sql: "UPDATE card SET buriedAt = NULL WHERE id = ?", arguments: [cardID])
            return try existingCard(cardID, in: db)
        }
    }
}

/// The card with this id, as it is now, or an error when there's none.
private func existingCard(_ cardID: Int64, in db: Database) throws -> Card {
    guard let row = try Table("card").filter(Column("id") == cardID).fetchOne(db) else {
        throw EngineError.cardNotFound(cardID)
    }
    return try Card(row: row)
}
