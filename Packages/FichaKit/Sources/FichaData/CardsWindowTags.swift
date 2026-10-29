import FichaCore
import Foundation

// The Cards window's tags, which sit inside tags (ADR 0021): the sidebar's
// Tags section, a tree of the tags that aren't set aside, and its Set Aside
// section, and renaming or moving a tag, with Rename… in its context menu or
// by dragging it onto another tag or onto the Tags section's title.

extension CardsWindowState {
    /// A tag as the sidebar lists it, in its Tags section or its Set Aside
    /// section, with the tags inside it, which a disclosure triangle shows.
    public struct SidebarTag: Sendable, Equatable, Identifiable {
        /// The tag, with what it has of its own and takes from the tags it
        /// sits inside.
        public let tag: CardTag
        /// What its row says, without its emoji: its last level, or, heading
        /// the Set Aside section inside a tag that isn't set aside, its whole
        /// name, written with " › ", as in "economía › Argentina".
        public let title: String
        /// The tags right inside it, in the order a tree lists them.
        public let children: [SidebarTag]

        public var id: String {
            tag.name
        }
    }

    /// What OK in the rename sheet makes of what its field holds.
    public enum RenameEntry: Sendable, Equatable {
        /// The tag's new whole name, its levels cleaned up, or the type's
        /// name, without the spaces around it.
        case name(String)
        /// A name OK refuses, and why, for the sheet to say: a blank one, or
        /// one inside the tag itself; or a type's name of one of the four
        /// Ficha comes with, or another user type's.
        case refused(EngineError)
    }

    /// The sidebar's two sections out of `tags`, the tags it offers, in the
    /// order a tree lists them: the Tags section, with the tags that aren't
    /// set aside, on their own or inside a tag that is, and the Set Aside
    /// section, with the others. Each row is named by the levels it has past
    /// the tag it's listed under, its last level under its parent, and its
    /// whole name at the top.
    static func sections(of tags: [CardTag]) -> (tags: [SidebarTag], setAside: [SidebarTag]) {
        let byName = Dictionary(tags.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let setAside = Set(tags.filter(\.isSetAside).map(\.name))
        let isSetAside = { (name: String) in TagPath.lineage(of: name).contains(where: setAside.contains) }
        /// The row of the tag at the top of `tree`, listed under `parent`.
        func row(_ tree: TagTree, under parent: String?) -> SidebarTag {
            SidebarTag(
                tag: byName[tree.name] ?? CardTag(name: tree.name), title: TagPath.shown(tree.name, under: parent),
                children: tree.children.map { row($0, under: tree.name) })
        }
        let names = tags.map(\.name)
        return (
            TagTree.forest(of: names.filter { !isSetAside($0) }).map { row($0, under: nil) },
            TagTree.forest(of: names.filter(isSetAside)).map { row($0, under: nil) }
        )
    }

    /// Asks which name the sidebar's tag named `tag` gets, in the rename
    /// sheet, after Rename… in its context menu.
    public mutating func askToRename(_ tag: String) {
        guard let tag = tags.first(where: { $0.name == tag }) else { return }
        question = .rename(tag)
    }

    /// What OK in the rename sheet makes of `text`, what its field holds: for
    /// the tag the window asks about, the tag's new whole name, or a refusal
    /// of a blank name or one inside the tag itself; for the user type it
    /// asks about, the type's name, or a refusal of a blank name, a name of
    /// one of the four Ficha comes with, or another user type's; each as the
    /// engine refuses them. Nil while the window asks about no name.
    public func renameEntry(_ text: String) -> RenameEntry? {
        switch question {
        case .rename(let tag):
            do throws(EngineError) {
                return .name(try checkedName(renaming: tag.name, to: text))
            } catch {
                return .refused(error)
            }
        case .renameType(let type):
            return typeNameEntry(text, renaming: type.id)
        default:
            return nil
        }
    }

    /// Chooses OK in the rename sheet, whose field holds `text`: renames the
    /// tag the window asks about, and every tag inside it, as
    /// `Engine.renameTag(_:to:)` does, or the user type it asks about, and
    /// reads the cards again, the sidebar following the tag or the type it
    /// chose to its new name; or records why it couldn't and goes on asking.
    /// While OK refuses `text`, it does nothing, and the sheet says why.
    public mutating func chooseNewName(_ text: String) {
        guard case .name(let name)? = renameEntry(text) else { return }
        let done: Bool
        switch question {
        case .rename(let tag): done = rename(tag.name, to: name, as: .rename(tag: tag.name))
        case .renameType(let type): done = renameType(type, to: name)
        default: return
        }
        if done {
            question = nil
        }
    }

    /// Drops the sidebar's tag named `tag` on its tag named `target`, as
    /// Lucas drags it: moves it inside `target`, renaming it
    /// `<target>::<its last level>`, with every tag inside it, and reads the
    /// cards again. Whether it took the drop: never when `tag` isn't a tag the
    /// sidebar lists, as a word dragged from elsewhere, when `target` is the
    /// tag itself or a tag inside it, or when `tag` already sits right inside
    /// `target`; nor when the engine couldn't, which it records.
    public mutating func drop(_ tag: String, onto target: String) -> Bool {
        guard tags.contains(where: { $0.name == target }), !TagPath.isTag(target, within: tag) else {
            return false
        }
        return move(tag, to: target + TagPath.separator + TagPath.lastLevel(of: tag))
    }

    /// Drops the sidebar's tag named `tag` on the Tags section's title, as
    /// Lucas drags it: takes it to the top, renaming it its last level, with
    /// every tag inside it, and reads the cards again. Whether it took the
    /// drop: never when `tag` isn't a tag the sidebar lists or is at the top
    /// already, nor when the engine couldn't, which it records.
    public mutating func dropOnTagsTitle(_ tag: String) -> Bool {
        move(tag, to: TagPath.lastLevel(of: tag))
    }

    /// Moves the sidebar's tag named `tag` to the new whole name `name`, as a
    /// drop does: whether it did, which it never does to a tag the sidebar
    /// doesn't list or to the name it has.
    private mutating func move(_ tag: String, to name: String) -> Bool {
        guard tags.contains(where: { $0.name == tag }), name != tag else {
            return false
        }
        return rename(tag, to: name, as: .move(tag: tag))
    }

    /// Renames the tag `tag` to `name`, and every tag inside it, for
    /// `action`, and reads the cards again, the sidebar following the tag it
    /// chose, when it's `tag` or inside it, to its new name; or records why
    /// it couldn't. Whether it did.
    private mutating func rename(_ tag: String, to name: String, as action: FailedAction) -> Bool {
        var renamed = name
        let done = perform(action) { engine throws(EngineError) in
            renamed = try engine.renameTag(tag, to: name)
        }
        guard done else {
            return false
        }
        if case .cards(.tag(let chosen)) = sidebarItem, let moved = TagPath.renaming(chosen, from: tag, to: renamed) {
            sidebarItem = .cards(.tag(moved))
        }
        read(on: ladder)
        return true
    }
}
