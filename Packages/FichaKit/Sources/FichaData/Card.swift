import FichaCore
import Foundation
internal import GRDB

/// One small thing Lucas wants to remember, with a front and a back, as the
/// engine saved it when he approved it. The `ficha` CLI prints it as JSON,
/// without the source, flag or burial it doesn't have.
public struct Card: Sendable, Equatable, Encodable {
    public let id: Int64
    public let type: CardType
    public let front: String
    public let back: String
    public let tags: [String]
    public let source: String?
    /// When Lucas approved it.
    public let createdAt: Date
    /// The capture it was refined from.
    public let captureID: Int64
    /// Lucas's flag, while the card waits to be fixed: out of his reviews,
    /// and in the inbox unless it's buried too.
    public let flag: Flag?
    /// When Lucas buried it, while it's buried: out of his reviews for good.
    public let buriedAt: Date?
}

/// Lucas's flag on a card: his note on what to fix, and when he wrote it.
public struct Flag: Sendable, Equatable, Encodable {
    /// What to fix, in his words.
    public let note: String
    /// When he flagged the card.
    public let flaggedAt: Date

    public init(note: String, flaggedAt: Date) {
        self.note = note
        self.flaggedAt = flaggedAt
    }
}

extension Card {
    /// A card read from a row of the `card` table, whose tags are a JSON array.
    init(row: Row) throws {
        id = try row.decode(forColumn: "id")
        let typeName: String = try row.decode(forColumn: "type")
        guard let type = CardType(rawValue: typeName) else {
            throw unreadable("Card \(id) has an unknown type")
        }
        self.type = type
        front = try row.decode(forColumn: "front")
        back = try row.decode(forColumn: "back")
        let tagsColumn: String = try row.decode(forColumn: "tags")
        tags = try JSONDecoder().decode([String].self, from: Data(tagsColumn.utf8))
        source = try row.decode(forColumn: "source")
        createdAt = try row.decode(forColumn: "createdAt")
        captureID = try row.decode(forColumn: "captureId")
        switch (try row.decode(forColumn: "flagNote") as String?, try row.decode(forColumn: "flaggedAt") as Date?) {
        case (nil, nil):
            flag = nil
        case (let note?, let flaggedAt?):
            flag = Flag(note: note, flaggedAt: flaggedAt)
        default:
            throw unreadable("Card \(id) has a flag without its note or its time")
        }
        buriedAt = try row.decode(forColumn: "buriedAt")
    }
}

/// Every card, in the order Lucas approved them.
func allCards(in db: Database) throws -> [Card] {
    try Row.fetchAll(db, sql: "SELECT * FROM card ORDER BY id").map(Card.init(row:))
}

/// The card with this id, as it is now, or an error when there's none.
func existingCard(_ cardID: Int64, in db: Database) throws -> Card {
    guard let row = try Table("card").filter(Column("id") == cardID).fetchOne(db) else {
        throw EngineError.cardNotFound(cardID)
    }
    return try Card(row: row)
}

/// The card with this id, while it's in Lucas's reviews, or an error that
/// says it's buried or flagged, or that there's no such card.
func cardInReviews(_ cardID: Int64, in db: Database) throws -> Card {
    let card = try existingCard(cardID, in: db)
    guard card.buriedAt == nil else {
        throw EngineError.cardBuried(cardID)
    }
    guard card.flag == nil else {
        throw EngineError.cardFlagged(cardID)
    }
    return card
}

/// Sets some of a card's columns, as `assignments` say, to `values` in
/// order, and returns the card as it is then.
func updateCard(
    _ cardID: Int64,
    setting assignments: String,
    to values: StatementArguments = [],
    in db: Database
) throws -> Card {
    try db.execute(sql: "UPDATE card SET \(assignments) WHERE id = ?", arguments: values + [cardID])
    return try existingCard(cardID, in: db)
}

/// The cards in Lucas's reviews, neither flagged nor buried, in the order he
/// approved them: the only ones the review panel brings.
func cardsInReviews(in db: Database) throws -> [Card] {
    try Table("card").filter(Column("flaggedAt") == nil && Column("buriedAt") == nil).order(Column("id"))
        .fetchAll(db).map(Card.init(row:))
}

/// The cards that wait in the inbox to be fixed: flagged, and not buried.
var flaggedCardsInInbox: QueryInterfaceRequest<Row> {
    Table("card").filter(Column("flaggedAt") != nil && Column("buriedAt") == nil)
}

/// A card's tags as the `card` table keeps them: a JSON array, which
/// `Card(row:)` reads back.
func tagsJSON(_ tags: [String]) throws -> String {
    String(decoding: try JSONEncoder().encode(tags), as: UTF8.self)
}
