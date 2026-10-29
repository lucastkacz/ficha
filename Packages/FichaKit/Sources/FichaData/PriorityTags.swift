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
/// "None", then each tag, and then All Tags… (ADR 0022).
public struct PrioritizeMenu: Sendable, Equatable {
    /// An item of the submenu.
    public enum Item: Sendable, Hashable {
        /// "None", ticked while no tag is a priority tag, which clears them.
        case noPriorityTag
        /// A tag, ticked while it's a priority tag, which toggles it.
        case tag(CardTag)
        /// All Tags…, which opens the Cards window on All Tags, for every
        /// other tag.
        case allTags
    }

    /// The tags it offers, each with what it has of its own and takes from
    /// the tags it sits inside, ticked while it's a priority tag: the pinned
    /// tags, in their order, and then the priority tags that aren't pinned,
    /// alphabetically by their whole names, each tag inside another right
    /// after it.
    public let tags: [CardTag]

    /// What it offers, in its order: "None", each of `tags`, and last All
    /// Tags….
    public var items: [Item] {
        [.noPriorityTag] + tags.map(Item.tag) + [.allTags]
    }

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
                tag.isPriority || CardStanding.setAsideTags(of: [tag.name], among: setAside).isEmpty
            }
            let others = TagPath.sortedAsTree(own.tags(switchedOn: .priority).filter { !$0.isPinned }.map(\.name))
            return PrioritizeMenu(tags: (pinned.map(\.name) + others).map(own.tag))
        }
    }

    /// Toggles `tag`'s priority, as the Prioritize submenu does: a priority
    /// tag is no longer one, and any other becomes one, as `setPriority(_:of:)`
    /// says.
    public func togglePriority(of tag: String) throws(EngineError) {
        try write { db in
            try setPriority(try !ownTag(tag, in: db).isPriority, of: tag, in: db)
        }
    }

    /// Makes `tag` a priority tag, so its cards come first from the next
    /// appearance, review now or "See more" on, or no longer one, whatever
    /// it was. A set-aside tag can't become one, since a tag is never both
    /// (ADR 0011), so the Prioritize submenu doesn't offer it, and the engine
    /// refuses it, as when another device set it aside meanwhile.
    public func setPriority(_ isPriority: Bool, of tag: String) throws(EngineError) {
        try write { db in try setPriority(isPriority, of: tag, in: db) }
    }

    /// Makes `tag` a priority tag, or no longer one, in the write `db`, as
    /// `setPriority(_:of:)` says.
    private func setPriority(_ isPriority: Bool, of tag: String, in db: Database) throws {
        var own = try ownTag(tag, in: db)
        switch (own.switchedOn, isPriority) {
        case (.setAside, true): throw EngineError.tagSetAside(tag)
        case (.setAside, false), (.priority, true), (nil, false): return
        case (.priority, false): own.switchedOn = nil
        case (nil, true): own.switchedOn = .priority
        }
        try save(own, in: db)
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
