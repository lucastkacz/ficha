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

extension Engine {
    /// Each tag's counts, as All Tags shows them, for every tag `allTags()`
    /// lists, each card standing on `ladder` now.
    public func tagCounts(on ladder: Ladder) throws(EngineError) -> [String: TagCounts] {
        let rows = try cardRows(in: .all, on: ladder)
        let now = time.now
        var counts = Dictionary(uniqueKeysWithValues: try allTags().map { ($0.name, (cards: 0, due: 0)) })
        for row in rows {
            let isDue = row.isDue(at: now)
            for tag in TagPath.lineages(of: row.card.tags) {
                counts[tag, default: (0, 0)].cards += 1
                counts[tag, default: (0, 0)].due += isDue ? 1 : 0
            }
        }
        return counts.mapValues { TagCounts(cards: $0.cards, due: $0.due) }
    }
}
