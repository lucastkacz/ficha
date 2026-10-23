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

    /// Approves a capture in the inbox into the cards created from it one at
    /// a time, as the Cards window's form does once it closes: takes it out
    /// of the inbox and returns those cards, in the order they came in. A
    /// capture no card was created from stays in the inbox, and is refused,
    /// as approving it into no cards is; so is one that isn't in the inbox.
    @discardableResult
    public func approve(_ captureID: Int64) throws(EngineError) -> [Card] {
        let refinedAt = time.now
        return try write { db in
            let cards = try FichaData.cards(
                in: Row.fetchAll(
                    db, sql: "SELECT * FROM card WHERE captureId = ? ORDER BY id", arguments: [captureID]),
                in: db)
            guard !cards.isEmpty else {
                throw EngineError.noCards
            }
            try takeOutOfInbox(captureID, at: refinedAt, in: db)
            return cards
        }
    }
}

extension Engine {
    /// The card whose front `front` repeats, by the duplicate rule, as the
    /// Cards window's form warns about it: the first one that came in, or nil
    /// when it repeats none.
    func cardRepeated(byFront front: String) throws(EngineError) -> Card? {
        try read { db in try FichaData.cardRepeated(byFront: front, in: db) }
    }
}

/// The card whose front `front` repeats, by the duplicate rule, the first one
/// that came in, or nil when it repeats none. Only fronts count: a card
/// created or imported is a duplicate by its front alone. A front without
/// text, which holds only an image, repeats none.
func cardRepeated(byFront front: String, in db: Database) throws -> Card? {
    guard !CardContent.isBlank(front) else {
        return nil
    }
    let fronts = try Row.fetchAll(db, sql: "SELECT id, front FROM card ORDER BY id")
    let repeated = try fronts.first { row in repeats(front, try row.decode(forColumn: "front")) }
    return try repeated.map { row in try existingCard(row.decode(forColumn: "id"), in: db) }
}

/// Saves `content` as a new card, created at `time` from the capture with the
/// id `captureID`, or from none when it's nil, and returns the card's id.
/// Every card comes in through here, with content `CardContent` checked.
@discardableResult
func insertCard(_ content: CardContent, capturedAs captureID: Int64?, at time: Date, in db: Database) throws -> Int64 {
    try db.execute(
        sql: """
            INSERT INTO card (type, front, back, frontImage, backImage, tags, source, createdAt, captureId)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            content.type?.rawValue, content.front, content.back, content.frontImage?.rawValue,
            content.backImage?.rawValue, try tagsJSON(content.tags), content.source, time, captureID,
        ]
    )
    return db.lastInsertedRowID
}
