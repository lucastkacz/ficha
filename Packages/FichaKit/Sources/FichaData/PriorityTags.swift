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

/// What the menu bar's Prioritize submenu offers, as the engine reads it:
/// "None", and then each tag, which the menu draws.
public struct PrioritizeMenu: Sendable, Equatable {
    /// The tags it offers, each with what it has of its own, ticked while
    /// it's a priority tag, in the order a tree lists them, so that each tag
    /// inside another follows it.
    public let tags: [CardTag]

    /// Whether "None" is ticked: no tag is a priority tag.
    public var isNoneTicked: Bool {
        priorityTagNames.isEmpty
    }

    /// The priority tags' names, in the order it offers them, which its
    /// title names while there are some.
    public var priorityTagNames: [String] {
        tags.filter(\.isPriority).map(\.name)
    }
}

extension Engine {
    /// What the menu's Prioritize submenu offers: every tag of the cards in
    /// Lucas's reviews, and every tag those sit inside, as the one way in to
    /// the cards that show up reads them, and every priority tag, which stays
    /// listed while no card in his reviews carries it, so that he can untick
    /// it. A set-aside tag's cards are out of his reviews, and it's never a
    /// priority tag, so it isn't offered.
    public func prioritizeMenu() throws(EngineError) -> PrioritizeMenu {
        try read { db in
            PrioritizeMenu(
                tags: try OwnTags(in: db).listing(cardsThatShowUp(in: db).inReviews.tags, alongWithEvery: .priority))
        }
    }

    /// Toggles `tag`'s priority: a priority tag is no longer one, and a tag
    /// that's neither a priority tag nor set aside becomes one, so its cards
    /// come first from the next appearance, review now or "See more" on. A
    /// set-aside tag stays set aside, since a tag is never both (ADR 0011):
    /// the Prioritize submenu doesn't offer it.
    public func togglePriority(of tag: String) throws(EngineError) {
        try write { db in
            var own = try ownTag(tag, in: db)
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
            for var tag in try OwnTags(in: db).tags(switchedOn: .priority) {
                tag.switchedOn = nil
                try save(tag, in: db)
            }
        }
    }
}
