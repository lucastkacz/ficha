import Foundation

/// Tags inside tags (ADR 0021): a tag's name carries the tags it sits
/// inside, its levels joined by `::` as Anki writes them, so
/// `economía::Argentina` is Argentina inside economía, and a parent exists
/// through the tags inside it. The one place that reads a tag's levels:
/// whatever asks which tags one sits inside, as a tag's switches, color and
/// emoji do, or lists tags as a tree, asks here, never splitting a name
/// again.
public enum TagPath {
    /// What joins a tag's levels in its name, as cards, the `ficha` CLI,
    /// Export and Import carry it.
    public static let separator = "::"

    /// What joins a tag's levels where the app writes a tag standing alone,
    /// as in "economía › Argentina".
    private static let shownSeparator = " › "

    /// `name` as a tag's name: its levels without the spaces and line breaks
    /// around them, and without the empty ones, so `economía:: Argentina` and
    /// `economía::::Argentina` are `economía::Argentina`, with each accented
    /// letter as one character (Unicode's NFC), as the database compares
    /// names, character by character; or nil when no level is left, as for a
    /// blank name.
    public static func normalized(_ name: String) -> String? {
        let levels = cleaned(name.components(separatedBy: separator))
        return levels.isEmpty ? nil : levels.joined(separator: separator).precomposedStringWithCanonicalMapping
    }

    /// The levels of the tag `name`, the outermost first. A name stored
    /// before tags sat inside tags, with an empty level or spaces around one,
    /// which `normalized(_:)` would change, is one level, whole: a tag at the
    /// top that nothing sits inside, until it's renamed.
    public static func levels(of name: String) -> [String] {
        let levels = name.components(separatedBy: separator)
        return cleaned(levels) == levels ? levels : [name]
    }

    /// `levels` without the spaces and line breaks around each, and without
    /// the empty ones.
    private static func cleaned(_ levels: [String]) -> [String] {
        levels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Its last level, which names it in a tree under its parent: Argentina
    /// for `economía::Argentina`.
    public static func lastLevel(of name: String) -> String {
        levels(of: name).last ?? name
    }

    /// The tag `name` sits right inside, or nil for a tag at the top.
    public static func parent(of name: String) -> String? {
        let levels = levels(of: name)
        return levels.count > 1 ? levels.dropLast().joined(separator: separator) : nil
    }

    /// The tags `name` sits inside, its parent first, and the tag at the top
    /// last.
    public static func ancestors(of name: String) -> [String] {
        Array(sequence(first: name, next: parent(of:)).dropFirst())
    }

    /// The tag `name`, and then every tag it sits inside, its parent first:
    /// the tags whose switches, color and emoji hold for it.
    public static func lineage(of name: String) -> [String] {
        [name] + ancestors(of: name)
    }

    /// Every tag in `tags`, and every tag one of them sits inside, each once:
    /// the tags whose switches hold for a card with `tags`.
    public static func lineages(of tags: some Sequence<String>) -> Set<String> {
        Set(tags.flatMap(lineage(of:)))
    }

    /// Whether the tag `name` is `other`, or sits inside it at any depth.
    public static func isTag(_ name: String, within other: String) -> Bool {
        name == other || (name.hasPrefix(other + separator) && ancestors(of: name).contains(other))
    }

    /// The name of the tag `name` once the tag `old`, which it is or sits
    /// inside, is renamed `new`, as the tags inside a tag move along with
    /// it; or nil when `name` is neither `old` nor inside it.
    public static func renaming(_ name: String, from old: String, to new: String) -> String? {
        guard isTag(name, within: old) else {
            return nil
        }
        return new + name.dropFirst(old.count)
    }

    /// How the app writes the tag `name` where it stands alone, as in a
    /// card's tags or a menu: its levels joined by " › ", as in "economía ›
    /// Argentina", so that two Argentina under different parents never look
    /// the same.
    public static func shown(_ name: String) -> String {
        levels(of: name).joined(separator: shownSeparator)
    }

    /// How the app writes the tag `name` under `ancestor`, a tag it sits
    /// inside, as in a tree: the levels it has past `ancestor`'s, joined by
    /// " › ", which are its last level alone under its parent. Its whole
    /// name, as `shown(_:)` writes it, when `ancestor` is nil or `name`
    /// doesn't sit inside it.
    public static func shown(_ name: String, under ancestor: String?) -> String {
        guard let ancestor, name != ancestor, isTag(name, within: ancestor) else {
            return shown(name)
        }
        return levels(of: name).dropFirst(levels(of: ancestor).count).joined(separator: shownSeparator)
    }

    /// `names` in the order a tree lists them, each once: each tag right
    /// after the tag it sits inside and the tags inside the tags before it,
    /// and the tags at each level in alphabetical order as the Mac sorts
    /// text, so that children follow their parent.
    public static func sortedAsTree(_ names: some Sequence<String>) -> [String] {
        Set(names).map { (name: $0, levels: levels(of: $0)) }.sorted { comesBefore($0.levels, $1.levels) }.map(\.name)
    }

    /// Whether the tag with the levels `levels` comes before the one with
    /// `otherLevels` in a tree: level by level, in alphabetical order as the
    /// Mac sorts text, a parent before what sits inside it. Two levels the
    /// Mac sorts as one, such as "Economía" and "economía", are told apart by
    /// their characters, so that each one's children follow it.
    private static func comesBefore(_ levels: [String], _ otherLevels: [String]) -> Bool {
        for (level, otherLevel) in zip(levels, otherLevels) where level != otherLevel {
            switch level.localizedStandardCompare(otherLevel) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return level < otherLevel
            }
        }
        return levels.count < otherLevels.count
    }
}

/// A tag with the tags inside it, as a tree lists them.
public struct TagTree: Sendable, Equatable {
    /// The tag's whole name.
    public let name: String
    /// The tags right inside it, in the order a tree lists them.
    public let children: [TagTree]

    public init(name: String, children: [TagTree] = []) {
        self.name = name
        self.children = children
    }

    /// The trees `names` make, each tag once, under the nearest tag it sits
    /// inside among `names`, or at the top when there's none, in the order a
    /// tree lists them (`TagPath.sortedAsTree(_:)`). A parent missing from
    /// `names` is left out, so its children head trees of their own.
    public static func forest(of names: some Sequence<String>) -> [TagTree] {
        let sorted = TagPath.sortedAsTree(names)
        let all = Set(sorted)
        var childrenByParent: [String?: [String]] = [:]
        for name in sorted {
            childrenByParent[TagPath.ancestors(of: name).first(where: all.contains), default: []].append(name)
        }
        func tree(_ name: String) -> TagTree {
            TagTree(name: name, children: (childrenByParent[name] ?? []).map(tree))
        }
        return (childrenByParent[nil] ?? []).map(tree)
    }
}
