import FichaCore
import Foundation

// The Cards window's tags, which sit inside tags (ADR 0021) and which Lucas
// pins to the sidebar (ADR 0022): the sidebar's Tags section, with the pinned
// tags alone, in his order, which he reorders by dragging, pinning a tag he
// drags in from All Tags among them or onto All Tags…; a tag's context menu,
// one menu in the sidebar and in All Tags, which pins or unpins it, renames
// it, gives it a color or an emoji, and asks to delete it, for every tag
// selected in All Tags at once but for Rename… and Emoji…; and renaming a
// tag, which moves it too, with Rename…. A tag only labels its cards (ADR
// 0024): Set Aside and Prioritize are a deck's (`CardsWindowDecks.swift`),
// so no tag is grayed. All Tags
// itself, its tree, its drops and a tag's cards in its place, is in
// `CardsWindowAllTags.swift`. The rename sheet that Rename… opens renames a
// card type of the user's own too, so its entry and OK are with the emoji
// sheet's, in `CardsWindowState.swift`.

extension CardsWindowState {
    /// A tag as the sidebar lists it among the pinned tags.
    public struct PinnedTagRow: Sendable, Equatable, Identifiable {
        /// The tag, with what it has of its own and takes from the tags it
        /// sits inside.
        public let tag: CardTag

        public var id: String {
            tag.name
        }

        /// What its row offers: the tag's cards.
        public var item: SidebarItem {
            .cards(.tag(tag.name))
        }
    }

    /// The tags named `names` that the window offers, those it read last,
    /// whether All Tags lists them or its search leaves them out, each once,
    /// in the order a tree lists them, or in the order of `names` when
    /// `keepingTheirOrder` says so.
    func offeredTags(_ names: [String], keepingTheirOrder: Bool = false) -> [CardTag] {
        guard keepingTheirOrder else {
            let names = Set(names)
            return tags.filter { names.contains($0.name) }
        }
        return names.uniqued().compactMap { name in tags.first { $0.name == name } }
    }

    /// The names of the tags Lucas drags from All Tags that the window
    /// offers, in the order a tree lists them, or in the order he drags them
    /// when `keepingTheirOrder` says so: none while he drags none from it.
    func droppedTags(keepingTheirOrder: Bool = false) -> [String] {
        offeredTags(draggedTags ?? [], keepingTheirOrder: keepingTheirOrder).map(\.name)
    }

    /// What the context menu offers for the tags named `tags`, those of them
    /// the window offers, in the sidebar or in All Tags, as
    /// `tagsActedOn(clicking:)` says which; or nil when it offers none of
    /// them.
    public func menu(for tags: [String]) -> TagMenu? {
        let offered = offeredTags(tags)
        guard !offered.isEmpty else {
            return nil
        }
        let colors = Set(offered.map(\.color))
        return TagMenu(
            tags: offered.map(\.name), isPinned: offered.allSatisfy(\.isPinned),
            colorItems: ([nil] + TagColor.allCases).map { ColorItem(color: $0, isTicked: colors == [$0]) })
    }

    /// Chooses Pin to Sidebar in the context menu of `tags`, in All Tags or
    /// the sidebar, which pins those that aren't pinned after the pinned
    /// tags, in their order, or Unpin from Sidebar while all are pinned, and
    /// reads the cards again, or records why it couldn't.
    public mutating func choosePin(on tags: [String]) {
        guard let menu = menu(for: tags) else { return }
        setPinned(!menu.isPinned, of: menu.tags)
    }

    /// Chooses `color` in the Color submenu of `tags`, or None when it's nil:
    /// gives them that color, or takes their colors away, and reads the
    /// cards again, or records why it couldn't.
    public mutating func chooseColor(_ color: TagColor?, on tags: [String]) {
        guard let menu = menu(for: tags) else { return }
        change(menu.tags, as: FailedAction.setColor(tag:)) { engine throws(EngineError) in
            try engine.setColor(color, of: menu.tags)
        }
    }

    /// Pins `tags`, those that aren't pinned after the pinned tags, in their
    /// order, or unpins them when `isPinned` is false, and reads the cards
    /// again, or records why it couldn't. Unpinning the tag the sidebar chose
    /// keeps its cards listed, as All Tags lists a tag's cards in its place,
    /// with the tag selected there and its parents open, so that the sidebar
    /// shows All Tags…, where the tag is now, and Back goes to it.
    mutating func setPinned(_ isPinned: Bool, of tags: [String]) {
        if isPinned {
            change(tags, as: FailedAction.pin(tag:)) { engine throws(EngineError) in try engine.pin(tags) }
            return
        }
        change(
            tags, as: FailedAction.unpin(tag:), followedBy: { $0.showUnpinnedChosenTag(among: tags) },
            { engine throws(EngineError) in try engine.unpin(tags) })
    }

    /// Lists the cards of the tag the sidebar chose, when it's one of
    /// `unpinned`, in All Tags' place, with the tag selected there and its
    /// parents open, as `setPinned(_:of:)` says.
    private mutating func showUnpinnedChosenTag(among unpinned: [String]) {
        guard case .cards(.tag(let chosen)) = sidebarItem, unpinned.contains(chosen) else { return }
        sidebarItem = .allTags
        tagShownFromAllTags = chosen
        allTagsSearch = ""
        selectedTags = [chosen]
        openTags.formUnion(TagPath.ancestors(of: chosen))
    }

    /// Does `work`, the engine's part of an action on the tags named `tags`,
    /// then `followUp`, and reads the cards again; or records why it
    /// couldn't, as `action` names the action after the first of them.
    /// Whether it did: never when `tags` is empty.
    @discardableResult
    mutating func change(
        _ tags: [String], as action: (String) -> FailedAction, followedBy followUp: (inout Self) -> Void = { _ in },
        _ work: (Engine) throws(EngineError) -> Void
    ) -> Bool {
        guard let first = tags.first, perform(action(first), work) else {
            return false
        }
        followUp(&self)
        read(on: ladder)
        return true
    }

    /// Asks which emoji the tag named `tag` gets, in the emoji sheet, after
    /// Emoji… in its context menu.
    public mutating func askForEmoji(on tag: String) {
        guard let tag = tags.first(where: { $0.name == tag }) else { return }
        question = .emoji(tag)
    }

    /// Gives `tag`, the tag the window asks about, `emoji`, or takes its
    /// emoji away when it's nil, and reads the cards again; or records why it
    /// couldn't. Whether it did.
    mutating func setEmoji(_ emoji: Emoji?, of tag: CardTag) -> Bool {
        change([tag.name], as: FailedAction.setEmoji(tag:)) { engine throws(EngineError) in
            try engine.setEmoji(emoji, of: tag.name)
        }
    }

    /// Starts dragging the tags named `names` from All Tags, as Lucas drags
    /// their rows, which a drop in the sidebar pins, or in All Tags moves,
    /// until he lets go of them (`stopDraggingTags()`).
    public mutating func startDraggingTags(_ names: [String]) {
        draggedTags = names
    }

    /// Lucas let go of the tags he dragged from All Tags, wherever he
    /// dropped them, in the window or out of it, after the window took the
    /// drop, if it did.
    public mutating func stopDraggingTags() {
        draggedTags = nil
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
        let index = Self.index(of: destination, in: pinned, apartFrom: moving)
        change(moving, as: FailedAction.reorderPinned(tag:)) { engine throws(EngineError) in
            try engine.movePinnedTags(moving, to: index)
        }
    }

    /// Pins the tags Lucas drags from All Tags (`draggedTags`), which he
    /// dropped among the sidebar's pinned tags before the one at `offset`, or
    /// after them all when it's past them, in the order he drags them, in
    /// one go; a pinned one moves there. Then it reads the cards again.
    /// Whether it took the drop: never while he drags none from All Tags, as
    /// when he drops text dragged in from another app or from elsewhere in
    /// Ficha, even text that names a tag, nor when the engine couldn't pin
    /// them, which it records.
    @discardableResult
    public mutating func pinDraggedTags(at offset: Int) -> Bool {
        let dropped = droppedTags(keepingTheirOrder: true)
        let index = Self.index(of: offset, in: pinnedTags.map(\.id), apartFrom: dropped)
        return change(dropped, as: FailedAction.pin(tag:)) { engine throws(EngineError) in
            try engine.pin(dropped, at: index)
        }
    }

    /// Drops the tags Lucas drags from All Tags on the sidebar's All Tags…:
    /// pins them after the pinned tags, as a drop right above All Tags…
    /// would, which is where he drops one while none is pinned, as the
    /// pinned tags then have no rows to drop between. Whether it took the
    /// drop, as `pinDraggedTags(at:)` says.
    public mutating func dropDraggedTagsOnAllTags() -> Bool {
        pinDraggedTags(at: pinnedTags.count)
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

    /// Renames the tag `tag` to `name`, and every tag inside it, for
    /// `action`, and reads the cards again, the window following it to its
    /// new name (`follow(_:)`); or records why it couldn't. Whether it did.
    mutating func renameTag(_ tag: String, to name: String, as action: FailedAction) -> Bool {
        var renamed = name
        let done = perform(action) { engine throws(EngineError) in
            renamed = try engine.renameTag(tag, to: name)
        }
        guard done else {
            return false
        }
        follow([.rename(tag, to: renamed)])
        read(on: ladder)
        return true
    }

    /// Points what the window holds of tags at their names after `renames`,
    /// made in that order: the tag the sidebar chose, the one whose cards
    /// All Tags lists in its place, and All Tags' selection and open
    /// parents, each when it's a tag renamed or inside one.
    mutating func follow(_ renames: [TagEdit]) {
        func renamed(_ name: String) -> String {
            renames.reduce(name) { name, edit in edit.name(of: name) ?? name }
        }
        if case .cards(.tag(let chosen)) = sidebarItem {
            sidebarItem = .cards(.tag(renamed(chosen)))
        }
        tagShownFromAllTags = tagShownFromAllTags.map(renamed)
        selectedTags = Set(selectedTags.map(renamed))
        openTags = Set(openTags.map(renamed))
    }
}
