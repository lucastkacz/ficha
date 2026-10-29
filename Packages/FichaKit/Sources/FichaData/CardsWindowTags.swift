import FichaCore
import Foundation

// The Cards window's tags, which sit inside tags (ADR 0021) and which Lucas
// pins to the sidebar (ADR 0022): the sidebar's Tags section, with the pinned
// tags alone, in his order, which he pins and unpins from a tag's context
// menu and reorders by dragging, pinning a tag he drags in from All Tags
// among them or onto All Tags…; All Tags, a tree of every tag that isn't set
// aside and its Set Aside section, which the menu bar's All Tags… opens too;
// and renaming or moving a tag, with Rename… in its context menu or by
// dragging it, in All Tags, onto another tag or onto its Tags section's
// title. The rename sheet that Rename… opens renames a card type of the
// user's own too, so its entry and OK are with the emoji sheet's, in
// `CardsWindowState.swift`.

extension CardsWindowState {
    /// A tag as the window lists it: among the sidebar's pinned tags, or in
    /// All Tags, in its tree or its Set Aside section, with the tags inside
    /// it, which a disclosure triangle shows.
    public struct ListedTag: Sendable, Equatable, Identifiable {
        /// The tag, with what it has of its own and takes from the tags it
        /// sits inside.
        public let tag: CardTag
        /// What its row says, without its emoji: its whole name, written
        /// with " › ", as in "economía › Argentina", among the pinned tags
        /// and at the top of All Tags' tree or its Set Aside section, and its
        /// last level under its parent.
        public let title: String
        /// Whether its row is grayed: among the pinned tags, while its cards
        /// are out of Lucas's reviews, as it's set aside on its own or sits
        /// inside a tag that is; never in All Tags, whose Set Aside section
        /// holds those.
        public let isGrayed: Bool
        /// The tags right inside it, in the order a tree lists them: none
        /// among the pinned tags.
        public let children: [ListedTag]

        public var id: String {
            tag.name
        }
    }

    /// The sidebar's rows of `pinned`, the pinned tags in Lucas's order, each
    /// named by its whole path and grayed when it's set aside, on its own or
    /// inside one of `tags`, every tag the window offers, that is.
    static func pinnedRows(of pinned: [CardTag], among tags: [CardTag]) -> [ListedTag] {
        let isSetAside = setAside(among: tags)
        return pinned.map {
            ListedTag(tag: $0, title: TagPath.shown($0.name), isGrayed: isSetAside($0.name), children: [])
        }
    }

    /// All Tags' two parts out of `tags`, every tag the window offers, in the
    /// order a tree lists them: the tree, with the tags that aren't set
    /// aside, on their own or inside a tag that is, and the Set Aside
    /// section, with the others, none grayed. Each row is named by the
    /// levels it has past the tag it's listed under, its last level under its
    /// parent, and its whole name at the top.
    static func allTagsTree(of tags: [CardTag]) -> (tree: [ListedTag], setAside: [ListedTag]) {
        let byName = Dictionary(tags.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let isSetAside = setAside(among: tags)
        /// The row of the tag at the top of `tree`, listed under `parent`.
        func row(_ tree: TagTree, under parent: String?) -> ListedTag {
            ListedTag(
                tag: byName[tree.name] ?? CardTag(name: tree.name), title: TagPath.shown(tree.name, under: parent),
                isGrayed: false, children: tree.children.map { row($0, under: tree.name) })
        }
        let names = tags.map(\.name)
        return (
            TagTree.forest(of: names.filter { !isSetAside($0) }).map { row($0, under: nil) },
            TagTree.forest(of: names.filter(isSetAside)).map { row($0, under: nil) }
        )
    }

    /// Whether the tag with a name is set aside, on its own or inside a tag
    /// that is, among `tags`, which hold every set-aside tag, as
    /// `CardStanding` picks a card's set-aside tags.
    private static func setAside(among tags: [CardTag]) -> (String) -> Bool {
        let setAside = Set(tags.filter(\.isSetAside).map(\.name))
        return { name in !CardStanding.setAsideTags(of: [name], among: setAside).isEmpty }
    }

    /// Chooses All Tags, as All Tags… in the menu bar's Prioritize submenu
    /// asks, unless Lucas is editing a card or a capture, while the sidebar
    /// waits for him.
    public mutating func showAllTags() {
        guard editing == nil else { return }
        choose(.allTags)
    }

    /// Chooses Pin to Sidebar in the context menu of the tag named `tag`, in
    /// All Tags or the sidebar, which pins it after the pinned tags, or
    /// Unpin from Sidebar while it's pinned, and reads the cards again, or
    /// records why it couldn't.
    public mutating func choosePin(on tag: String) {
        guard let menu = menu(for: tag) else { return }
        let done =
            if menu.isPinned {
                perform(.unpin(tag: tag)) { engine throws(EngineError) in try engine.unpin(tag) }
            } else {
                perform(.pin(tag: tag)) { engine throws(EngineError) in try engine.pin(tag) }
            }
        if done {
            read(on: ladder)
        }
    }

    /// Moves the sidebar's pinned tags at `offsets` to before the one at
    /// `destination`, or after them all when it's past them, as Lucas drags
    /// them, each offset and `destination` counted in the pinned tags as
    /// they were, as SwiftUI's `onMove` gives them, in one go; then reads the
    /// cards again, or records why it couldn't, as when one of them was
    /// unpinned meanwhile. The tags it moves keep their order.
    public mutating func movePinnedTags(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let pinned = pinnedTags.map(\.id)
        let moving = offsets.filter(pinned.indices.contains).map { pinned[$0] }
        guard let first = moving.first else { return }
        let index = Self.index(of: destination, in: pinned, apartFrom: moving)
        let done = perform(.reorderPinned(tag: first)) { engine throws(EngineError) in
            try engine.movePinnedTags(moving, to: index)
        }
        if done {
            read(on: ladder)
        }
    }

    /// Pins the tags named `names`, which Lucas dropped among the sidebar's
    /// pinned tags before the one at `offset`, or after them all when it's
    /// past them, as he drags them in from All Tags, in that order there, in
    /// one go; a pinned one moves there. Then it reads the cards again.
    /// Whether it took the drop: never when none of `names` is a tag the
    /// window offers, as a word dragged from elsewhere, nor when the engine
    /// couldn't pin them, which it records.
    @discardableResult
    public mutating func pinDroppedTags(_ names: [String], at offset: Int) -> Bool {
        let dropped = names.filter { name in tags.contains { $0.name == name } }.uniqued()
        guard let first = dropped.first else {
            return false
        }
        let index = Self.index(of: offset, in: pinnedTags.map(\.id), apartFrom: dropped)
        let done = perform(.pin(tag: first)) { engine throws(EngineError) in try engine.pin(dropped, at: index) }
        if done {
            read(on: ladder)
        }
        return done
    }

    /// Drops the tag named `tag`, which Lucas drags in from All Tags, on the
    /// sidebar's All Tags…: pins it after the pinned tags, as a drop right
    /// above All Tags… would, which is where he drops one while none is
    /// pinned, as the pinned tags then have no rows to drop between. Whether
    /// it took the drop, as `pinDroppedTags(_:at:)` says.
    public mutating func dropOnAllTags(_ tag: String) -> Bool {
        pinDroppedTags([tag], at: pinnedTags.count)
    }

    /// The place before the tag at `offset` in `pinned`, the pinned tags as
    /// SwiftUI counts them, among those of them that aren't in `moving`, as
    /// the engine counts it: how many of those come before it.
    private static func index(of offset: Int, in pinned: [String], apartFrom moving: [String]) -> Int {
        pinned.prefix(max(offset, 0)).filter { !moving.contains($0) }.count
    }

    /// Asks which name the tag named `tag` gets, in the rename sheet, after
    /// Rename… in its context menu.
    public mutating func askToRename(_ tag: String) {
        guard let tag = tags.first(where: { $0.name == tag }) else { return }
        question = .renameTag(tag)
    }

    /// `text`, what the rename sheet's field holds for the tag `tag`, as OK
    /// takes it: the tag's new whole name, its levels cleaned up, or a
    /// refusal of a blank name or one inside the tag itself, as the engine
    /// refuses them.
    func tagNameEntry(_ text: String, renaming tag: String) -> RenameEntry {
        do throws(EngineError) {
            return .name(try checkedTagName(renaming: tag, to: text))
        } catch {
            return .refused(error)
        }
    }

    /// Drops All Tags' tag named `tag` on its tag named `target`, as Lucas
    /// drags it: moves it inside `target`, renaming it
    /// `<target>::<its last level>`, with every tag inside it, and reads the
    /// cards again. Whether it took the drop: never when `tag` isn't a tag
    /// the window offers, as a word dragged from elsewhere, when `target` is
    /// the tag itself or a tag inside it, or when `tag` already sits right
    /// inside `target`; nor when the engine couldn't, which it records.
    public mutating func drop(_ tag: String, onto target: String) -> Bool {
        guard tags.contains(where: { $0.name == target }), !TagPath.isTag(target, within: tag) else {
            return false
        }
        return move(tag, to: target + TagPath.separator + TagPath.lastLevel(of: tag))
    }

    /// Drops All Tags' tag named `tag` on its Tags section's title, as Lucas
    /// drags it: takes it to the top, renaming it its last level, with every
    /// tag inside it, and reads the cards again. Whether it took the drop:
    /// never when `tag` isn't a tag the window offers or is at the top
    /// already, nor when the engine couldn't, which it records.
    public mutating func dropOnTagsTitle(_ tag: String) -> Bool {
        move(tag, to: TagPath.lastLevel(of: tag))
    }

    /// Moves the tag named `tag` to the new whole name `name`, as a drop
    /// does: whether it did, which it never does to a tag the window doesn't
    /// offer or to the name it has.
    private mutating func move(_ tag: String, to name: String) -> Bool {
        guard tags.contains(where: { $0.name == tag }), name != tag else {
            return false
        }
        return renameTag(tag, to: name, as: .move(tag: tag))
    }

    /// Renames the tag `tag` to `name`, and every tag inside it, for
    /// `action`, and reads the cards again, the sidebar following the tag it
    /// chose, when it's `tag` or inside it, to its new name; or records why
    /// it couldn't. Whether it did.
    mutating func renameTag(_ tag: String, to name: String, as action: FailedAction) -> Bool {
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
