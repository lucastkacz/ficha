import FichaCore
import Foundation
internal import GRDB

/// One small thing Lucas wants to remember, with a front and a back, as the
/// engine saved it when he approved it or the user created it. Each side
/// holds text, an image, a sound, or any of them together. The `ficha` CLI
/// prints it as JSON, without the type, images, sounds, source, edited time,
/// capture, flag, burial or set-aside decks it doesn't have.
public struct Card: Sendable, Equatable, Encodable {
    public let id: Int64
    /// Its type, or nil when it has none, as when its user type was deleted,
    /// or hasn't come from another device yet. The CLI prints its name as a
    /// text file writes it (`CardType.writtenName`).
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
    /// The deck it lives in, by its whole name, its levels joined by `::`,
    /// or `Deck.defaultName`, which is empty, for Default.
    public let deck: String
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
    /// The set-aside decks it's set aside by, its deck and the decks it sits
    /// inside, as the user set them aside, Idiomas and not Idiomas::Inglés,
    /// the outermost first, flagged or buried or not, or nil when none is.
    /// Where the card stands is read from `standing`, never from this.
    public let setAsideBy: [String]?
    /// Whether the user also reviews it back first, its back and then its
    /// front, as well as front first (ADR 0016). How it's reviewed, not what
    /// it holds: changing its content keeps it.
    public let bothWays: Bool

    /// Where the card stands: in Lucas's reviews, waiting in the inbox to be
    /// fixed, buried, or set aside with its deck, or a deck its deck sits
    /// inside.
    public var standing: CardStanding {
        CardStanding(flag: flag, buriedAt: buriedAt, setAsideBy: setAsideBy ?? [])
    }
}

extension Card {
    /// A card read from a row of the `card` table, whose tags are a JSON
    /// array, when the decks in `setAsideDecks` are set aside, and the user's
    /// types are `userTypes`.
    init(row: Row, setAsideDecks: Set<String>, userTypes: UserTypes) throws {
        let id: Int64 = try row.decode(forColumn: "id")
        self.id = id
        let typeColumn: String? = try row.decode(forColumn: "type")
        type = try typeColumn.flatMap { try CardType(column: $0, ofCard: id, among: userTypes) }
        front = try row.decode(forColumn: "front")
        back = try row.decode(forColumn: "back")
        frontImage = try fileName(in: row, column: ImageName.columns.front, ofCard: id)
        backImage = try fileName(in: row, column: ImageName.columns.back, ofCard: id)
        frontSound = try fileName(in: row, column: SoundName.columns.front, ofCard: id)
        backSound = try fileName(in: row, column: SoundName.columns.back, ofCard: id)
        deck = try row.decode(forColumn: "deck")
        tags = try tagsFromJSON(try row.decode(forColumn: "tags"))
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
        let setAside = CardStanding.setAsideDecks(of: deck, among: setAsideDecks)
        setAsideBy = setAside.isEmpty ? nil : setAside
        bothWays = try row.decode(forColumn: "bothWays")
    }

    /// Whether it carries the tag `tag`, or a tag inside it, as choosing the
    /// tag in the Cards window's sidebar lists it.
    func hasTag(within tag: String) -> Bool {
        tags.contains { TagPath.isTag($0, within: tag) }
    }

    /// The images on its sides, each once.
    var images: Set<ImageName> {
        Set([frontImage, backImage].compactMap(\.self))
    }

    /// The sounds on its sides, each once.
    var sounds: Set<SoundName> {
        Set([frontSound, backSound].compactMap(\.self))
    }

    /// The text on `side`, which may be empty when the side has an image or a
    /// sound.
    public func text(on side: CardSide) -> String {
        switch side {
        case .front: front
        case .back: back
        }
    }

    /// What the front holds when it has no text: its image, or else its
    /// sound, which the Cards window names with a word where it lists the
    /// front (#229). Nil when the front has text.
    public var frontWithoutText: SideMedia? {
        guard front.isEmpty else {
            return nil
        }
        if frontImage != nil {
            return .image
        }
        return frontSound != nil ? .sound : nil
    }

    /// The image on `side`, or nil for none.
    public func image(on side: CardSide) -> ImageName? {
        switch side {
        case .front: frontImage
        case .back: backImage
        }
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

/// What a side without text holds instead: an image or a sound.
public enum SideMedia: Sendable, Equatable {
    case image
    case sound
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
    /// This content with the images and sounds of `card` where the card has
    /// them, as a card fixed or expanded with a content alone keeps its own,
    /// as with a refine session's draft that leaves them out.
    func keepingFiles(of card: Card) -> CardContent {
        keepingFiles(
            frontImage: card.frontImage, backImage: card.backImage, frontSound: card.frontSound,
            backSound: card.backSound)
    }
}

/// The cards in `rows` of the `card` table, as they are now, each knowing
/// which decks set it aside.
func cards(in rows: [Row], in db: Database) throws -> [Card] {
    let setAside = try setAsideDecks(in: db)
    let userTypes = try UserTypes(in: db)
    return try rows.map { try Card(row: $0, setAsideDecks: setAside, userTypes: userTypes) }
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
    return try Card(row: row, setAsideDecks: setAsideDecks(in: db), userTypes: UserTypes(in: db))
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
/// to a card's content made on this device goes through here, with content
/// `CardContent` checked, as every new card goes through `insertCard`, but
/// three that write one column of many cards at once: renaming a tag writes
/// their tags (`RenamingTags.swift`), turning tags into decks writes their
/// tags with their decks (`TagsIntoDecks.swift`), and deleting a user type
/// clears their type (`forgetType`). None can make a card `CardContent`
/// refuses, and going through here would clean up each card's other fields
/// as `CardContent` does, changing what the user didn't touch, such as a tag
/// stored before tags sat inside tags. An image or a sound the card no
/// longer refers to stays where Ficha keeps it: the engine removes it once
/// no card uses it. A user type deleted meanwhile is refused.
func replaceContent(of cardID: Int64, with content: CardContent, at now: Date, in db: Database) throws -> Card {
    try checkExists(content.type, in: db)
    let before = try existingCard(cardID, in: db)
    return try updateCard(
        cardID,
        setting: """
            type = ?, front = ?, back = ?, frontImage = ?, backImage = ?, frontSound = ?, backSound = ?, tags = ?, \
            source = ?, editedAt = ?
            """,
        to: [
            content.type?.column, content.front, content.back, content.frontImage?.rawValue,
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
/// `tagsFromJSON(_:)` reads back.
func tagsJSON(_ tags: [String]) throws -> String {
    String(decoding: try JSONEncoder().encode(tags), as: UTF8.self)
}

/// The tags `column`, a card's `tags` column, holds, as `tagsJSON(_:)` writes
/// them.
func tagsFromJSON(_ column: String) throws -> [String] {
    try JSONDecoder().decode([String].self, from: Data(column.utf8))
}
