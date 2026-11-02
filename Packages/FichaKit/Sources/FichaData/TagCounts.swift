import FichaCore
import Foundation
internal import GRDB

// Each tag's counts (ADR 0022): how many cards it lists, and how many of
// those are due, as All Tags' Cards and Due columns show them and `ficha
// tags` writes them.

/// Each tag's counts, as All Tags shows them and `ficha tags` writes them.
public struct TagCounts: Sendable, Equatable {
    /// How many cards the tag lists when it's chosen: those that carry it or
    /// a tag inside it, and aren't buried.
    public let cards: Int
    /// How many of those are due now and in the user's reviews, which those
    /// of a set-aside deck never are.
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
    /// All Tags shows them, each card standing as `scheduler` replays its log
    /// now: a tag no card lists counts none. One read, so each tag's pin,
    /// which gives the pinned tags' order (`pinnedInOrder`), and its counts
    /// are of the same moment.
    public func countedTags(with scheduler: Scheduler) throws(EngineError) -> [CountedTag] {
        let now = time.now
        return try read { db in
            let own = try OwnTags(in: db)
            var counts: [String: (cards: Int, due: Int)] = [:]
            for row in try FichaData.cardRows(in: .all, matching: "", with: scheduler, at: now, in: db) {
                let isDue = row.isDue(at: now)
                for tag in TagPath.lineages(of: row.card.tags) {
                    counts[tag, default: (0, 0)].cards += 1
                    counts[tag, default: (0, 0)].due += isDue ? 1 : 0
                }
            }
            return own.everyTagName(carriedBy: try allCards(in: db)).map { name in
                let count = counts[name, default: (0, 0)]
                return CountedTag(tag: own.tag(name), counts: TagCounts(cards: count.cards, due: count.due))
            }
        }
    }
}
