import FichaCore
import Foundation
internal import GRDB

// Turning tags into decks (ADR 0024): before decks, Lucas's tags said where
// each card lived, and the update put every card in Default, its tags as they
// were. He turns the tags that were his subjects into decks once, with the
// `ficha` CLI, in a session he starts, so the app has no conversion. It takes
// a list of tags, in order, and for each tag: the tag, and each tag inside
// it, become decks of the same whole names, made on this device; every card
// that carries one of them, and is still in Default, moves to the deck of the
// deepest one it carries, the first in the order a tree lists them when two
// are as deep, and loses that tag and those it sits inside, which its deck now
// says; each tag's color, emoji, switch and choice to sync, kept by the `tag`
// table from before decks, go to its deck; and each tag's row goes, its pin
// with it, since decks aren't pinned. A card that an earlier tag of the list
// moved out of Default stays there, and keeps a later one as a tag, as a card
// does that carries two tags of one tag, neither inside the other. It's one
// write, so a deck chosen to sync is chosen as its cards move in, and every
// change syncs as the rows' own do: no change to a tag is recorded, so a card
// on another device that doesn't sync keeps its tags.

/// What turning tags into decks does on this device, as its preview says
/// before and the `ficha` CLI prints after.
public struct TagConversion: Sendable, Equatable, Encodable {
    /// A deck the conversion makes from a tag.
    public struct NewDeck: Sendable, Equatable, Encodable {
        /// Its whole name, the tag's.
        public let name: String
        /// How many cards move to it, not counting those of the decks inside
        /// it.
        public let cards: Int
    }

    /// A card that carries two tags or more that become decks, neither inside
    /// the other, so that it goes to one deck and keeps the others as tags.
    public struct CardWithTwoTags: Sendable, Equatable, Encodable {
        public let id: Int64
        public let front: String
        /// The tags it carries that become decks, as it carries them.
        public let tags: [String]
        /// The deck it goes to, by its whole name.
        public let deck: String
    }

    /// The decks it makes, in the order a tree lists them.
    public let decks: [NewDeck]
    /// The cards that carry two tags or more that become decks, neither
    /// inside the other, in the order Lucas approved them.
    public let cardsWithTwoTags: [CardWithTwoTags]
}

extension Engine {
    /// What turning `tags` into decks, in their order, would do now, as
    /// `convertTagsToDecks(_:)` says, without changing anything. Refuses what
    /// it refuses.
    public func conversion(ofTags tags: [String]) throws(EngineError) -> TagConversion {
        try read { db in try TagsIntoDecks(converting: tags, in: db).conversion }
    }

    /// Turns `tags`, each by its whole name, in their order, into decks, in
    /// one write, as the file's header says, and returns what it did. A tag
    /// no card carries and no row has turns into nothing. Refuses a tag whose
    /// deck would take one of Default's names at its top level, as
    /// `makeDeck(named:)` does, changing nothing.
    @discardableResult
    public func convertTagsToDecks(_ tags: [String]) throws(EngineError) -> TagConversion {
        try write { db in
            let conversion = try TagsIntoDecks(converting: tags, in: db)
            try conversion.make(in: db)
            return conversion.conversion
        }
    }
}

/// Turning a list of tags into decks, worked out from a database as it is,
/// before any of it is made.
private struct TagsIntoDecks {
    /// A card as the conversion leaves it.
    private struct ConvertedCard {
        let card: Card
        var deck: String
        var tags: [String]
        /// Whether a tag of the list moved it out of Default.
        var moved = false
    }

    /// The name of every deck it makes.
    private var decks: Set<String> = []
    /// What the tags with a row had of their own, by the name of the deck
    /// each becomes.
    private var ownTags: [String: CardTag] = [:]
    /// The name of every tag that becomes a deck, as cards carry it.
    private var tags: Set<String> = []
    /// The tags whose rows go.
    private var tagRows: Set<String> = []
    /// Every card, as the conversion leaves it.
    private var cards: [ConvertedCard]

    /// Turning `list` into decks in `db`, as it is now.
    init(converting list: [String], in db: Database) throws {
        let own = try OwnTags(in: db)
        var rows = Set(own.names)
        cards = try allCards(in: db).map { ConvertedCard(card: $0, deck: $0.deck, tags: $0.tags) }
        for tag in list {
            let existing = TagPath.lineages(of: cards.flatMap(\.tags) + rows)
            for name in existing where TagPath.isTag(name, within: tag) {
                let deck = try checkedDeckName(name)
                decks.insert(deck)
                tags.insert(name)
                if rows.remove(name) != nil {
                    ownTags[deck] = own.tag(name)
                    tagRows.insert(name)
                }
            }
            for index in cards.indices where cards[index].deck == Deck.defaultName {
                let carried = TagPath.sortedAsTree(cards[index].tags.filter { TagPath.isTag($0, within: tag) })
                guard
                    let deepest = carried.max(by: { TagPath.levels(of: $0).count < TagPath.levels(of: $1).count })
                else {
                    continue
                }
                let lineage = TagPath.lineage(of: deepest)
                cards[index].deck = try checkedDeckName(deepest)
                cards[index].tags.removeAll(where: lineage.contains)
                cards[index].moved = true
            }
        }
    }

    /// What it does, as its preview says it.
    var conversion: TagConversion {
        let moved = cards.filter(\.moved)
        return TagConversion(
            decks: TagPath.sortedAsTree(decks).map { deck in
                TagConversion.NewDeck(name: deck, cards: moved.count { $0.deck == deck })
            },
            cardsWithTwoTags: moved.filter { $0.tags.contains(where: tags.contains) }.map { converted in
                TagConversion.CardWithTwoTags(
                    id: converted.card.id, front: converted.card.front,
                    tags: converted.card.tags.filter(tags.contains), deck: converted.deck)
            })
    }

    /// Makes it in the write `db`: the decks first, with what their tags had
    /// of their own, then the cards' moves, and last the tags' rows go.
    func make(in db: Database) throws {
        for deck in TagPath.sortedAsTree(decks) {
            try makeRow(ofDeck: deck, madeHere: true, in: db)
        }
        for (deck, tag) in ownTags {
            try changeOwnDecks([deck], in: db) { own in
                own.color = tag.color ?? own.color
                own.emoji = tag.emoji ?? own.emoji
                own.switchedOn = tag.switchedOn.map(DeckSwitch.init) ?? own.switchedOn
                own.chosenToSync = own.chosenToSync || tag.chosenToSync
            }
        }
        for converted in cards where converted.moved {
            try db.execute(
                sql: "UPDATE card SET deck = ?, tags = ? WHERE id = ?",
                arguments: [converted.deck, try tagsJSON(converted.tags), converted.card.id])
        }
        for tag in tagRows {
            try deleteRow(ofTag: tag, in: db)
        }
    }
}

extension DeckSwitch {
    /// The deck's switch a tag's switch from before decks becomes.
    fileprivate init(_ tagSwitch: TagSwitch) {
        switch tagSwitch {
        case .priority: self = .priority
        case .setAside: self = .setAside
        }
    }
}
