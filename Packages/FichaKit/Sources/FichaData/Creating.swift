import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Creates a card with `content`, as the Cards window's form and the
    /// imports make cards, and returns it. It goes straight into the user's
    /// reviews as a new card, after the cards before it, unless one of its
    /// tags is set aside. It's saved whether or not its front repeats another
    /// card's: the duplicate rule only warns. It lives in the deck `deck`, by
    /// its whole name, which is made if it isn't there, or in Default, as
    /// `changeDeck(of:to:)` takes a deck, and refuses one. It goes both ways
    /// when `bothWays` says so, and one way otherwise.
    ///
    /// With no capture, as from a new card or an import, the card has none.
    /// From `captureID`, a capture in the inbox, the card remembers it, as an
    /// approved card does, so that a capture repeating it repeats the card,
    /// and the capture stays in the inbox, for more cards from it. A capture
    /// that isn't in the inbox is refused.
    @discardableResult
    public func create(
        _ content: CardContent, deck: String = Deck.defaultName, bothWays: Bool = false, from captureID: Int64? = nil
    ) throws(EngineError) -> Card {
        let createdAt = time.now
        return try write { db in
            if let captureID {
                _ = try captureInInbox(captureID, in: db)
            }
            let cardID = try insertCard(
                content, deck: deck, bothWays: bothWays, capturedAs: captureID, at: createdAt, in: db)
            return try existingCard(cardID, in: db)
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

/// The cards' fronts, by the duplicate rule, each with the first card that
/// came in with it, which the Cards window's form looks a front up in as it's
/// typed. Only fronts count: a card created or imported is a duplicate by its
/// front alone.
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
/// or in Default, created at `time` from the capture with the id
/// `captureID`, or from none when it's nil, going both ways when `bothWays`
/// says so, and returns the card's id. Every card comes in through here, with
/// content `CardContent` checked, and its deck as `deckOfCards(_:in:)` takes
/// it. A user type deleted meanwhile is refused.
@discardableResult
func insertCard(
    _ content: CardContent, deck: String = Deck.defaultName, bothWays: Bool = false,
    capturedAs captureID: Int64?, at time: Date, in db: Database
) throws -> Int64 {
    try checkExists(content.type, in: db)
    let deck = try deckOfCards(deck, in: db)
    try db.execute(
        sql: """
            INSERT INTO card (
                type, front, back, frontImage, backImage, frontSound, backSound, tags, source, createdAt, captureId,
                bothWays, deck)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            content.type?.column, content.front, content.back, content.frontImage?.rawValue,
            content.backImage?.rawValue, content.frontSound?.rawValue, content.backSound?.rawValue,
            try tagsJSON(content.tags), content.source, time, captureID, bothWays, deck,
        ]
    )
    return db.lastInsertedRowID
}
