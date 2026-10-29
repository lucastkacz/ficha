import FichaCore
import Foundation

// Each tag's counts (ADR 0022): how many cards it lists, and how many of
// those are due, as All Tags' Cards and Due columns show them and `ficha
// tags` writes them.

/// Each tag's counts, as All Tags shows them and `ficha tags` writes them.
public struct TagCounts: Sendable, Equatable {
    /// How many cards the tag lists when it's chosen: those that carry it or
    /// a tag inside it, and aren't buried.
    public let cards: Int
    /// How many of those are due now and in the user's reviews, which a
    /// set-aside tag's never are.
    public let due: Int

    public init(cards: Int, due: Int) {
        self.cards = cards
        self.due = due
    }
}

/// A tag with its counts, read together, so that every tag has its own.
public struct CountedTag: Sendable, Equatable {
    /// The tag, with what it has of its own and takes from the tags it sits
    /// inside.
    public let tag: CardTag
    /// How many cards it lists, and how many of those are due.
    public let counts: TagCounts

    public init(tag: CardTag, counts: TagCounts) {
        self.tag = tag
        self.counts = counts
    }
}

extension Engine {
    /// Every tag `allTags()` lists, in its order, each with its counts, as
    /// All Tags shows them, each card standing on `ladder` now: a tag no card
    /// lists counts none.
    public func countedTags(on ladder: Ladder) throws(EngineError) -> [CountedTag] {
        let tags = try allTags()
        let rows = try cardRows(in: .all, on: ladder)
        let now = time.now
        var counts: [String: (cards: Int, due: Int)] = [:]
        for row in rows {
            let isDue = row.isDue(at: now)
            for tag in TagPath.lineages(of: row.card.tags) {
                counts[tag, default: (0, 0)].cards += 1
                counts[tag, default: (0, 0)].due += isDue ? 1 : 0
            }
        }
        return tags.map { tag in
            let count = counts[tag.name, default: (0, 0)]
            return CountedTag(tag: tag, counts: TagCounts(cards: count.cards, due: count.due))
        }
    }
}
