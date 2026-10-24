import FichaCore
import Foundation
internal import GRDB

/// One small thing Lucas wants to remember, with a front and a back, as the
/// engine saved it when he approved it or the user created it. Each side
/// holds text, an image, a sound, or any of them together. The `ficha` CLI
/// prints it as JSON, without the type, images, sounds, source, edited time,
/// capture, flag, burial or set-aside tags it doesn't have.
public struct Card: Sendable, Equatable, Encodable {
    public let id: Int64
    /// Its type, or nil when it has none.
    public let type: CardType?
    /// The front's text, or empty when the front holds only an image or a
    /// sound.
    public let front: String
    /// The back's text, or empty when the back holds only an image or a
    /// sound.
    public let back: String
    /// The front's image, or nil when it has none.
    public let frontImage: ImageName?
    /// The back's image, or nil when it has none.
    public let backImage: ImageName?
    /// The front's sound, or nil when it has none.
    public let frontSound: SoundName?
    /// The back's sound, or nil when it has none.
    public let backSound: SoundName?
    public let tags: [String]
    public let source: String?
    /// When it came in: when the user approved it in a refine session, or created it.
    public let createdAt: Date
    /// When its front or back last changed, a side's image or sound included,
    /// or nil when neither changed since it came in, or since before Ficha
    /// kept it.
    public let editedAt: Date?
    /// The capture it was refined from, or nil when it came in another way,
    /// such as the Cards window's form or an import.
    public let captureID: Int64?
    /// Lucas's flag, while the card waits to be fixed, buried or not. Where
    /// the card stands is read from `standing`, never from this.
    public let flag: Flag?
    /// When Lucas buried it, while it's buried. Where the card stands is read
    /// from `standing`, never from this.
    public let buriedAt: Date?
    /// Its tags that are set aside, in alphabetical order, flagged or buried
    /// or not, or nil when none is. Where the card stands is read from
    /// `standing`, never from this.
    public let setAsideBy: [String]?

    /// Where the card stands: in Lucas's reviews, waiting in the inbox to be
    /// fixed, buried, or set aside with one of its tags.
    public var standing: CardStanding {
        CardStanding(flag: flag, buriedAt: buriedAt, setAsideBy: setAsideBy ?? [])
    }
}

extension Card {
    /// A card read from a row of the `card` table, whose tags are a JSON
    /// array, when the tags in `setAsideTags` are set aside.
    init(row: Row, setAsideTags: Set<String>) throws {
        let id: Int64 = try row.decode(forColumn: "id")
        self.id = id
        let typeName: String? = try row.decode(forColumn: "type")
        type = try typeName.map { typeName in
            guard let type = CardType(rawValue: typeName) else {
                throw unreadable("Card \(id) has an unknown type")
            }
            return type
        }
        front = try row.decode(forColumn: "front")
        back = try row.decode(forColumn: "back")
        frontImage = try fileName(in: row, column: ImageName.columns.front, ofCard: id)
        backImage = try fileName(in: row, column: ImageName.columns.back, ofCard: id)
        frontSound = try fileName(in: row, column: SoundName.columns.front, ofCard: id)
        backSound = try fileName(in: row, column: SoundName.columns.back, ofCard: id)
        let tagsColumn: String = try row.decode(forColumn: "tags")
        tags = try JSONDecoder().decode([String].self, from: Data(tagsColumn.utf8))
        source = try row.decode(forColumn: "source")
        createdAt = try row.decode(forColumn: "createdAt")
        editedAt = try row.decode(forColumn: "editedAt")
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
        let setAside = CardStanding.setAsideTags(of: tags, among: setAsideTags)
        setAsideBy = setAside.isEmpty ? nil : setAside
    }

    /// The images on its sides, each once.
    var images: Set<ImageName> {
        Set([frontImage, backImage].compactMap(\.self))
    }

    /// The sounds on its sides, each once.
    var sounds: Set<SoundName> {
        Set([frontSound, backSound].compactMap(\.self))
    }

    /// The sound on `side`, or nil for none.
    public func sound(on side: CardSide) -> SoundName? {
        switch side {
        case .front: frontSound
        case .back: backSound
        }
    }

    /// Which sides have an image, as the Cards window's Media column says,
    /// or nil when neither does.
    public var sidesWithImages: WhichSides? {
        WhichSides(front: frontImage != nil, back: backImage != nil)
    }

    /// Which sides have a sound, as the Cards window's Media column says, or
    /// nil when neither does.
    public var sidesWithSounds: WhichSides? {
        WhichSides(front: frontSound != nil, back: backSound != nil)
    }
}

/// Which sides of a card have something: its front, its back or both.
public enum WhichSides: Sendable, Equatable {
    case front
    case back
    case both

    /// The sides that have something, as `front` and `back` say, or nil when
    /// neither does.
    init?(front: Bool, back: Bool) {
        switch (front, back) {
        case (false, false): return nil
        case (true, false): self = .front
        case (false, true): self = .back
        case (true, true): self = .both
        }
    }
}

/// The file, an image or a sound, a side of card `cardID` refers to in
/// `column` of its row, or nil for none. A name that isn't one of `Name`
/// fails, as a card the engine never saved.
private func fileName<Name: NameOfFileOnCard>(in row: Row, column: String, ofCard cardID: Int64) throws -> Name? {
    let rawName: String? = try row.decode(forColumn: column)
    return try rawName.map { rawName in
        guard let name = Name(rawValue: rawName) else {
            throw unreadable("Card \(cardID) refers to a file that isn't named as Ficha names its \(Name.kind)s")
        }
        return name
    }
}

extension CardContent {
    /// This content with the images and sounds of `card` where it has none
    /// of its own, as a refine session's content keeps those of the card it
    /// changes, since refining never adds one.
    func keepingFiles(of card: Card) -> CardContent {
        keepingFiles(
            frontImage: card.frontImage, backImage: card.backImage, frontSound: card.frontSound,
            backSound: card.backSound)
    }
}

/// The cards in `rows` of the `card` table, as they are now, each knowing
/// which of its tags are set aside.
func cards(in rows: [Row], in db: Database) throws -> [Card] {
    let setAside = try setAsideTags(in: db)
    return try rows.map { try Card(row: $0, setAsideTags: setAside) }
}

/// Every card, in the order Lucas approved them.
func allCards(in db: Database) throws -> [Card] {
    try cards(in: Row.fetchAll(db, sql: "SELECT * FROM card ORDER BY id"), in: db)
}

/// The card with this id, as it is now, or an error when there's none.
func existingCard(_ cardID: Int64, in db: Database) throws -> Card {
    guard let row = try Table("card").filter(Column("id") == cardID).fetchOne(db) else {
        throw EngineError.cardNotFound(cardID)
    }
    return try Card(row: row, setAsideTags: setAsideTags(in: db))
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

/// Replaces a card's content with `content`, its images and sounds included,
/// keeping its review log, its flag and its burial, at `now`, which becomes
/// when its front or back last changed when either differs from before, a
/// side's image or sound included; a change to its type, tags or source alone
/// leaves that time as it was. Returns the card as it is then. Every change
/// to a card's content goes through here, with content `CardContent` checked,
/// as every new card goes through `insertCard`. An image or a sound the card
/// no longer refers to stays where Ficha keeps it: the engine removes it once
/// no card uses it.
func replaceContent(of cardID: Int64, with content: CardContent, at now: Date, in db: Database) throws -> Card {
    let before = try existingCard(cardID, in: db)
    return try updateCard(
        cardID,
        setting: """
            type = ?, front = ?, back = ?, frontImage = ?, backImage = ?, frontSound = ?, backSound = ?, tags = ?, \
            source = ?, editedAt = ?
            """,
        to: [
            content.type?.rawValue, content.front, content.back, content.frontImage?.rawValue,
            content.backImage?.rawValue, content.frontSound?.rawValue, content.backSound?.rawValue,
            try tagsJSON(content.tags), content.source, before.hasSides(of: content) ? before.editedAt : now,
        ],
        in: db
    )
}

extension Card {
    /// Whether the card's front and back are those of `content`, each with
    /// its image and its sound.
    fileprivate func hasSides(of content: CardContent) -> Bool {
        (front, back, frontImage, backImage, frontSound, backSound)
            == (
                content.front, content.back, content.frontImage, content.backImage, content.frontSound,
                content.backSound
            )
    }
}

/// The flagged cards that wait in the inbox to be fixed, as their standing
/// says, the first flagged first, and then in the order Lucas approved them.
func flaggedCardsWaiting(in db: Database) throws -> [Card] {
    let flagged: [(card: Card, flag: Flag)] = try allCards(in: db).compactMap { card in
        guard case .inInbox(let flag) = card.standing else {
            return nil
        }
        return (card, flag)
    }
    return flagged.sorted { ($0.flag.flaggedAt, $0.card.id) < ($1.flag.flaggedAt, $1.card.id) }.map(\.card)
}

/// A card's tags as the `card` table keeps them: a JSON array, which
/// `Card(row:)` reads back.
func tagsJSON(_ tags: [String]) throws -> String {
    String(decoding: try JSONEncoder().encode(tags), as: UTF8.self)
}
