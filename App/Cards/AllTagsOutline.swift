import AppKit
import FichaCore
import FichaData
import SwiftUI

/// All Tags, where the Cards window's table was: every tag as a tree, in
/// AppKit's outline view, since SwiftUI's `Table` with children takes a drop
/// neither onto one row nor between two, and an outline view draws its
/// insertion line at the level a drop goes to, as Finder's and Mail's do.
/// Its columns are the tag, Cards, Due, and the Pinned, Priority and Set Aside
/// checkboxes, Priority off on a set-aside tag; a click on a column's title
/// sorts each level by it, and a second click turns the order around. A
/// set-aside tag's row is grayed, and so are the rows inside it. Lucas
/// selects several tags with ⌘ and ⇧, opens the context menu `menu` makes
/// for the tags it acts on, double-clicks a tag to list its cards, and drags
/// tags onto another, between two rows, or into the sidebar, which takes
/// their names as text. The state decides all of it, what the tree lists,
/// which parents are open, what's selected, how it sorts and which drops it
/// takes, and the outline view draws it and tells the state what Lucas did.
struct AllTagsOutline: NSViewRepresentable {
    let rows: [CardsWindowState.AllTagsRow]
    @Binding var state: CardsWindowState
    /// The context menu of the tags with these names.
    let menu: ([String]) -> NSMenu

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let outline = TagsOutlineView()
        outline.headerView = NSTableHeaderView()
        outline.style = .inset
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = true
        outline.allowsColumnReordering = false
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.autoresizesOutlineColumn = false
        // Narrower than the inset style's own, so that the columns fit in
        // the pane.
        outline.intercellSpacing.width = 4
        for column in CardsWindowState.AllTagsColumn.allCases {
            outline.addTableColumn(column.tableColumn)
        }
        outline.outlineTableColumn = outline.tableColumns.first
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.target = coordinator
        outline.doubleAction = #selector(Coordinator.showClickedTagsCards(_:))
        outline.makeMenu = { [weak coordinator] name in coordinator?.menu(clicking: name) }
        // Its own rows, and the sidebar's, which takes a tag dropped there as
        // SwiftUI takes text: copied.
        outline.registerForDraggedTypes([.string])
        outline.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        coordinator.outline = outline
        let scrollView = NSScrollView()
        scrollView.documentView = outline
        // Sideways too, for a pane narrower than the columns.
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }

    /// Tells the state what Lucas did in the outline view, and gives the
    /// outline view the state's tree, sort, open parents and selection.
    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: AllTagsOutline
        weak var outline: NSOutlineView?
        /// The rows the outline view shows, as nodes, which it tells apart
        /// as objects.
        private var roots: [TagNode] = []
        /// The rows `roots` were made of.
        private var shownRows: [CardsWindowState.AllTagsRow]?
        /// Whether the outline view is being given the state, so that what it
        /// says it changed, which the state asked, goes back to no one.
        private var isUpdating = false

        init(_ parent: AllTagsOutline) {
            self.parent = parent
        }

        /// Gives the outline view the state's rows, when they changed, then
        /// its sort, its open parents and its selection, scrolled into view
        /// when it's the state that changed it, as after a drop or Back.
        func update() {
            guard let outline else { return }
            isUpdating = true
            defer { isUpdating = false }
            if parent.rows != shownRows {
                shownRows = parent.rows
                roots = parent.rows.map(TagNode.init)
                outline.reloadData()
            }
            let sort = parent.state.allTagsSort
            let descriptors = [NSSortDescriptor(key: sort.column.key, ascending: sort.isAscending)]
            if outline.sortDescriptors != descriptors {
                outline.sortDescriptors = descriptors
            }
            open(roots, in: outline)
            var selected = IndexSet()
            for index in 0..<outline.numberOfRows {
                if let node = outline.item(atRow: index) as? TagNode, parent.state.selectedTags.contains(node.name) {
                    selected.insert(index)
                }
            }
            if selected != outline.selectedRowIndexes {
                outline.selectRowIndexes(selected, byExtendingSelection: false)
                if let first = selected.first {
                    outline.scrollRowToVisible(first)
                }
            }
        }

        /// Opens the parents among `nodes` that the state says are open, and
        /// the open ones inside them, and closes the others.
        private func open(_ nodes: [TagNode], in outline: NSOutlineView) {
            for node in nodes where !node.children.isEmpty {
                if parent.state.isOpen(node.name) {
                    outline.expandItem(node)
                    open(node.children, in: outline)
                } else if outline.isItemExpanded(node) {
                    outline.collapseItem(node)
                }
            }
        }

        /// The context menu of the tag named `name`, which acts on every
        /// selected tag when it's one of them.
        func menu(clicking name: String) -> NSMenu {
            parent.menu(parent.state.tagsActedOn(clicking: name))
        }

        /// Lists the cards of the tag Lucas double-clicked, in All Tags'
        /// place.
        @objc func showClickedTagsCards(_ sender: NSOutlineView) {
            guard let node = sender.item(atRow: sender.clickedRow) as? TagNode else { return }
            parent.state.showCards(of: node.name)
        }

        /// Ticks or unticks the checkbox Lucas clicked, as the state does it:
        /// until the state reads the tags again, the checkbox shows what
        /// they had, which stays when it couldn't.
        @objc func tick(_ sender: NSButton) {
            guard let outline, let cell = sender.superview as? CheckboxCellView,
                let node = outline.item(atRow: outline.row(for: sender)) as? TagNode
            else { return }
            let isTicked = sender.state == .on
            cell.show(node.row)
            parent.state.tick(cell.checkbox, isTicked, on: node.name)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? TagNode else { return roots.count }
            return node.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? TagNode else { return roots[index] }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? TagNode)?.children.isEmpty == false
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? TagNode, let identifier = tableColumn?.identifier,
                let column = CardsWindowState.AllTagsColumn(key: identifier.rawValue)
            else { return nil }
            switch column {
            case .tag:
                let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? TagCellView ?? TagCellView()
                cell.identifier = identifier
                cell.show(node.row)
                return cell
            case .cards, .due:
                let cell =
                    outlineView.makeView(withIdentifier: identifier, owner: nil) as? NumberCellView ?? NumberCellView()
                cell.identifier = identifier
                cell.show(column == .cards ? node.row.counts.cards : node.row.counts.due, grayed: node.row.isGrayed)
                return cell
            case .pinned, .priority, .setAside:
                let checkbox: CardsWindowState.AllTagsCheckbox =
                    switch column {
                    case .pinned: .pinned
                    case .priority: .priority
                    default: .setAside
                    }
                let cell =
                    outlineView.makeView(withIdentifier: identifier, owner: nil) as? CheckboxCellView
                    ?? CheckboxCellView(checkbox, title: column.title, target: self, action: #selector(tick(_:)))
                cell.identifier = identifier
                cell.show(node.row)
                return cell
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let outline else { return }
            let names = outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? TagNode)?.name }
            parent.state.selectTags(Set(names))
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isUpdating, let node = notification.userInfo?["NSObject"] as? TagNode else { return }
            parent.state.setOpen(true, node.name)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isUpdating, let node = notification.userInfo?["NSObject"] as? TagNode else { return }
            parent.state.setOpen(false, node.name)
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isUpdating, let descriptor = outlineView.sortDescriptors.first,
                let column = descriptor.key.flatMap(CardsWindowState.AllTagsColumn.init(key:))
            else { return }
            parent.state.sortAllTags(by: column, ascending: descriptor.ascending)
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)?
        {
            (item as? TagNode).map { $0.name as NSString }
        }

        /// Whether the outline view takes the tags Lucas drags over it, its
        /// own: onto a row, inside that tag, or between two rows, inside the
        /// tag whose level the insertion line shows, or at the top, as the
        /// state says. Below the rows, at the top, after them.
        func outlineView(
            _ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard (info.draggingSource as? NSOutlineView) === outlineView else { return [] }
            if item == nil, index == NSOutlineViewDropOnItemIndex {
                outlineView.setDropItem(nil, dropChildIndex: roots.count)
            }
            return parent.state.canDrop(Self.names(in: info), into: (item as? TagNode)?.name) ? .move : []
        }

        func outlineView(
            _ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int
        ) -> Bool {
            parent.state.drop(Self.names(in: info), into: (item as? TagNode)?.name)
        }

        /// The names of the tags Lucas drags.
        private static func names(in info: any NSDraggingInfo) -> [String] {
            info.draggingPasteboard.pasteboardItems?.compactMap { $0.string(forType: .string) } ?? []
        }
    }
}

/// A row of All Tags, as the outline view tells its rows apart: an object.
private final class TagNode {
    let row: CardsWindowState.AllTagsRow
    let children: [TagNode]

    var name: String {
        row.id
    }

    init(_ row: CardsWindowState.AllTagsRow) {
        self.row = row
        children = row.children.map(TagNode.init)
    }
}

/// The outline view, whose context menu is the one of the tag Lucas clicks.
private final class TagsOutlineView: NSOutlineView {
    /// The context menu of the tag with this name.
    var makeMenu: ((String) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let node = item(atRow: row(at: convert(event.locationInWindow, from: nil))) as? TagNode else {
            return nil
        }
        // The outline view's own shows it, with the ring around the row.
        menu = makeMenu?(node.name)
        return super.menu(for: event)
    }
}

extension CardsWindowState.AllTagsColumn {
    /// How the outline view names it, in its sort descriptors too.
    fileprivate var key: String {
        switch self {
        case .tag: "tag"
        case .cards: "cards"
        case .due: "due"
        case .pinned: "pinned"
        case .priority: "priority"
        case .setAside: "setAside"
        }
    }

    fileprivate init?(key: String) {
        guard let column = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = column
    }

    /// Its title.
    fileprivate var title: String {
        switch self {
        case .tag:
            String(localized: "Tag", comment: "A column of the Cards window's All Tags: the tag.")
        case .cards:
            String(
                localized: "Cards",
                comment: "A column of the Cards window's All Tags: how many cards carry the tag, or a tag inside it.")
        case .due:
            String(
                localized: "Due",
                comment: "A column of the Cards window's All Tags: how many of the tag's cards are due now.")
        case .pinned:
            String(
                localized: "Pinned",
                comment:
                    "A column of the Cards window's All Tags: a checkbox, ticked while the tag is pinned to the sidebar."
            )
        case .priority:
            String(
                localized: "Priority",
                comment: "A column of the Cards window's All Tags: a checkbox, ticked while the tag is a priority tag.")
        case .setAside:
            // A key of its own, since a tag's menu says "Set Aside" too, as a
            // verb, which a translation may word apart.
            String(
                localized: "all-tags.set-aside-column", defaultValue: "Set Aside",
                comment: """
                    A column of the Cards window's All Tags: a checkbox, ticked while the tag is set aside, its cards \
                    out of Lucas's reviews for now.
                    """)
        }
    }

    /// Its column, whose title's first click sorts it as the state says: the
    /// tag's as wide as the others leave it, and each of the others as wide
    /// as its title, in whatever language, with the sort's arrow, so that
    /// all fit in the pane as the window first opens.
    @MainActor
    fileprivate var tableColumn: NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
        column.title = title
        column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: !sortsDescendingFirst)
        guard self != .tag else {
            // The outline view widens it to fill the pane.
            column.minWidth = 100
            column.width = 100
            column.resizingMask = [.autoresizingMask, .userResizingMask]
            return column
        }
        let isNumber = self == .cards || self == .due
        column.headerCell.alignment = isNumber ? .right : .center
        column.sizeToFit()
        // Room for the sort's arrow beside a number's title, in bold while
        // it sorts; a checkbox's title, centered, has some at its sides.
        column.width = max(column.width + (isNumber ? 28 : 0), 36)
        column.minWidth = column.width
        column.resizingMask = .userResizingMask
        return column
    }
}

/// A tag's cell: its emoji, its own or else the tags' it sits inside, before
/// its title, its last level under its parent and its whole name at the top,
/// after the tag symbol, filled with its color, found the same way, when it
/// has one. Its tooltip says its whole name.
private final class TagCellView: NSTableCellView {
    init() {
        super.init(frame: .zero)
        let symbol = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        for view in [symbol, text] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        imageView = symbol
        textField = text
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 4),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(_ row: CardsWindowState.AllTagsRow) {
        let color = row.tag.shownColor
        imageView?.image = NSImage(systemSymbolName: color == nil ? "tag" : "tag.fill", accessibilityDescription: nil)
        imageView?.contentTintColor = color?.nsColor ?? .secondaryLabelColor
        textField?.stringValue = row.tag.title(shown: row.title)
        toolTip = row.tag.title
        alphaValue = row.isGrayed ? 0.5 : 1
    }
}

/// A number's cell, Cards or Due, on the right, in digits of one width, and
/// faint when it's none.
private final class NumberCellView: NSTableCellView {
    init() {
        super.init(frame: .zero)
        let text = NSTextField(labelWithString: "")
        text.alignment = .right
        text.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(_ number: Int, grayed: Bool) {
        textField?.stringValue = number.formatted()
        textField?.textColor = number == 0 ? .tertiaryLabelColor : .labelColor
        alphaValue = grayed ? 0.5 : 1
    }
}

/// A checkbox's cell, Pinned, Priority or Set Aside, in its middle, named
/// for VoiceOver by its column.
private final class CheckboxCellView: NSTableCellView {
    let checkbox: CardsWindowState.AllTagsCheckbox
    private let button: NSButton

    init(_ checkbox: CardsWindowState.AllTagsCheckbox, title: String, target: AnyObject, action: Selector) {
        self.checkbox = checkbox
        button = NSButton(checkboxWithTitle: "", target: target, action: action)
        super.init(frame: .zero)
        button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Shows whether `row`'s tag has it ticked, of its own, and Priority
    /// off while the tag is set aside.
    func show(_ row: CardsWindowState.AllTagsRow) {
        let isTicked =
            switch checkbox {
            case .pinned: row.tag.isPinned
            case .priority: row.tag.isPriority
            case .setAside: row.tag.isSetAside
            }
        button.state = isTicked ? .on : .off
        button.isEnabled = checkbox != .priority || row.canPrioritize
    }
}
