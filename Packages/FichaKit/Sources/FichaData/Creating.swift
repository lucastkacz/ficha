import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Creates a card with `content`, as the Cards window's form and the
    /// imports make cards, and returns it. It goes straight into the user's
    /// reviews as a new card, after the cards before it, unless its deck, or
    /// a deck it sits inside, is set aside. It's saved whether or not its
    /// front repeats another card's: the duplicate rule only warns. It lives
    /// in the deck `deck`, by its whole name, which is made if it isn't there,
    /// or in Default, as `changeDeck(of:to:)` takes a deck, and refuses one.
    /// It goes both ways when `bothWays` says so, and one way otherwise.
    @discardableResult
    public func create(_ content: CardContent, deck: String = Deck.defaultName, bothWays: Bool = false)
        throws(EngineError) -> Card
    {
        let createdAt = time.now
        return try write { db in
            let cardID = try insertCard(content, deck: deck, bothWays: bothWays, at: createdAt, in: db)
            return try existingCard(cardID, in: db)
        }
    }
}

/// The cards' fronts, by the duplicate rule, each with the first card that
/// came in with it, which the Cards window's form looks a front up in as it's
/// typed, and `Engine.add(_:)` looks up the fronts of the cards it adds in.
/// Only fronts count: a card is a duplicate by its front alone, whatever its
/// back.
struct FrontsInUse: Sendable, Equatable {
    private var firstCardIDs: [String: Int64] = [:]

    /// The id of the first card whose front `front` repeats, or nil when it
    /// repeats none. A front without text, which holds only an image or a
    /// sound, repeats none.
    func cardID(repeatedBy front: String) -> Int64? {
        guard !CardContent.isBlank(front) else {
            return nil
        }
        return firstCardIDs[duplicateKey(front)]
    }

    /// The fronts of the cards in `db`.
    init(in db: Database) throws {
        for row in try Row.fetchAll(db, sql: "SELECT id, front FROM card ORDER BY id") {
            let front: String = try row.decode(forColumn: "front")
            let key = duplicateKey(front)
            // The first card that came in stays.
            if !CardContent.isBlank(front), firstCardIDs[key] == nil {
                firstCardIDs[key] = try row.decode(forColumn: "id")
            }
        }
    }
}

extension Engine {
    /// The cards' fronts, as the Cards window's form looks them up.
    func frontsInUse() throws(EngineError) -> FrontsInUse {
        try read { db in try FrontsInUse(in: db) }
    }

    /// The card with the id `cardID`, or `cardNotFound` when there's none.
    func card(_ cardID: Int64) throws(EngineError) -> Card {
        try read { db in try existingCard(cardID, in: db) }
    }
}

/// Saves `content` as a new card in the deck `deck`, made if it isn't there,
/// or in Default, created at `time`, going both ways when `bothWays` says so,
/// and returns the card's id. Every card comes in through here, with content
/// `CardContent` checked, and its deck as `madeDeck(named:in:)` makes it. A
/// user type deleted meanwhile is refused.
@discardableResult
func insertCard(
    _ content: CardContent, deck: String = Deck.defaultName, bothWays: Bool = false, at time: Date,
    in db: Database
) throws -> Int64 {
    try checkExists(content.type, in: db)
    let deck = try madeDeck(named: deck, in: db)
    try db.execute(
        sql: """
            INSERT INTO card (
                type, front, back, frontImage, backImage, frontSound, backSound, tags, source, createdAt,
                bothWays, deck)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            content.type?.column, content.front, content.back, content.frontImage?.rawValue,
            content.backImage?.rawValue, content.frontSound?.rawValue, content.backSound?.rawValue,
            try tagsJSON(content.tags), content.source, time, bothWays, deck,
        ]
    )
    return db.lastInsertedRowID
}
