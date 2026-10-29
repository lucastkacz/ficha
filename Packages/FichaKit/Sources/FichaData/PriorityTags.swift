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
/// "None", then each tag, and then All Tags…, which the menu draws
/// (ADR 0022).
public struct PrioritizeMenu: Sendable, Equatable {
    /// The tags it offers, each with what it has of its own and takes from
    /// the tags it sits inside, ticked while it's a priority tag: the pinned
    /// tags, in their order, and then the priority tags that aren't pinned,
    /// alphabetically by their whole names, each tag inside another right
    /// after it.
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
    /// What the menu's Prioritize submenu offers: the pinned tags, in their
    /// order, and every priority tag that isn't pinned, which stays listed
    /// while no card carries it, so that Lucas can untick it. A set-aside
    /// tag's cards are out of his reviews, and so are those of a tag inside
    /// it, so a pinned tag set aside, on its own or inside a tag that is,
    /// isn't offered, unless it's a priority tag to untick.
    public func prioritizeMenu() throws(EngineError) -> PrioritizeMenu {
        try read { db in
            let own = try OwnTags(in: db)
            let setAside = Set(own.tags(switchedOn: .setAside).map(\.name))
            let pinned = own.pinned.filter { tag in
                tag.isPriority || !TagPath.lineage(of: tag.name).contains(where: setAside.contains)
            }
            let others = TagPath.sortedAsTree(own.tags(switchedOn: .priority).filter { !$0.isPinned }.map(\.name))
            return PrioritizeMenu(tags: (pinned.map(\.name) + others).map(own.tag))
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
