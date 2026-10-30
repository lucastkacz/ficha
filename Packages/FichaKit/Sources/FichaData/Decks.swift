import FichaCore
import Foundation
internal import GRDB

// Decks (ADR 0024, `GLOSSARY.md`'s Deck and Default): each card lives in
// exactly one, which it names by the deck's whole name, its levels joined by
// `::` and cleaned up as `TagPath` cleans up a tag's, or by Default's,
// `Deck.defaultName`. A parent exists through the decks inside it, as a tag's
// does (ADR 0021), and holds their cards. A deck has a row of its own in the
// `deck` table while it exists (`Schema`'s "v31 decks"), so one the user makes
// stays while it has no cards; it holds the deck's switch, color, emoji and
// choice to sync, which sync as a tag's do (`SyncedDecks.swift`). Default
// gets its row once something is set on it, and is listed only while it
// holds cards.

/// A switch a deck can have on, which changes which of its cards show up
/// (ADR 0011, ADR 0024). A deck has one on at most. Its raw value is how the
/// `deck` table keeps it, so it never changes.
public enum DeckSwitch: String, Sendable {
    /// Its cards, and those of every deck inside it, come first when cards
    /// show up.
    case priority
    /// Its cards, and those of every deck inside it, are out of the user's
    /// reviews for now, without being buried.
    case setAside
}

/// A deck of the user's cards, by its whole name, with the decks it sits
/// inside, and what it has of its own: the switch it has on, its color and
/// its emoji, each optional, and whether the user chose it to sync. It
/// carries the color and the emoji it takes from the decks it sits inside
/// too, which it shows while it has none of its own.
public struct Deck: Sendable, Hashable {
    /// Default's name, as a card names it and the `deck` table keeps it:
    /// empty, which no name the user types is, since a blank one is refused
    /// (`Engine.makeDeck(named:)`). The app shows Default by a name of its
    /// own, in the Mac's language, as `Deck.defaultNames` lists it.
    public static let defaultName = ""

    /// Its whole name, its levels joined by `::`, as `TagPath` reads it, or
    /// `defaultName` for Default.
    public let name: String
    /// The switch it has on, or nil when it's neither a priority deck nor set
    /// aside.
    public var switchedOn: DeckSwitch?
    /// Its color, or nil for none.
    public var color: TagColor?
    /// Its emoji, or nil for none.
    public var emoji: String?
    /// Whether the user chose it to sync, for selective sync (ADR 0020). A
    /// deck isn't, until the user ticks it.
    public var chosenToSync: Bool
    /// The color of the nearest deck it sits inside that has one, or nil when
    /// none does: never its own, and never stored.
    public let inheritedColor: TagColor?
    /// The emoji of the nearest deck it sits inside that has one, or nil when
    /// none does: never its own, and never stored.
    public let inheritedEmoji: String?

    public init(
        name: String, switchedOn: DeckSwitch? = nil, color: TagColor? = nil, emoji: String? = nil,
        chosenToSync: Bool = false, inheritedColor: TagColor? = nil, inheritedEmoji: String? = nil
    ) {
        self.name = name
        self.switchedOn = switchedOn
        self.color = color
        self.emoji = emoji
        self.chosenToSync = chosenToSync
        self.inheritedColor = inheritedColor
        self.inheritedEmoji = inheritedEmoji
    }

    /// Whether it's Default.
    public var isDefault: Bool {
        name == Self.defaultName
    }

    /// The color it shows: its own, or else the nearest deck's it sits inside
    /// that has one, or nil for none.
    public var shownColor: TagColor? {
        color ?? inheritedColor
    }

    /// The emoji it shows: its own, or else the nearest deck's it sits inside
    /// that has one, or nil for none.
    public var shownEmoji: String? {
        emoji ?? inheritedEmoji
    }

    /// The names Default goes by, which no deck the user makes takes at its
    /// top level: "Default", and its name in the Mac's language, as the app
    /// shows it, whose key of the app's String Catalog this is.
    static var defaultNames: [String] {
        ["Default", String(localized: "Default", comment: "The deck a card lives in when it has no other.")]
    }
}

/// A deck's counts, as the Cards window's sidebar shows them.
public struct DeckCounts: Sendable, Equatable {
    /// How many cards the deck lists when it's chosen: those that live in it
    /// or in a deck inside it, and aren't buried.
    public let cards: Int
    /// How many of those are due now and in the user's reviews.
    public let due: Int

    public init(cards: Int, due: Int) {
        self.cards = cards
        self.due = due
    }
}

/// A deck with its counts, read together, so that every deck has its own.
public struct CountedDeck: Sendable, Equatable {
    /// The deck, with what it has of its own and takes from the decks it sits
    /// inside.
    public let deck: Deck
    /// How many cards it lists, and how many of those are due.
    public let counts: DeckCounts

    public init(deck: Deck, counts: DeckCounts) {
        self.deck = deck
        self.counts = counts
    }
}

extension Engine {
    /// Every deck this device lists, in the order a tree lists them, Default
    /// first: every deck with a row, every deck a card lives in, buried cards
    /// too, and every deck those sit inside, each with what it has of its own
    /// and takes from the decks it sits inside; and Default only while it
    /// holds cards.
    public func decks() throws(EngineError) -> [Deck] {
        try read { db in
            let own = try OwnDecks(in: db)
            return own.everyDeckName(livedInBy: try allCards(in: db)).map(own.deck)
        }
    }

    /// Every deck `decks()` lists, in its order, each with its counts, each
    /// card standing on `ladder` now, in one read: a deck no card lives in
    /// counts none.
    public func countedDecks(on ladder: Ladder) throws(EngineError) -> [CountedDeck] {
        let now = time.now
        return try read { db in
            let own = try OwnDecks(in: db)
            var counts: [String: (cards: Int, due: Int)] = [:]
            for row in try FichaData.cardRows(in: .all, matching: "", on: ladder, at: now, in: db) {
                let isDue = row.isDue(at: now)
                for deck in TagPath.lineage(of: row.card.deck) {
                    counts[deck, default: (0, 0)].cards += 1
                    counts[deck, default: (0, 0)].due += isDue ? 1 : 0
                }
            }
            return own.everyDeckName(livedInBy: try allCards(in: db)).map { name in
                let count = counts[name, default: (0, 0)]
                return CountedDeck(deck: own.deck(name), counts: DeckCounts(cards: count.cards, due: count.due))
            }
        }
    }

    /// Makes the deck named `name`, its levels cleaned up as `TagPath`
    /// cleans up a tag's, and returns that name: it stays, also while no
    /// card lives in it, with the decks it sits inside. A deck that's there
    /// already stays as it is. Refuses a blank name, and one whose top level
    /// is one of Default's names (`checkedDeckName(_:)`).
    @discardableResult
    public func makeDeck(named name: String) throws(EngineError) -> String {
        let name = try checkedDeckName(name)
        try write { db in try makeRow(ofDeck: name, in: db) }
        return name
    }

    /// Moves the cards with the ids `cardIDs` to the deck `deck`, by its whole
    /// name, its levels cleaned up as `makeDeck(named:)` cleans them up, or
    /// to Default, by `Deck.defaultName`, in one write: Change Deck. Each
    /// card keeps its step, its review log and its tags, and the change syncs
    /// as one to its deck. A deck that isn't there is made. Refuses a name
    /// `makeDeck(named:)` refuses, and a card that isn't there, moving none.
    public func changeDeck(of cardIDs: Set<Int64>, to deck: String) throws(EngineError) {
        let deck = deck == Deck.defaultName ? deck : try checkedDeckName(deck)
        try write { db in
            for cardID in cardIDs.sorted() {
                _ = try existingCard(cardID, in: db)
            }
            if deck != Deck.defaultName {
                try makeRow(ofDeck: deck, in: db)
            }
            for cardID in cardIDs.sorted() {
                try db.execute(sql: "UPDATE card SET deck = ? WHERE id = ?", arguments: [deck, cardID])
            }
        }
    }
}

/// `name`, a deck's whole name as the user gives it, its levels cleaned up as
/// `TagPath.normalized(_:)` cleans up a tag's: or an error when no level is
/// left, or when its top level is one of the names Default goes by
/// (`Deck.defaultNames`), ignoring case and accents, as a user type's name is
/// compared, so that no deck looks like Default in the sidebar. A deck inside
/// another can be named so: “Arte › Default”.
func checkedDeckName(_ name: String) throws(EngineError) -> String {
    guard let name = TagPath.normalized(name) else {
        throw .blankDeckName
    }
    let top = TagPath.levels(of: name).first ?? name
    guard !Deck.defaultNames.contains(where: { UserType.isSameName(top, as: $0) }) else {
        throw .defaultDeckName(top)
    }
    return name
}

/// Gives the deck `name` its row, with nothing of its own, in the write `db`,
/// unless it has one, which stays as it is.
func makeRow(ofDeck name: String, in db: Database) throws {
    try db.execute(sql: "INSERT INTO deck (name) VALUES (?) ON CONFLICT (name) DO NOTHING", arguments: [name])
}

/// What every deck has of its own, as the `deck` table keeps it, read at
/// once: a deck the table has no row for, one a card lives in or one other
/// decks sit inside, has nothing of its own.
struct OwnDecks: Sendable {
    /// Every deck the `deck` table has a row for, by name.
    private let byName: [String: Deck]

    /// What every deck has of its own, as the `deck` table keeps it now.
    init(in db: Database) throws {
        let decks = try Row.fetchAll(db, sql: "SELECT * FROM deck").map(Deck.init(row:))
        byName = Dictionary(uniqueKeysWithValues: decks.map { ($0.name, $0) })
    }

    /// The deck with this name, with what it has of its own, which is nothing
    /// when the `deck` table has no row for it, and the color and the emoji of
    /// the nearest decks it sits inside that have one.
    func deck(_ name: String) -> Deck {
        let ancestors = TagPath.ancestors(of: name).compactMap { byName[$0] }
        let own = byName[name] ?? Deck(name: name)
        return Deck(
            name: name, switchedOn: own.switchedOn, color: own.color, emoji: own.emoji,
            chosenToSync: own.chosenToSync, inheritedColor: ancestors.lazy.compactMap(\.color).first,
            inheritedEmoji: ancestors.lazy.compactMap(\.emoji).first)
    }

    /// The name of every deck, as `Engine.decks()` lists them, in the order a
    /// tree lists them: Default first, while one of `cards` lives in it, then
    /// every deck one of `cards` lives in, every deck with a row, and every
    /// deck those sit inside.
    func everyDeckName(livedInBy cards: [Card]) -> [String] {
        let holdsDefault = cards.contains { $0.deck == Deck.defaultName }
        let named = TagPath.lineages(of: cards.map(\.deck) + byName.keys).subtracting([Deck.defaultName])
        return (holdsDefault ? [Deck.defaultName] : []) + TagPath.sortedAsTree(named)
    }
}

/// The deck with this name, with what it has of its own, which is nothing
/// when the `deck` table has no row for it.
func ownDeck(_ name: String, in db: Database) throws -> Deck {
    try deckWithRow(name, in: db) ?? Deck(name: name)
}

/// The deck with this name, with what it has of its own, as its row of the
/// `deck` table holds it, or nil when it has none.
func deckWithRow(_ name: String, in db: Database) throws -> Deck? {
    try Row.fetchOne(db, sql: "SELECT * FROM deck WHERE name = ?", arguments: [name]).map(Deck.init(row:))
}

/// Changes what each of `decks` has of its own with `change`, in the write
/// `db`, and saves it, giving a deck without a row its row: the loop behind
/// every change the engine makes to decks' switches, colors, emoji and
/// choices to sync, in one write, which an error `change` throws undoes
/// whole. A deck `change` leaves as it was stays as it is, since the sync
/// triggers record only what changed.
func changeOwnDecks(_ decks: [String], in db: Database, _ change: (inout Deck) throws -> Void) throws {
    for name in decks {
        var own = try ownDeck(name, in: db)
        try change(&own)
        try save(own, in: db)
    }
}

/// Saves what `deck` has of its own in its row of the `deck` table, which it
/// gets when it has none.
func save(_ deck: Deck, in db: Database) throws {
    try db.execute(
        sql: """
            INSERT INTO deck (name, switchedOn, color, emoji, chosenToSync) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (name) DO UPDATE SET
                switchedOn = excluded.switchedOn, color = excluded.color, emoji = excluded.emoji,
                chosenToSync = excluded.chosenToSync
            """,
        arguments: [deck.name, deck.switchedOn?.rawValue, deck.color?.rawValue, deck.emoji, deck.chosenToSync])
}

extension Deck {
    /// A deck read from a row of the `deck` table.
    fileprivate init(row: Row) throws {
        let switchName: String? = try row.decode(forColumn: "switchedOn")
        let colorName: String? = try row.decode(forColumn: "color")
        self.init(
            name: try row.decode(forColumn: "name"),
            switchedOn: try switchName.map { switchName in
                guard let deckSwitch = DeckSwitch(rawValue: switchName) else {
                    throw unreadable("A deck has an unknown switch on")
                }
                return deckSwitch
            },
            color: try colorName.map { colorName in
                guard let color = TagColor(rawValue: colorName) else {
                    throw unreadable("A deck has an unknown color")
                }
                return color
            },
            emoji: try row.decode(forColumn: "emoji"), chosenToSync: try row.decode(forColumn: "chosenToSync"))
    }
}
