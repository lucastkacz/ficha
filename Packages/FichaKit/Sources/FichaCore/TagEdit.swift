import Foundation

/// A change to a tag that reaches every card carrying it or a tag inside it
/// (ADR 0021, ADR 0022): a rename, which moves it with the tags inside it, or
/// a deletion, which takes it off with them.
public enum TagEdit: Sendable, Hashable {
    /// The tag `tag`, the first, renamed to the second.
    case rename(String, to: String)
    /// The tag deleted.
    case deletion(String)

    /// The tag it changes.
    public var tag: String {
        switch self {
        case .rename(let tag, _), .deletion(let tag): tag
        }
    }

    /// Whether it changes the tag `name`: it's the tag, or a tag inside it.
    public func changes(_ name: String) -> Bool {
        TagPath.isTag(name, within: tag)
    }

    /// The name the tag `name` has after it: its new name when it's the tag
    /// renamed or a tag inside it, nil when it's the tag deleted or a tag
    /// inside it, and `name` itself otherwise.
    public func name(of name: String) -> String? {
        switch self {
        case .rename(let tag, let newName): TagPath.renaming(name, from: tag, to: newName) ?? name
        case .deletion(let tag): TagPath.isTag(name, within: tag) ? nil : name
        }
    }

    /// A card's `tags` after it, in their order, each once: a card left with
    /// a tag twice, as a rename onto a tag it carries leaves it, carries it
    /// in the place of the first.
    public func tags(after tags: [String]) -> [String] {
        tags.compactMap(name(of:)).uniqued()
    }
}
