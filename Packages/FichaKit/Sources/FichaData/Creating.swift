import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Creates a card with `content`, as the Cards window's form and the
    /// imports make cards, and returns it. It goes straight into the user's
    /// reviews as a new card, after the cards before it, unless one of its
    /// tags is set aside. It's saved whether or not its front repeats another
    /// card's: the duplicate rule only warns.
    ///
    /// With no capture, as from a new card or an import, the card has none.
    /// From `captureID`, a capture in the inbox, the card remembers it, as an
    /// approved card does, so that a capture repeating it repeats the card,
    /// and the capture stays in the inbox, for more cards from it. A capture
    /// that isn't in the inbox is refused.
    @discardableResult
    public func create(_ content: CardContent, from captureID: Int64? = nil) throws(EngineError) -> Card {
        let createdAt = time.now
        return try write { db in
            if let captureID {
                _ = try captureInInbox(captureID, in: db)
            }
            return try existingCard(insertCard(content, capturedAs: captureID, at: createdAt, in: db), in: db)
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
