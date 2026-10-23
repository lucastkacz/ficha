import FichaCore
import Foundation
internal import GRDB

extension CardTag {
    /// Whether it's a priority tag: every card with it comes first when cards
    /// show up.
    public var isPriority: Bool {
        switchedOn == .priority
    }
}

extension Engine {
    /// The tags the menu's Prioritize submenu offers, each with what it has
    /// of its own, in alphabetical order as the Mac sorts text: every tag of
    /// the cards in Lucas's reviews, and every priority tag, which stays
    /// listed while no card in his reviews carries it, so that he can untick
    /// it. A set-aside tag's cards are out of his reviews, and it's never a
    /// priority tag, so it isn't offered.
    public func tagsToPrioritize() throws(EngineError) -> [CardTag] {
        try read { db in
            let ownTags = try tagsWithSomethingOfTheirOwn(in: db)
            let inReviews = try allCards(in: db).filter { $0.standing == .inReviews }
            let names = Set(inReviews.flatMap(\.tags)).union(ownTags.values.filter(\.isPriority).map(\.name))
            return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { ownTags[$0] ?? CardTag(name: $0) }
        }
    }

    /// Toggles `tag`'s priority: a priority tag is no longer one, and a tag
    /// that's neither a priority tag nor set aside becomes one, so its cards
    /// come first from the next appearance, review now or "See more" on. A
    /// set-aside tag stays set aside, since a tag is never both (ADR 0011):
    /// the Prioritize submenu doesn't offer it.
    public func togglePriority(of tag: String) throws(EngineError) {
        try write { db in
            var own = try tagsWithSomethingOfTheirOwn(in: db)[tag] ?? CardTag(name: tag)
            switch own.switchedOn {
            case .priority: own.switchedOn = nil
            case nil: own.switchedOn = .priority
            case .setAside: return
            }
            try save(own, in: db)
        }
    }

    /// Makes every priority tag no longer one, as the Prioritize submenu's
    /// "None" does, so the cards come in their usual order from the next
    /// appearance, review now or "See more" on.
    public func clearPriorityTags() throws(EngineError) {
        try write { db in
            for var tag in try tagsWithSomethingOfTheirOwn(in: db).values where tag.isPriority {
                tag.switchedOn = nil
                try save(tag, in: db)
            }
        }
    }
}
