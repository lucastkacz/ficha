import FichaCore
import Foundation

// The Cards window's tags, which sit inside tags (ADR 0021) and which Lucas
// pins to the sidebar (ADR 0022): the sidebar's Tags section, with the pinned
// tags alone, in his order, which he reorders by dragging, pinning a tag he
// drags in from All Tags among them or onto All Tags…; a tag's context menu,
// one menu in the sidebar and in All Tags, which pins or unpins it, renames
// it, gives it a color or an emoji, sets it aside or prioritizes it, and asks
// to delete it, for every tag selected in All Tags at once but for Rename…
// and Emoji…; and renaming a tag, which moves it too, with Rename…. All Tags
// itself, its tree, its drops and a tag's cards in its place, is in
// `CardsWindowAllTags.swift`. The rename sheet that Rename… opens renames a
// card type of the user's own too, so its entry and OK are with the emoji
// sheet's, in `CardsWindowState.swift`.

extension CardsWindowState {
    /// A tag as the sidebar lists it among the pinned tags.
    public struct ListedTag: Sendable, Equatable, Identifiable {
        /// The tag, with what it has of its own and takes from the tags it
        /// sits inside.
        public let tag: CardTag
        /// What its row says, without its emoji: its whole name, written
        /// with " › ", as in "economía › Argentina".
        public let title: String
        /// Whether its row is grayed: while its cards are out of Lucas's
        /// reviews, as it's set aside on its own or sits inside a tag that
        /// is.
        public let isGrayed: Bool

        public var id: String {
            tag.name
        }
    }

    /// The sidebar's rows of `pinned`, the pinned tags in Lucas's order, each
    /// named by its whole path and grayed when it's set aside, on its own or
    /// inside one of `tags`, every tag the window offers, that is.
    static func pinnedRows(of pinned: [CardTag], among tags: [CardTag]) -> [ListedTag] {
        let isSetAside = setAside(among: tags)
        return pinned.map { ListedTag(tag: $0, title: TagPath.shown($0.name), isGrayed: isSetAside($0.name)) }
    }

    /// Whether the tag with a name is set aside, on its own or inside a tag
    /// that is, among `tags`, which hold every set-aside tag, as
    /// `CardStanding` picks a card's set-aside tags.
    static func setAside(among tags: [CardTag]) -> (String) -> Bool {
        let setAside = Set(tags.filter(\.isSetAside).map(\.name))
        return { name in !CardStanding.setAsideTags(of: [name], among: setAside).isEmpty }
    }

    /// The tags named `names` that the window offers, each once, in the order
    /// a tree lists them.
    func listedTags(_ names: [String]) -> [CardTag] {
        let names = Set(names)
        return tags.filter { names.contains($0.name) }
    }

    /// Chooses All Tags, as All Tags… in the menu bar's Prioritize submenu
    /// asks, unless Lucas is editing a card or a capture, while the sidebar
    /// waits for him.
    public mutating func showAllTags() {
        guard editing == nil else { return }
        choose(.allTags)
    }

    /// What the context menu offers for the tags named `tags`, those of them
    /// the window lists, in the sidebar or in All Tags, as
    /// `tagsActedOn(clicking:)` says which; or nil when it lists none of
    /// them.
    public func menu(for tags: [String]) -> TagMenu? {
        let listed = listedTags(tags)
        guard !listed.isEmpty else {
            return nil
        }
        let colors = Set(listed.map(\.color))
        return TagMenu(
            tags: listed.map(\.name), isPinned: listed.allSatisfy(\.isPinned),
            isSetAsideTicked: listed.allSatisfy(\.isSetAside), isPriorityTicked: listed.allSatisfy(\.isPriority),
            canPrioritize: !listed.contains(where: \.isSetAside),
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

    /// Chooses Set Aside in the context menu of `tags`: sets them aside, or
    /// undoes it while it's ticked, and reads the cards again, or records why
    /// it couldn't.
    public mutating func chooseSetAside(on tags: [String]) {
        guard let menu = menu(for: tags) else { return }
        setSetAside(!menu.isSetAsideTicked, of: menu.tags)
    }

    /// Chooses Prioritize in the context menu of `tags`, while it's on: makes
    /// them priority tags, or no longer, while it's ticked, and reads the
    /// cards again, or records why it couldn't.
    public mutating func choosePriority(on tags: [String]) {
        guard let menu = menu(for: tags), menu.canPrioritize else { return }
        setPriority(!menu.isPriorityTicked, of: menu.tags)
    }

    /// Chooses `color` in the Color submenu of `tags`, or None when it's nil:
    /// gives them that color, or takes their colors away, and reads the
    /// cards again, or records why it couldn't.
    public mutating func chooseColor(_ color: TagColor?, on tags: [String]) {
        guard let menu = menu(for: tags), let first = menu.tags.first else { return }
        let done = perform(.setColor(tag: first)) { engine throws(EngineError) in
            try engine.setColor(color, of: menu.tags)
        }
        if done {
            read(on: ladder)
        }
    }

    /// Pins `tags`, those that aren't pinned after the pinned tags, in their
    /// order, or unpins them when `isPinned` is false, and reads the cards
    /// again, or records why it couldn't. Unpinning the tag the sidebar chose
    /// keeps its cards listed, as All Tags lists a tag's cards in its place,
    /// with the tag selected there and its parents open, so that the sidebar
    /// shows All Tags…, where the tag is now, and Back goes to it.
    mutating func setPinned(_ isPinned: Bool, of tags: [String]) {
        guard let first = tags.first else { return }
        let done =
            if isPinned {
                perform(.pin(tag: first)) { engine throws(EngineError) in try engine.pin(tags) }
            } else {
                perform(.unpin(tag: first)) { engine throws(EngineError) in try engine.unpin(tags) }
            }
        guard done else { return }
        if !isPinned, case .cards(.tag(let chosen)) = sidebarItem, tags.contains(chosen) {
            sidebarItem = .allTags
            tagShownFromAllTags = chosen
            allTagsSearch = ""
            selectedTags = [chosen]
            openTags.formUnion(TagPath.ancestors(of: chosen))
        }
        read(on: ladder)
    }

    /// Sets `tags` aside, or stops setting them aside when `isSetAside` is
    /// false, and reads the cards again, or records why it couldn't.
    mutating func setSetAside(_ isSetAside: Bool, of tags: [String]) {
        guard let first = tags.first else { return }
        let done =
            if isSetAside {
                perform(.setAside(tag: first)) { engine throws(EngineError) in try engine.setAside(tags) }
            } else {
                perform(.stopSettingAside(tag: first)) { engine throws(EngineError) in
                    try engine.stopSettingAside(tags)
                }
            }
        if done {
            read(on: ladder)
        }
    }

    /// Makes `tags` priority tags, or no longer when `isPriority` is false,
    /// and reads the cards again, or records why it couldn't, as when one of
    /// them was set aside meanwhile.
    mutating func setPriority(_ isPriority: Bool, of tags: [String]) {
        guard let first = tags.first else { return }
        let action: FailedAction = isPriority ? .prioritize(tag: first) : .stopPrioritizing(tag: first)
        let done = perform(action) { engine throws(EngineError) in try engine.setPriority(isPriority, of: tags) }
        if done {
            read(on: ladder)
        }
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
        let done = perform(.setEmoji(tag: tag.name)) { engine throws(EngineError) in
            try engine.setEmoji(emoji, of: tag.name)
        }
        if done {
            read(on: ladder)
        }
        return done
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

    /// Drops the tags named `names`, which Lucas drags in from All Tags, on
    /// the sidebar's All Tags…: pins them after the pinned tags, as a drop
    /// right above All Tags… would, which is where he drops one while none is
    /// pinned, as the pinned tags then have no rows to drop between. Whether
    /// it took the drop, as `pinDroppedTags(_:at:)` says.
    public mutating func dropOnAllTags(_ names: [String]) -> Bool {
        pinDroppedTags(names, at: pinnedTags.count)
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
