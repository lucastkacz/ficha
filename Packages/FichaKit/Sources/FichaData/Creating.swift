import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Creates a card with `content`, which comes from no capture, as the
    /// Cards window's form and the imports make cards, and returns it. It
    /// goes straight into the user's reviews as a new card, after the cards
    /// before it, unless one of its tags is set aside. It's saved whether or
    /// not its front repeats another card's: the duplicate rule only warns.
    @discardableResult
    public func create(_ content: CardContent) throws(EngineError) -> Card {
        let createdAt = time.now
        return try write { db in
            try existingCard(insertCard(content, capturedAs: nil, at: createdAt, in: db), in: db)
        }
    }
}

/// Saves `content` as a new card, created at `time` from the capture with the
/// id `captureID`, or from none when it's nil, and returns the card's id.
/// Every card comes in through here, with content `CardContent` checked.
@discardableResult
func insertCard(_ content: CardContent, capturedAs captureID: Int64?, at time: Date, in db: Database) throws -> Int64 {
    try db.execute(
        sql: """
            INSERT INTO card (type, front, back, tags, source, createdAt, captureId)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            content.type?.rawValue, content.front, content.back, try tagsJSON(content.tags), content.source, time,
            captureID,
        ]
    )
    return db.lastInsertedRowID
}
