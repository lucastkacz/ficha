import FichaCore
import Foundation

// All Tags (ADR 0022), where the Cards window's table was: every tag as a
// tree, each with how many cards it holds and how many are due, and whether
// it's pinned, a priority tag or set aside, a set-aside tag grayed in its
// place with the tags inside it. Lucas sorts each level by a column, narrows
// the tree with the search field, opens its parents, which start closed, and
// selects several tags, which a tag's menu then acts on at once
// (`CardsWindowTags.swift`). He drags tags onto another to move them inside
// it, or between two rows to move them to that level; deletes tags and clears
// the unused ones, both after a question with what they do, since the Cards
// window has no undo; and lists a tag's cards in All Tags' place, until Back
// brings All Tags back as he left it.

extension CardsWindowState {
    /// A tag in All Tags' tree, with the tags right inside it, which a
    /// disclosure triangle shows.
    public struct AllTagsRow: Sendable, Equatable, Identifiable {
        /// The tag, with what it has of its own and takes from the tags it
        /// sits inside: its Pinned, Priority and Set Aside checkboxes show
        /// its own.
        public let tag: CardTag
        /// What its row says, without its emoji: its last level under its
        /// parent, and its whole name at the top, written with " › ".
        public let title: String
        /// How many cards it lists and how many of those are due, counting
        /// the tags inside it: its Cards and Due columns.
        public let counts: TagCounts
        /// Whether its row is grayed: while its cards are out of Lucas's
        /// reviews, as it's set aside on its own or sits inside a tag that
        /// is.
        public let isGrayed: Bool
        /// Whether its Priority checkbox is on: not while it's set aside, on
        /// its own or inside a tag that is, as the menu bar's Prioritize
        /// submenu leaves it out, unless it's a priority tag, to untick.
        public let canPrioritize: Bool
        /// The tags right inside it that All Tags lists, in its order.
        public let children: [AllTagsRow]

        public var id: String {
            tag.name
        }

        /// Whether its `checkbox` is ticked: whether the tag is pinned, a
        /// priority tag or set aside, of its own.
        public func isTicked(_ checkbox: AllTagsCheckbox) -> Bool {
            switch checkbox {
            case .pinned: tag.isPinned
            case .priority: tag.isPriority
            case .setAside: tag.isSetAside
            }
        }
    }

    /// A column of All Tags, whose title sorts each level of its tree by it.
    public enum AllTagsColumn: Sendable, Hashable, CaseIterable {
        /// The tag, alphabetically.
        case tag
        /// How many cards it holds.
        case cards
        /// How many of those are due.
        case due
        /// One of the checkboxes, the ticked ones apart from the others.
        case checkbox(AllTagsCheckbox)

        /// Every column, in All Tags' order: the tag, Cards, Due, then
        /// Pinned, Priority and Set Aside.
        public static let allCases: [AllTagsColumn] =
            [.tag, .cards, .due] + AllTagsCheckbox.allCases.map(Self.checkbox)

        /// Whether a first click on its title sorts it descending, so that
        /// the tags with the most cards, or the most due cards, come first,
        /// and the ticked ones: all but the tag, which sorts alphabetically.
        public var sortsDescendingFirst: Bool {
            self != .tag
        }

        /// What it sorts `row` by, for every column but the tag, which keeps
        /// the tree's alphabetical order.
        fileprivate func value(of row: AllTagsRow) -> Int {
            switch self {
            case .tag: 0
            case .cards: row.counts.cards
            case .due: row.counts.due
            case .checkbox(let checkbox): row.isTicked(checkbox) ? 1 : 0
            }
        }
    }

    /// How All Tags sorts each level of its tree: by a column, ascending or
    /// descending, and alphabetically between two tags it puts alike.
    public struct AllTagsSort: Sendable, Equatable {
        /// The column it sorts by.
        public let column: AllTagsColumn
        /// Whether it's ascending: the fewest first, the unticked first, or
        /// from A to Z.
        public let isAscending: Bool

        public init(column: AllTagsColumn, isAscending: Bool) {
            self.column = column
            self.isAscending = isAscending
        }

        /// From A to Z, as All Tags opens.
        public static let alphabetical = AllTagsSort(column: .tag, isAscending: true)

        /// `rows`, one level of the tree in alphabetical order, in this
        /// order.
        fileprivate func sorted(_ rows: [AllTagsRow]) -> [AllTagsRow] {
            guard column != .tag else {
                return isAscending ? rows : rows.reversed()
            }
            return rows.enumerated()
                .sorted { row, other in
                    let (value, otherValue) = (column.value(of: row.element), column.value(of: other.element))
                    guard value != otherValue else {
                        return row.offset < other.offset
                    }
                    return isAscending ? value < otherValue : value > otherValue
                }
                .map(\.element)
        }
    }

    /// A checkbox of All Tags' rows, in its order.
    public enum AllTagsCheckbox: Sendable, Hashable, CaseIterable {
        case pinned
        case priority
        case setAside
    }

    /// What Lucas can do in All Tags with the tags selected there, beyond a
    /// tag's menu.
    public enum TagAction: Sendable, Hashable {
        /// List the cards of the one tag selected, in All Tags' place.
        case showCards
        /// Delete the selected tags, asking first.
        case delete
        /// Delete every tag no card carries, asking first.
        case clearUnused
    }

    /// The group of cards the table lists: the one the sidebar chose, or the
    /// tag whose cards All Tags lists in its place; nil while it lists the
    /// inbox or All Tags' tree.
    public var listedGroup: CardGroup? {
        switch sidebarItem {
        case .cards(let group): group
        case .allTags: tagShownFromAllTags.map(CardGroup.tag)
        case .inbox: nil
        }
    }

    /// The tag whose cards All Tags lists in its place, which the window's
    /// title names, until Back.
    public var shownTag: CardTag? {
        tagShownFromAllTags.flatMap { shown in tags.first { $0.name == shown } }
    }

    /// Whether Back, in the toolbar or ⌘[, goes back to All Tags: while it
    /// lists a tag's cards in its place, and Lucas isn't editing one.
    public var canGoBack: Bool {
        tagShownFromAllTags != nil && editing == nil
    }

    /// All Tags' rows out of every tag, read with its counts on the window's
    /// ladder, as its search and its sort leave them.
    func allTagsRows() throws(EngineError) -> [AllTagsRow] {
        Self.allTagsRows(of: try engine.countedTags(on: ladder), search: hasSearch ? search : "", sort: allTagsSort)
    }

    /// All Tags' rows out of `counted`, every tag with its counts, in the
    /// order a tree lists them: as a tree, each level in `sort`'s order,
    /// keeping only the tags whose last level mentions `search`, with the
    /// tags they sit inside, or every tag while it's blank. Each row is named
    /// by its last level under its parent and its whole name at the top,
    /// grayed when it's set aside, on its own or inside a tag that is, and
    /// with Priority off then, unless it's a priority tag.
    static func allTagsRows(of counted: [CountedTag], search: String, sort: AllTagsSort) -> [AllTagsRow] {
        let tags = counted.map(\.tag)
        let byName = Dictionary(counted.map { ($0.tag.name, $0) }, uniquingKeysWith: { first, _ in first })
        let isSetAside = setAside(among: tags)
        let setAsideNames = setAsideNames(among: tags)
        /// The rows of `trees`, listed under `parent`.
        func rows(of trees: [TagTree], under parent: String?) -> [AllTagsRow] {
            sort.sorted(
                trees.compactMap { tree in
                    let children = rows(of: tree.children, under: tree.name)
                    // The forest holds `counted`'s names alone, so each tree
                    // finds its own.
                    guard let counted = byName[tree.name],
                        !children.isEmpty || mentions(TagPath.lastLevel(of: tree.name), search)
                    else {
                        return nil
                    }
                    return AllTagsRow(
                        tag: counted.tag, title: TagPath.shown(tree.name, under: parent), counts: counted.counts,
                        isGrayed: isSetAside(tree.name),
                        canPrioritize: counted.tag.canBePrioritized(amongSetAside: setAsideNames), children: children)
                })
        }
        return rows(of: TagTree.forest(of: tags.map(\.name)), under: nil)
    }

    /// The rows All Tags lists, and the rows inside them, in its order, or
    /// none while the window lists something else.
    private var listedAllTagsRows: [AllTagsRow] {
        guard case .success(.allTags(let rows)) = listing else {
            return []
        }
        func flattened(_ rows: [AllTagsRow]) -> [AllTagsRow] {
            rows.flatMap { [$0] + flattened($0.children) }
        }
        return flattened(rows)
    }

    /// The tags Lucas selected in All Tags that it lists, in its order.
    var selectedListedTags: [CardTag] {
        listedAllTagsRows.filter { selectedTags.contains($0.id) }.map(\.tag)
    }

    /// What Lucas can do in All Tags with what he selected there: list the
    /// one tag's cards, delete the tags, and clear the unused tags while
    /// there are some.
    public var tagActions: Set<TagAction> {
        guard case .allTags(let selected) = detail else {
            return []
        }
        var actions: Set<TagAction> = unusedTags.isEmpty ? [] : [.clearUnused]
        if !selected.isEmpty {
            actions.insert(.delete)
        }
        if selected.count == 1 {
            actions.insert(.showCards)
        }
        return actions
    }

    /// Sorts each level of All Tags' tree by `column`, ascending or
    /// descending, as a click on the column's title asks.
    public mutating func sortAllTags(by column: AllTagsColumn, ascending isAscending: Bool) {
        let sort = AllTagsSort(column: column, isAscending: isAscending)
        guard sort != allTagsSort else { return }
        allTagsSort = sort
        read(on: ladder)
    }

    /// Whether All Tags' tag named `tag` shows the tags inside it: once Lucas
    /// opened it, since each parent starts closed, or, while a search
    /// narrows the tree, unless he closed it since, as the search opens every
    /// parent it keeps.
    public func isOpen(_ tag: String) -> Bool {
        hasSearch ? !tagsClosedInSearch.contains(tag) : openTags.contains(tag)
    }

    /// Opens All Tags' tag named `tag`, or closes it when `isOpen` is false,
    /// as its disclosure triangle does: for as long as the window is open,
    /// or, while a search narrows the tree, until the search changes.
    public mutating func setOpen(_ isOpen: Bool, _ tag: String) {
        switch (hasSearch, isOpen) {
        case (true, true): tagsClosedInSearch.remove(tag)
        case (true, false): tagsClosedInSearch.insert(tag)
        case (false, true): openTags.insert(tag)
        case (false, false): openTags.remove(tag)
        }
    }

    /// Selects the tags named `names` in All Tags, as ⌘-click and ⇧-click
    /// select several.
    public mutating func selectTags(_ names: Set<String>) {
        selectedTags = names
    }

    /// The tags a tag's menu acts on when Lucas opens it on the tag named
    /// `tag` in All Tags: every selected tag it lists, when `tag` is one of
    /// them, as in Finder, and `tag` alone otherwise.
    public func tagsActedOn(clicking tag: String) -> [String] {
        let selected = selectedListedTags.map(\.name)
        return selected.contains(tag) ? selected : [tag]
    }

    /// Ticks `checkbox` of All Tags' tag named `tag`, or unticks it when
    /// `isTicked` is false: pins it after the pinned tags or unpins it, makes
    /// it a priority tag or no longer, while its menu's Prioritize is on, or
    /// sets it aside or stops; and reads the cards again, or records why it
    /// couldn't.
    public mutating func tick(_ checkbox: AllTagsCheckbox, _ isTicked: Bool, on tag: String) {
        guard let menu = menu(for: [tag]) else { return }
        switch checkbox {
        case .pinned: setPinned(isTicked, of: menu.tags)
        case .priority:
            guard menu.canPrioritize else { return }
            setPriority(isTicked, of: menu.tags)
        case .setAside: setSetAside(isTicked, of: menu.tags)
        }
    }

    /// Lists the cards of All Tags' tag named `tag` in All Tags' place, with
    /// its name as the window's title, as a double-click on it does, with
    /// nothing searched, keeping All Tags' search for Back.
    public mutating func showCards(of tag: String) {
        guard sidebarItem == .allTags, tagShownFromAllTags == nil, editing == nil,
            tags.contains(where: { $0.name == tag })
        else { return }
        allTagsSearch = search
        search = ""
        tagShownFromAllTags = tag
        read(on: ladder)
    }

    /// Lists the cards of the one tag selected in All Tags, in its place, as
    /// Return does, while it's offered.
    public mutating func showCardsOfSelectedTag() {
        guard tagActions.contains(.showCards), let tag = selectedListedTags.first else { return }
        showCards(of: tag.name)
    }

    /// Goes back to All Tags from the tag's cards it lists in its place, as
    /// Back does, with the search, the sort, the selection and the open
    /// parents it had.
    public mutating func goBack() {
        guard canGoBack else { return }
        tagShownFromAllTags = nil
        search = allTagsSearch
        read(on: ladder)
    }

    /// Asks whether to delete `tags`, those of them the window offers, each
    /// with every tag inside it, saying what that does: how many cards lose
    /// them, how many tags sit inside them, how many cards come back to
    /// Lucas's reviews, and, under selective sync, how many stop syncing; or
    /// records why it couldn't count them. After Delete… in their menu.
    public mutating func askToDeleteTags(_ tags: [String]) {
        let offered = offeredTags(tags).map(\.name)
        guard let first = offered.first else { return }
        var deletion: TagDeletion?
        let counted = perform(.deleteTags(tag: first)) { engine throws(EngineError) in
            deletion = try engine.deletion(of: offered)
        }
        if counted, let deletion {
            question = .deleteTags(deletion)
        }
    }

    /// Asks whether to delete the tags selected in All Tags, as ⌘⌫ does,
    /// while it's offered.
    public mutating func askToDeleteSelectedTags() {
        guard tagActions.contains(.delete) else { return }
        askToDeleteTags(selectedListedTags.map(\.name))
    }

    /// Deletes the tags of `deletion`, which the window asked about and Lucas
    /// confirmed, each with every tag inside it, off every card, in one go,
    /// and reads the cards again, or records why it couldn't. The dialog
    /// hands `deletion` back, as Delete's hands its cards.
    public mutating func deleteTags(_ deletion: TagDeletion) {
        question = nil
        change(deletion.tags, as: FailedAction.deleteTags(tag:)) { engine throws(EngineError) in
            try engine.deleteTags(deletion.tags)
        }
    }

    /// Asks whether to clear the unused tags, saying how many, while Clear
    /// Unused Tags… is offered; or records why it couldn't count them.
    public mutating func askToClearUnusedTags() {
        guard tagActions.contains(.clearUnused) else { return }
        var unused: [String] = []
        let counted = perform(.clearUnusedTags) { engine throws(EngineError) in unused = try engine.unusedTags() }
        guard counted else { return }
        if unused.isEmpty {
            // A card got one meanwhile: no longer offered.
            read(on: ladder)
        } else {
            question = .clearUnusedTags(unused)
        }
    }

    /// Clears the unused tags, which the window asked about and Lucas
    /// confirmed: those no card carries now. Then it reads the cards again,
    /// or records why it couldn't.
    public mutating func clearUnusedTags() {
        question = nil
        let done = perform(.clearUnusedTags) { engine throws(EngineError) in try engine.clearUnusedTags() }
        if done {
            read(on: ladder)
        }
    }

    /// Whether All Tags takes the tags named `names` dropped inside the tag
    /// named `parent`, or at the top when it's nil, which says where the
    /// drag highlights a row or draws its line: when one of `names` is a tag
    /// the window offers, `parent` too, none of them is `parent` or holds
    /// it, and one of them would move.
    public func canDrop(_ names: [String], into parent: String?) -> Bool {
        let dropped = offeredTags(names).map(\.name)
        guard !dropped.isEmpty, parent.map({ parent in tags.contains { $0.name == parent } }) ?? true else {
            return false
        }
        return (try? tagMoves(of: dropped, into: parent))?.isEmpty == false
    }

    /// Drops the tags named `names`, which Lucas drags in All Tags, inside
    /// the tag named `parent`: onto its row, or between two rows at the level
    /// of the tags right inside it; or at the top when `parent` is nil. Each
    /// moves there with every tag inside it, as `Engine.moveTags(_:into:)`
    /// moves them, in one go, and reads the cards again; then the tags that
    /// moved are selected by their new names, inside `parent` opened, for
    /// Lucas to see where they went. Whether it took the drop, as
    /// `canDrop(_:into:)` says; never when the engine couldn't, which it
    /// records.
    @discardableResult
    public mutating func drop(_ names: [String], into parent: String?) -> Bool {
        let dropped = offeredTags(names).map(\.name)
        guard canDrop(dropped, into: parent), let first = dropped.first else {
            return false
        }
        var moves: [TagEdit] = []
        let done = perform(.move(tag: first)) { engine throws(EngineError) in
            moves = try engine.moveTags(dropped, into: parent)
        }
        guard done else {
            return false
        }
        follow(moves)
        selectedTags = Set(moves.compactMap(\.newName))
        if let parent {
            openTags.formUnion(TagPath.lineage(of: parent))
            tagsClosedInSearch.subtract(TagPath.lineage(of: parent))
        }
        read(on: ladder)
        return true
    }
}
