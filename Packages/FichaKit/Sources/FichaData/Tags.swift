import FichaCore
import Foundation
internal import GRDB

/// A switch a tag can have on, which changes which of its cards show up
/// (ADR 0011). A tag has one on at most: setting aside a priority tag drops
/// its priority. Its raw value is how the `tag` table keeps it, so it never
/// changes.
public enum TagSwitch: String, Sendable {
    /// Its cards come first when cards show up.
    case priority
    /// Its cards are out of Lucas's reviews for now, without being buried.
    case setAside
}

/// One of Finder's seven tag colors, in Finder's order. Its raw value is how
/// the `tag` table keeps it, so it never changes.
public enum TagColor: String, Sendable, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray
}

/// A tag of Lucas's cards, by its name, exactly as cards carry it, with the
/// tags it sits inside (ADR 0021), with what it has of its own: the switch it
/// has on, its color and its emoji, each optional, and whether the user chose
/// it to sync. A tag with none of them is just a name. It carries the color
/// and the emoji it takes from the tags it sits inside too, which it shows
/// while it has none of its own.
public struct CardTag: Sendable, Hashable {
    /// Its whole name, its levels joined by `::`, as `TagPath` reads it.
    public let name: String
    /// The switch it has on, or nil when it's neither a priority tag nor set
    /// aside.
    public var switchedOn: TagSwitch?
    /// Its color, or nil for none.
    public var color: TagColor?
    /// Its emoji, or nil for none.
    public var emoji: String?
    /// Whether the user chose it to sync, for selective sync (ADR 0020): a
    /// switch of its own beside the other, so a priority tag or one set
    /// aside can be chosen too. A tag isn't, until the user ticks it.
    public var chosenToSync: Bool
    /// The color of the nearest tag it sits inside that has one, or nil when
    /// none does: never its own, and never stored.
    public let inheritedColor: TagColor?
    /// The emoji of the nearest tag it sits inside that has one, or nil when
    /// none does: never its own, and never stored.
    public let inheritedEmoji: String?

    public init(
        name: String, switchedOn: TagSwitch? = nil, color: TagColor? = nil, emoji: String? = nil,
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

    /// Whether it's set aside on its own: every card with it, or with a tag
    /// inside it, is out of Lucas's reviews for now.
    public var isSetAside: Bool {
        switchedOn == .setAside
    }

    /// The color it shows: its own, or else the nearest tag's it sits inside
    /// that has one, or nil for none. Its color and its emoji are each
    /// looked up apart.
    public var shownColor: TagColor? {
        color ?? inheritedColor
    }

    /// The emoji it shows: its own, or else the nearest tag's it sits inside
    /// that has one, or nil for none.
    public var shownEmoji: String? {
        emoji ?? inheritedEmoji
    }

    /// Whether it has nothing of its own, so the `tag` table has no row for
    /// it.
    var hasNothingOfItsOwn: Bool {
        switchedOn == nil && color == nil && emoji == nil && !chosenToSync
    }

    /// The tag named `name` with what this one has of its own, its switch,
    /// color, emoji and choice to sync, and with `inheritedColor` and
    /// `inheritedEmoji`, which it takes from the tags it sits inside there.
    func named(_ name: String, inheritedColor: TagColor? = nil, inheritedEmoji: String? = nil) -> CardTag {
        CardTag(
            name: name, switchedOn: switchedOn, color: color, emoji: emoji, chosenToSync: chosenToSync,
            inheritedColor: inheritedColor, inheritedEmoji: inheritedEmoji)
    }
}

extension Engine {
    /// The tags the Cards window's sidebar lists, each with what it has of
    /// its own and what it takes from the tags it sits inside, in the order a
    /// tree lists them: every tag of the cards that aren't buried, with every
    /// tag it sits inside, and every set-aside tag, which stays listed while
    /// no card carries it, so that Lucas can undo it.
    public func sidebarTags() throws(EngineError) -> [CardTag] {
        try read { db in
            try OwnTags(in: db).listing(
                TagPath.lineages(of: allCards(in: db).filter(\.standing.isInAllCards).flatMap(\.tags)),
                alongWithEvery: .setAside)
        }
    }

    /// Sets `tag` aside: every card with it leaves Lucas's reviews for now,
    /// also cards that get it later, unless it's buried or flagged. A
    /// priority tag is no longer one. Its cards keep their steps and their
    /// waits keep running.
    public func setAside(_ tag: String) throws(EngineError) {
        try write { db in
            var own = try ownTag(tag, in: db)
            own.switchedOn = .setAside
            try save(own, in: db)
        }
    }

    /// Stops setting `tag` aside: its cards come back to Lucas's reviews where
    /// they'd be without it, unless another of their tags is set aside. A tag
    /// that isn't set aside stays as it is.
    public func stopSettingAside(_ tag: String) throws(EngineError) {
        try write { db in
            var own = try ownTag(tag, in: db)
            guard own.isSetAside else { return }
            own.switchedOn = nil
            try save(own, in: db)
        }
    }
}

/// What every tag has of its own, as the `tag` table keeps it, read at
/// once: a tag the table has no row for is just a name.
struct OwnTags: Sendable {
    /// Every tag the `tag` table has a row for, since it has something of
    /// its own, by name.
    private let byName: [String: CardTag]

    /// What every tag has of its own, as the `tag` table keeps it now.
    init(in db: Database) throws {
        let tags = try Row.fetchAll(db, sql: "SELECT * FROM tag").map(CardTag.init(row:))
        byName = Dictionary(uniqueKeysWithValues: tags.map { ($0.name, $0) })
    }

    /// The tag with this name, with what it has of its own, which is nothing
    /// when the `tag` table has no row for it, and the color and the emoji of
    /// the nearest tags it sits inside that have one.
    func tag(_ name: String) -> CardTag {
        let ancestors = TagPath.ancestors(of: name).compactMap { byName[$0] }
        return (byName[name] ?? CardTag(name: name)).named(
            name, inheritedColor: ancestors.lazy.compactMap(\.color).first,
            inheritedEmoji: ancestors.lazy.compactMap(\.emoji).first)
    }

    /// Every tag with `tagSwitch` on.
    func tags(switchedOn tagSwitch: TagSwitch) -> [CardTag] {
        byName.values.filter { $0.switchedOn == tagSwitch }
    }

    /// Every tag the user chose to sync.
    var chosenToSync: [CardTag] {
        byName.values.filter(\.chosenToSync)
    }

    /// The tags named in `names`, and every tag with `tagSwitch` on, which
    /// stays listed while no card carries it, each once, as `tag(_:)` reads
    /// it, in the order a tree lists them, so that children follow their
    /// parent.
    func listing(_ names: some Sequence<String>, alongWithEvery tagSwitch: TagSwitch) -> [CardTag] {
        TagPath.sortedAsTree(Set(names).union(tags(switchedOn: tagSwitch).map(\.name))).map(tag)
    }
}

/// The tag with this name, with what it has of its own, which is nothing
/// when the `tag` table has no row for it.
func ownTag(_ name: String, in db: Database) throws -> CardTag {
    guard let row = try Row.fetchOne(db, sql: "SELECT * FROM tag WHERE name = ?", arguments: [name]) else {
        return CardTag(name: name)
    }
    return try CardTag(row: row)
}

/// Saves what `tag` has of its own in the `tag` table, or deletes its row
/// once it has nothing left.
func save(_ tag: CardTag, in db: Database) throws {
    if tag.hasNothingOfItsOwn {
        try db.execute(sql: "DELETE FROM tag WHERE name = ?", arguments: [tag.name])
    } else {
        try db.execute(
            sql: """
                INSERT INTO tag (name, switchedOn, color, emoji, chosenToSync) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (name) DO UPDATE SET
                    switchedOn = excluded.switchedOn, color = excluded.color, emoji = excluded.emoji,
                    chosenToSync = excluded.chosenToSync
                """,
            arguments: [tag.name, tag.switchedOn?.rawValue, tag.color?.rawValue, tag.emoji, tag.chosenToSync])
    }
}

extension CardTag {
    /// A tag read from a row of the `tag` table.
    fileprivate init(row: Row) throws {
        let name: String = try row.decode(forColumn: "name")
        let switchName: String? = try row.decode(forColumn: "switchedOn")
        let colorName: String? = try row.decode(forColumn: "color")
        self.name = name
        switchedOn = try switchName.map { switchName in
            guard let tagSwitch = TagSwitch(rawValue: switchName) else {
                throw unreadable("A tag has an unknown switch on")
            }
            return tagSwitch
        }
        color = try colorName.map { colorName in
            guard let color = TagColor(rawValue: colorName) else {
                throw unreadable("A tag has an unknown color")
            }
            return color
        }
        emoji = try row.decode(forColumn: "emoji")
        chosenToSync = try row.decode(forColumn: "chosenToSync")
        inheritedColor = nil
        inheritedEmoji = nil
    }
}
