import FichaCore
import FichaData
import SwiftUI

/// The Cards window's content, in three panes as Mail lays out its own: a
/// sidebar to choose a group of cards or the inbox, a table with one row per
/// card in it, or per capture and flagged card in the inbox, narrowed by the
/// toolbar's search field, and the selected row whole beside it, with what
/// Lucas can do with it at its foot. The cards' table opens with the columns
/// and the order Lucas left it with, which he changes in its headers. He
/// edits a card or a capture right there, in fields that take the detail's
/// place while the sidebar and the table wait. He selects several cards with
/// ⌘ or Shift, as in Finder, and then the detail says how many, with what he
/// can do with all of them. It reads the cards again whenever the engine says
/// they changed, from the app or the `ficha` CLI, when Lucas changes the
/// ladder in Settings, and every minute, since cards come due as time passes,
/// or at once when Ficha Dev's debug menu moves the time.
struct CardsView: View {
    let model: AppModel
    /// What the table lists, or why it couldn't be read.
    @State private var listing: Result<Listing, EngineError>?
    /// The tags the sidebar offers: those of the cards that aren't buried.
    @State private var tags: [String] = []
    /// The engine's time when the cards were read, which the Due column
    /// counts from.
    @State private var now: Date
    /// What the sidebar chose: All cards, until Lucas picks another group or
    /// the inbox.
    @State private var sidebarItem = SidebarItem.cards(.all)
    /// What Lucas looks for in what the sidebar chose, from the search field.
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    /// The cards Lucas selected, which can include cards the table no longer
    /// lists: the detail and its actions take only those it lists.
    @State private var selection: Set<CardRow.ID> = []
    /// The table's order: the one Lucas left it in with a click on a column's
    /// header, and at first the newest cards first.
    @State private var sortOrder = Preferences.cardsSortOrder
    /// The table's columns as Lucas left them: which ones show, in what order
    /// and how wide. At first Front, Step and Due, until he adds others from
    /// the headers' menu.
    @State private var columns = Preferences.cardsColumns
    /// The row Lucas selected in the inbox, one at a time, which the table
    /// may no longer list, as with the cards.
    @State private var inboxSelection: InboxRow.ID?
    /// The inbox's order: the latest added first, until Lucas clicks a
    /// column's header.
    @State private var inboxSortOrder = [InboxRowOrder(.added, order: .reverse)]
    /// The review log of the card the detail shows, or why it couldn't be
    /// read: read with the cards, and again when Lucas selects another card.
    @State private var reviewLog: CardReviewLog?
    /// What Lucas is editing, as it was when he started, while the detail
    /// shows its fields. The sidebar and the table wait until he saves or
    /// cancels, so that a click elsewhere can't drop what he typed.
    @State private var editing: Editing?
    /// Whether the table has the keyboard, which it gets back once Lucas
    /// saves or cancels an edit, for him to go on with the arrow keys.
    @FocusState private var isTableFocused: Bool
    /// The card Lucas is flagging, while the sheet asks for his note.
    @State private var flagging: CardRow?
    /// The capture Lucas is discarding, while the window asks whether to.
    @State private var discarding: Capture?
    /// The cards Lucas is deleting, while the window asks whether to.
    @State private var deleting: [CardRow]?
    /// What Lucas did that couldn't be saved, while an alert says so.
    @State private var failure: Failure?

    init(model: AppModel) {
        self.model = model
        _now = State(initialValue: model.now)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 280)
                .waiting(while: editing != nil)
        } content: {
            table
                .navigationSplitViewColumnWidth(min: 380, ideal: 440)
                .waiting(while: editing != nil)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        }
        .searchable(text: $search, placement: .toolbar)
        .searchFocused($isSearchFocused)
        .background {
            // ⌘F puts Lucas in the search field, as in Mail and Finder. The
            // search field doesn't take it on its own.
            Button {
                isSearchFocused = true
            } label: {
                Text("Find", comment: "A hidden button of the Cards window: ⌘F, which goes to the search field.")
            }
            .keyboardShortcut("f")
            .hidden()
        }
        .sheet(item: $flagging) { row in
            FlagSheet(card: row.card) { note throws(EngineError) in
                try model.flag(row.id, note: note)
            }
        }
        .confirmationDialog(
            discarding.map {
                Text(
                    "Discard “\($0.text)”?",
                    comment: "The title of the Cards window's question before it discards a capture, with its text.")
            } ?? Text(verbatim: ""),
            isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }),
            titleVisibility: .visible,
            presenting: discarding
        ) { capture in
            Button(role: .destructive) {
                discard(capture)
            } label: {
                Text("Discard", comment: "The button that discards the capture the Cards window asks about.")
            }
        } message: { _ in
            Text(
                "It leaves the inbox without becoming cards, and you can't bring it back.",
                comment: "Under the title of the Cards window's question before it discards a capture.")
        }
        .confirmationDialog(
            deleting.map { deletionTitle(for: $0) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { rows in
            Button(role: .destructive) {
                delete(rows)
            } label: {
                Text("Delete", comment: "The button that deletes the cards the Cards window asks about.")
            }
        } message: { rows in
            deletionMessage(for: rows)
        }
        .failureAlert($failure)
        .onChange(of: sidebarItem) {
            reload()
        }
        .onChange(of: search) {
            reload()
        }
        .onChange(of: selection) {
            readReviewLog()
        }
        .onChange(of: inboxSelection) {
            readReviewLog()
        }
        .task {
            // Listening before reading, so no change falls in between.
            let changes = model.changes()
            reload()
            for await _ in changes {
                reload()
            }
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                reload()
            }
        }
        .onChange(of: model.settings.ladder) {
            reload()
        }
        .onChange(of: model.debugTools?.timeShift) {
            reload()
        }
    }

    /// Reads the tags and what the sidebar chose again, as they are now, and
    /// the review log of the card the detail shows. When the chosen tag is
    /// gone, because its last card was buried, edited or deleted, the window
    /// goes back to All cards.
    private func reload() {
        now = model.now
        do throws(EngineError) {
            tags = try model.tags()
            if case .cards(.tag(let tag)) = sidebarItem, !tags.contains(tag) {
                sidebarItem = .cards(.all)
            }
            switch sidebarItem {
            case .cards(let group):
                listing = .success(.cards(try model.cardRows(in: group, matching: search)))
            case .inbox:
                listing = .success(.inbox(try model.inboxRows(matching: search)))
            }
        } catch {
            listing = .failure(error)
        }
        readReviewLog()
    }

    /// Reads the review log of the card the detail shows, while it shows one:
    /// the only card selected, or the flagged card selected in the inbox.
    private func readReviewLog() {
        guard let row = singleSelectedRow else {
            reviewLog = nil
            return
        }
        reviewLog = CardReviewLog(
            cardID: row.id, rows: Result { () throws(EngineError) in try model.reviewLogRows(of: row.id) })
    }

    /// The review log of the card in `row`, once it's read: nil while the
    /// one read is another card's.
    private func reviewLogRows(of row: CardRow) -> Result<[ReviewLogRow], EngineError>? {
        guard let reviewLog, reviewLog.cardID == row.id else {
            return nil
        }
        return reviewLog.rows
    }

    /// What Lucas chooses from: the cards by where they stand, then the
    /// inbox, with how many things wait in it, as the menu counts them, then
    /// the cards by tag, then by type. One is chosen at a time, always.
    private var sidebar: some View {
        List(selection: chosenItem) {
            Section {
                ForEach([CardGroup.all, .new, .due, .learned, .flagged, .buried], id: \.self) { group in
                    Label(group.title, systemImage: group.symbol)
                        .tag(SidebarItem.cards(group))
                }
            }
            Section {
                Label(
                    String(
                        localized: "Inbox", comment: "An item of the Cards window's sidebar: what waits to be refined."),
                    systemImage: "tray"
                )
                .badge(model.progress?.inInbox ?? 0)
                .tag(SidebarItem.inbox)
            }
            if !tags.isEmpty {
                Section {
                    ForEach(tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(SidebarItem.cards(.tag(tag)))
                    }
                } header: {
                    Text("Tags", comment: "A section of the Cards window's sidebar: the cards' tags.")
                }
            }
            Section {
                ForEach(CardType.allCases, id: \.self) { type in
                    Label(type.pluralName, systemImage: type.symbol)
                        .tag(SidebarItem.cards(.type(type)))
                }
            } header: {
                Text("Types", comment: "A section of the Cards window's sidebar: the card types.")
            }
        }
    }

    /// The sidebar's selection: what it chose, which Lucas can change but not
    /// clear.
    private var chosenItem: Binding<SidebarItem?> {
        Binding {
            sidebarItem
        } set: {
            sidebarItem = $0 ?? sidebarItem
        }
    }

    /// Whether Lucas is looking for something, which narrows the table.
    private var hasSearch: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the table says when `group`, or the search in it, brings no
    /// cards.
    @ViewBuilder
    private func noCards(in group: CardGroup) -> some View {
        if hasSearch {
            ContentUnavailableView.search(text: search)
        } else if group == .all {
            ContentUnavailableView(
                group.emptyTitle, systemImage: group.symbol,
                description: Text(
                    "The cards you approve in a refine session show up here, and the ones you bury, in Buried.",
                    comment: "In the Cards window, when All cards is empty."))
        } else {
            ContentUnavailableView(group.emptyTitle, systemImage: group.symbol)
        }
    }

    /// What the table says when the inbox, or the search in it, brings
    /// nothing.
    @ViewBuilder
    private var emptyInbox: some View {
        if hasSearch {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView(
                String(localized: "Nothing in the inbox", comment: "In the Cards window, when the inbox is empty."),
                systemImage: "tray",
                description: Text(
                    "What you capture, and the cards you flag, wait here to be refined.",
                    comment: "In the Cards window, when the inbox is empty."))
        }
    }

    @ViewBuilder
    private var table: some View {
        switch listing {
        case .success(.cards(let rows)):
            cardTable(rows)
        case .success(.inbox(let rows)):
            inboxTable(rows)
        case .failure(let error):
            ContentUnavailableView {
                Label("Couldn't load your cards", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            }
        case nil:
            EmptyView()
        }
    }

    /// The cards of the group the sidebar chose, one per row. A right click on
    /// the headers shows SwiftUI's menu of the columns, as in Finder, which
    /// adds or removes all of them but Front.
    private func cardTable(_ rows: [CardRow]) -> some View {
        Table(
            rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns
        ) {
            TableColumn(
                Text("Front", comment: "A column of the Cards window: the card's front."),
                sortUsing: CardRowOrder(.front)
            ) {
                row in
                FrontCell(card: row.card)
            }
            .width(min: 120)
            .customizationID(CardRowOrder.Column.front.rawValue)
            // Always there, as Finder's Name: it says which card a row is.
            .disabledCustomizationBehavior(.visibility)
            TableColumn(
                Text("Step", comment: "A column of the Cards window: the card's step on the ladder, and its wait."),
                sortUsing: CardRowOrder(.step)
            ) { row in
                Text(stepText(row))
            }
            .width(min: 56, ideal: 64, max: 100)
            .customizationID(CardRowOrder.Column.step.rawValue)
            TableColumn(
                Text("Due", comment: "A column of the Cards window: when the card is due."),
                sortUsing: CardRowOrder(.due)
            ) { row in
                Text(dueText(row, at: now))
            }
            .width(min: 60, ideal: 72, max: 110)
            .customizationID(CardRowOrder.Column.due.rawValue)
            TableColumn(
                Text("Type", comment: "A column of the Cards window: the card's type."),
                sortUsing: CardRowOrder(.type)
            ) { row in
                Text(row.card.type.name)
            }
            .width(min: 60, ideal: 76, max: 110)
            .customizationID(CardRowOrder.Column.type.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text("Tags", comment: "A column of the Cards window: the card's tags."),
                sortUsing: CardRowOrder(.tags)
            ) { row in
                Text(row.card.tags.formatted(.list(type: .and, width: .narrow)))
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 120)
            .customizationID(CardRowOrder.Column.tags.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text("Source", comment: "A column of the Cards window: where Lucas came across the card's content."),
                sortUsing: CardRowOrder(.source)
            ) { row in
                Text(row.card.source ?? "")
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 120)
            .customizationID(CardRowOrder.Column.source.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text(
                    "Last seen",
                    comment: "A column of the Cards window: when Lucas last saw the card, in a first view or a review."),
                sortUsing: CardRowOrder(.lastSeen)
            ) { row in
                // Without the time, as the inbox's Added column.
                Text(row.lastSeen?.formatted(date: .abbreviated, time: .omitted) ?? "")
            }
            .width(min: 80, ideal: 96, max: 140)
            .customizationID(CardRowOrder.Column.lastSeen.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text("Created", comment: "A column of the Cards window: when Lucas approved the card."),
                sortUsing: CardRowOrder(.created)
            ) { row in
                Text(row.card.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            .width(min: 80, ideal: 96, max: 140)
            .customizationID(CardRowOrder.Column.created.rawValue)
            .defaultVisibility(.hidden)
        }
        .focused($isTableFocused)
        .overlay {
            if rows.isEmpty, case .cards(let group) = sidebarItem {
                noCards(in: group)
            }
        }
        // The window opens the next time with the table as Lucas leaves it.
        .onChange(of: sortOrder) {
            Preferences.cardsSortOrder = sortOrder
        }
        .onChange(of: columns) {
            Preferences.cardsColumns = columns
        }
    }

    /// What waits in the inbox, one row each: the captures, the expansions
    /// and the flagged cards, which Lucas selects one at a time.
    private func inboxTable(_ rows: [InboxRow]) -> some View {
        Table(rows.sorted(using: inboxSortOrder), selection: $inboxSelection, sortOrder: $inboxSortOrder) {
            TableColumn(
                Text(
                    "Text",
                    comment: "A column of the Cards window's inbox: a capture's text, or a flagged card's front."),
                sortUsing: InboxRowOrder(.text)
            ) { row in
                if let cardRow = row.flaggedCard {
                    FrontCell(card: cardRow.card)
                } else {
                    Text(row.text)
                        .lineLimit(1)
                }
            }
            .width(min: 120)
            TableColumn(
                Text(
                    "Kind",
                    comment: "A column of the Cards window's inbox: whether a row is a capture, an expansion or a card."
                ),
                sortUsing: InboxRowOrder(.kind)
            ) { row in
                Text(row.kindName)
            }
            .width(min: 64, ideal: 76, max: 110)
            TableColumn(
                Text(
                    "Added",
                    comment: "A column of the Cards window's inbox: when Lucas captured it, or flagged the card."),
                sortUsing: InboxRowOrder(.added)
            ) { row in
                // Without the time, to leave the Text column its room.
                Text(row.addedAt.formatted(date: .abbreviated, time: .omitted))
            }
            .width(min: 80, ideal: 96, max: 140)
        }
        .focused($isTableFocused)
        .overlay {
            if rows.isEmpty {
                emptyInbox
            }
        }
    }

    /// The selected cards the table lists, which the detail shows and its
    /// actions act on: those Lucas selected in a group of cards, or the
    /// flagged card he selected in the inbox. The actions read them as they
    /// are when Lucas acts, never as their buttons had them: SwiftUI keeps the
    /// action a keyboard shortcut had when its button first showed, so ⌘E
    /// would bury the cards selected back then.
    private var selectedRows: [CardRow] {
        switch listing {
        case .success(.cards(let rows)):
            return rows.filter { selection.contains($0.id) }
        case .success(.inbox):
            return selectedInboxRow?.flaggedCard.map { [$0] } ?? []
        case .failure, nil:
            return []
        }
    }

    /// The row Lucas selected in the inbox, while the table lists it.
    private var selectedInboxRow: InboxRow? {
        guard case .success(.inbox(let rows)) = listing else {
            return nil
        }
        return rows.first { $0.id == inboxSelection }
    }

    @ViewBuilder
    private var detail: some View {
        let selected = selectedRows
        switch editing {
        case .card(let card):
            CardEditor(card: card, isSearching: isSearchFocused) { content throws(EngineError) in
                try model.edit(card.id, with: content)
                // The detail shows the card as saved at once, without waiting
                // for the engine to say it changed.
                reload()
            } close: {
                stopEditing()
            }
        case .capture(let capture):
            CaptureEditor(capture: capture, isSearching: isSearchFocused) { text, note, source throws(EngineError) in
                try model.editCapture(capture.id, text: text, note: note, source: source)
                // As a card's: the detail shows the capture as saved at once.
                reload()
            } close: {
                stopEditing()
            }
        case nil:
            if let row = selectedInboxRow, let capture = row.capture {
                CaptureDetail(capture: capture, kind: row.kindName, expandedCard: row.expandedCard)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        captureActions
                    }
            } else if selected.count > 1 {
                selectionSummary(selected)
            } else if let row = selected.first {
                CardDetail(row: row, now: now, reviewLog: reviewLogRows(of: row), ladder: model.settings.ladder)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actions(for: row)
                    }
            } else if case .inbox = sidebarItem {
                ContentUnavailableView(
                    String(
                        localized: "Nothing selected",
                        comment: "In the Cards window's detail, when nothing in the inbox is selected."),
                    systemImage: "tray")
            } else {
                ContentUnavailableView("No card selected", systemImage: "rectangle.on.rectangle")
            }
        }
    }

    /// Ends an edit, saved or not, and gives the table the keyboard back.
    private func stopEditing() {
        editing = nil
        isTableFocused = true
    }

    /// Edit, which turns the detail of the selected card or capture into
    /// fields: ⌘L for either, since only one detail shows at a time.
    private var editButton: some View {
        Button(
            String(
                localized: "Edit",
                comment:
                    "A button of the Cards window that turns the card's or the capture's detail into fields to edit it."
            )
        ) {
            startEditing()
        }
        .keyboardShortcut("l", modifiers: .command)
        .help(
            Text(
                "Edit (⌘L)", comment: "The tooltip of the Cards window's button that edits the card or the capture."))
    }

    /// What Lucas can do with the capture selected in the inbox, at the foot
    /// of its detail, always in sight: edit it, and discard it, which asks
    /// first. While he's in the search field, ⌘⌫ is the field's, as in any
    /// text field: it deletes what he typed.
    private var captureActions: some View {
        ActionBar {
            editButton
            Button(
                String(
                    localized: "Discard…",
                    comment: "A button of the Cards window that discards the capture, asking first."
                )
            ) {
                startDiscarding()
            }
            .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.deleteKey, modifiers: .command))
            .help(Text("Discard… (⌘⌫)", comment: "The tooltip of the Cards window's button that discards the capture."))
            Spacer()
        }
    }

    /// What Lucas can do with the selected card, at the foot of its detail,
    /// always in sight: edit it, flag it while it's in his reviews, bury it,
    /// or unbury it once it's buried, and delete it, which asks first.
    private func actions(for row: CardRow) -> some View {
        ActionBar {
            editButton
            if row.isInReviews {
                Button(
                    String(
                        localized: "Flag…",
                        comment: "A button of the Cards window that flags the card, asking for a note on what to fix."
                    )
                ) {
                    startFlagging()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .help(Text("Flag… (⇧⌘L)", comment: "The tooltip of the Cards window's button that flags the card."))
            }
            buryButton(for: [row])
            deleteButton
            Spacer()
        }
    }

    /// What the detail says when Lucas selected several cards: how many, with
    /// Bury or Unbury when it works on all of them, and Delete. No sidebar
    /// item lists buried cards with others, so one of the first two always
    /// does.
    private func selectionSummary(_ rows: [CardRow]) -> some View {
        ContentUnavailableView {
            Label(
                String(
                    localized: "\(rows.count) cards selected",
                    comment: "In the Cards window's detail, when Lucas selected several cards in the table."),
                systemImage: "rectangle.stack")
        } actions: {
            buryButton(for: rows)
            deleteButton
        }
    }

    /// Delete…, which asks whether to delete the selected cards for good:
    /// ⌘⌫, as Discard… for a capture, since a card's detail and a capture's
    /// never show together. While Lucas is in the search field, ⌘⌫ is the
    /// field's, as in any text field: it deletes what he typed.
    private var deleteButton: some View {
        Button(
            String(
                localized: "Delete…",
                comment: "A button of the Cards window that deletes the selected cards for good, asking first."
            )
        ) {
            startDeleting()
        }
        .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.deleteKey, modifiers: .command))
        .help(Text("Delete… (⌘⌫)", comment: "The tooltip of the Cards window's button that deletes the cards."))
    }

    /// Bury, when none of the cards in `rows` is buried, or Unbury, when all
    /// of them are: ⌘E either way, since the two never show together.
    @ViewBuilder
    private func buryButton(for rows: [CardRow]) -> some View {
        if rows.canBeBuried {
            Button(
                String(
                    localized: "Bury",
                    comment: "A button of the Cards window that buries the selected cards: they leave Lucas's reviews."
                )
            ) {
                burySelection()
            }
            .keyboardShortcut("e", modifiers: .command)
            .help(Text("Bury (⌘E)", comment: "The tooltip of the Cards window's button that buries the cards."))
        } else if rows.canBeUnburied {
            Button(
                String(
                    localized: "Unbury",
                    comment:
                        "A button of the Cards window that unburies the selected cards: each goes back where it was."
                )
            ) {
                unburySelection()
            }
            .keyboardShortcut("e", modifiers: .command)
            .help(Text("Unbury (⌘E)", comment: "The tooltip of the Cards window's button that unburies the cards."))
        }
    }

    /// The selected card, while it's the only one selected.
    private var singleSelectedRow: CardRow? {
        let rows = selectedRows
        return rows.count == 1 ? rows.first : nil
    }

    /// Turns the detail into fields to edit the capture selected in the inbox,
    /// or the selected card, while it's the only one selected.
    private func startEditing() {
        if let capture = selectedInboxRow?.capture {
            editing = .capture(capture)
        } else if let row = singleSelectedRow {
            editing = .card(row.card)
        }
    }

    /// Asks whether to discard the capture selected in the inbox.
    private func startDiscarding() {
        guard let capture = selectedInboxRow?.capture else { return }
        discarding = capture
    }

    /// Discards `capture`, which Lucas confirmed, or says why it couldn't.
    private func discard(_ capture: Capture) {
        do throws(EngineError) {
            try model.discard(capture.id)
        } catch {
            failure = Failure(
                title: LocalizedStringResource(
                    "Couldn't discard the capture", comment: "An alert's title in the Cards window."),
                message: error.messageForCaptureInCardsWindow(
                    ifItLeft: String(
                        localized: """
                            This capture left the inbox outside this window meanwhile, approved or discarded in a \
                            refine session, so there's nothing to discard. The window now shows the inbox as it is.
                            """,
                        comment:
                            "An alert's message in the Cards window, when the capture Lucas discards already left the inbox."
                    )))
        }
    }

    /// Asks for a note to flag the selected card, while it's the only one
    /// selected and it's in Lucas's reviews.
    private func startFlagging() {
        guard let row = singleSelectedRow, row.isInReviews else { return }
        flagging = row
    }

    /// Buries the selected cards, all at once, while none of them is buried,
    /// or says why it couldn't.
    private func burySelection() {
        let rows = selectedRows
        guard !rows.isEmpty, rows.canBeBuried else { return }
        do throws(EngineError) {
            try model.bury(Set(rows.map(\.id)))
        } catch {
            failure = Failure(
                title: LocalizedStringResource(
                    "Couldn't bury \(rows.count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: rows.count))
        }
    }

    /// Unburies the selected cards, all at once, while all of them are
    /// buried, or says why it couldn't.
    private func unburySelection() {
        let rows = selectedRows
        guard !rows.isEmpty, rows.canBeUnburied else { return }
        do throws(EngineError) {
            try model.unbury(Set(rows.map(\.id)))
        } catch {
            failure = Failure(
                title: LocalizedStringResource(
                    "Couldn't unbury \(rows.count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: rows.count))
        }
    }

    /// Asks whether to delete the selected cards.
    private func startDeleting() {
        let rows = selectedRows
        guard !rows.isEmpty else { return }
        deleting = rows
    }

    /// Deletes the cards in `rows`, which Lucas confirmed, all at once, or
    /// says why it couldn't.
    private func delete(_ rows: [CardRow]) {
        do throws(EngineError) {
            try model.delete(Set(rows.map(\.id)))
        } catch {
            failure = Failure(
                title: LocalizedStringResource(
                    "Couldn't delete \(rows.count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: rows.count))
        }
    }

    /// The title of the question before Lucas deletes the cards in `rows`:
    /// the card's front when it's one, or how many when they're several.
    private func deletionTitle(for rows: [CardRow]) -> Text {
        if rows.count == 1, let row = rows.first {
            Text(
                "Delete “\(row.card.front)”?",
                comment: "The title of the Cards window's question before it deletes a card, with its front.")
        } else {
            Text(
                "Delete \(rows.count) cards?",
                comment: "The title of the Cards window's question before it deletes several cards, with how many.")
        }
    }

    /// What the question before Lucas deletes the cards in `rows` says under
    /// its title: that their review logs go too, and for good.
    private func deletionMessage(for rows: [CardRow]) -> Text {
        if rows.count == 1 {
            Text(
                "Its review log goes too, and you can't bring it back.",
                comment: "Under the title of the Cards window's question before it deletes a card.")
        } else {
            Text(
                "Their review logs go too, and you can't bring them back.",
                comment: "Under the title of the Cards window's question before it deletes several cards.")
        }
    }
}

/// What the Cards window's sidebar offers, one at a time: a group of cards,
/// or the inbox.
private enum SidebarItem: Hashable {
    case cards(CardGroup)
    case inbox
}

/// What the Cards window's table lists: the cards of a group, or what waits
/// in the inbox.
private enum Listing {
    case cards([CardRow])
    case inbox([InboxRow])
}

/// What Lucas edits in the Cards window: a card, or a capture in the inbox.
private enum Editing {
    case card(Card)
    case capture(Capture)
}

/// A card's review log, as the Cards window's detail shows it under the
/// card, or why it couldn't be read.
private struct CardReviewLog {
    let cardID: Int64
    let rows: Result<[ReviewLogRow], EngineError>
}

extension [CardRow] {
    /// Whether Bury works on all these cards: none of them is buried.
    fileprivate var canBeBuried: Bool {
        allSatisfy { $0.card.buriedAt == nil }
    }

    /// Whether Unbury works on all these cards: every one of them is buried.
    fileprivate var canBeUnburied: Bool {
        allSatisfy { $0.card.buriedAt != nil }
    }
}

extension EngineError {
    /// Why an action on `count` cards in the Cards window failed, as its alert
    /// says it. An error that says a card isn't as the window showed it means
    /// the card changed outside the window meanwhile, since the window offers
    /// each action only to the cards it works on. The engine's message for it
    /// names the card by its id, which the window doesn't show, and says what
    /// to do in the CLI or the review panel.
    fileprivate func messageInCardsWindow(actingOn count: Int) -> String {
        switch self {
        case .cardNotFound, .cardFlagged, .cardNotFlagged, .cardBuried, .cardNotBuried:
            String(
                localized: """
                    One of the \(count) cards changed outside this window meanwhile, in the review panel or a \
                    refine session, so nothing was saved. The window now shows them as they are: check them and \
                    try again.
                    """,
                comment: "An alert's message in the Cards window, under what couldn't be done with the selected cards."
            )
        case .migratedByNewerVersion, .emptyCapture, .captureNotInInbox, .notAnExpansion, .noCards, .cardNotNew,
            .cardStillNew, .cardNotDue, .cardNotInAppearance, .cannotUndo, .unreadableReviewLog, .storage:
            localizedDescription
        }
    }

    /// Why an action on a capture in the Cards window's inbox failed, as its
    /// alert says it: `message` when the error says the capture isn't in the
    /// inbox, which means a refine session took it out meanwhile, since the
    /// window offers its actions only to what waits there. The engine's
    /// message for it names the capture by its id, which the window doesn't
    /// show.
    fileprivate func messageForCaptureInCardsWindow(ifItLeft message: String) -> String {
        switch self {
        case .captureNotInInbox:
            message
        case .migratedByNewerVersion, .emptyCapture, .notAnExpansion, .noCards, .cardNotFound, .cardNotNew,
            .cardStillNew, .cardNotDue, .cardNotInAppearance, .cardFlagged, .cardNotFlagged, .cardBuried,
            .cardNotBuried, .cannotUndo, .unreadableReviewLog, .storage:
            localizedDescription
        }
    }
}

/// The sheet that asks for Lucas's note on what to fix in the card he flags,
/// as the review panel asks for it: Return flags the card, Option-Return
/// starts a new line, and Escape cancels. A blank note can't flag it. When
/// the card can't be flagged, an alert says why, and the sheet keeps the note.
private struct FlagSheet: View {
    let card: Card
    /// Flags the card with the note, or throws why it couldn't.
    let flag: (FlagNote) throws(EngineError) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var failure: Failure?
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Flag “\(card.front)”",
                    comment: "The title of the Cards window's sheet that flags a card, with the card's front."
                )
                .font(.headline)
                Text(
                    "It waits in the inbox, out of your reviews, until it's fixed.",
                    comment: "Under the title of the Cards window's sheet that flags a card."
                )
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField("Note", text: $note, prompt: Text("What needs fixing?"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .focused($noteIsFocused)
                // A focused text field keeps Return from reaching the default
                // button.
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    Text("Flag", comment: "The button that flags the card with the note written above it.")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(FlagNote(note) == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            noteIsFocused = true
        }
        .failureAlert($failure)
    }

    /// Flags the card with the note, unless it's blank, and closes the sheet.
    private func submit() {
        guard let note = FlagNote(note) else { return }
        do throws(EngineError) {
            try flag(note)
            dismiss()
        } catch {
            failure = Failure(title: "Couldn't flag the card", message: error.messageInCardsWindow(actingOn: 1))
        }
    }
}

extension CardGroup {
    /// The group's name in the sidebar.
    fileprivate var title: String {
        switch self {
        case .all:
            String(
                localized: "All cards",
                comment: "An item of the Cards window's sidebar: every card but the buried ones.")
        case .new:
            String(localized: "New", comment: "An item of the Cards window's sidebar: the cards not seen yet.")
        case .due:
            String(localized: "Due", comment: "An item of the Cards window's sidebar: the cards due now.")
        case .learned:
            String(localized: "Learned", comment: "An item of the Cards window's sidebar: the learned cards.")
        case .flagged:
            String(localized: "Flagged", comment: "An item of the Cards window's sidebar: the flagged cards.")
        case .buried:
            String(localized: "Buried", comment: "An item of the Cards window's sidebar: the buried cards.")
        case .tag(let tag):
            tag
        case .type(let type):
            type.pluralName
        }
    }

    /// The group's icon, in the sidebar and when it has no cards.
    fileprivate var symbol: String {
        switch self {
        case .all: "rectangle.stack"
        case .new: "sparkles"
        case .due: "clock"
        case .learned: "checkmark.seal"
        case .flagged: "flag"
        case .buried: "eye.slash"
        case .tag: "tag"
        case .type(let type): type.symbol
        }
    }

    /// What the table says when the group has no cards.
    fileprivate var emptyTitle: String {
        switch self {
        case .all:
            String(localized: "No cards", comment: "In the Cards window: no card that isn't buried.")
        case .new:
            String(localized: "No new cards", comment: "In the Cards window: no card waits for its first view.")
        case .due:
            String(localized: "No cards due", comment: "In the Cards window: no card is due now.")
        case .learned:
            String(localized: "No learned cards", comment: "In the Cards window: no card is learned yet.")
        case .flagged:
            String(localized: "No flagged cards", comment: "In the Cards window: no card is flagged.")
        case .buried:
            String(localized: "No buried cards", comment: "In the Cards window: no card is buried.")
        case .tag(let tag):
            String(
                localized: "No cards tagged \(tag)",
                comment: "In the Cards window: no card that isn't buried has this tag anymore.")
        case .type(.word):
            String(localized: "No words", comment: "In the Cards window: no word card that isn't buried.")
        case .type(.concept):
            String(localized: "No concepts", comment: "In the Cards window: no concept card that isn't buried.")
        case .type(.quote):
            String(localized: "No quotes", comment: "In the Cards window: no quote card that isn't buried.")
        case .type(.question):
            String(localized: "No questions", comment: "In the Cards window: no question card that isn't buried.")
        }
    }
}

/// How one of the window's tables orders its rows: by one column, either way.
nonisolated private protocol ColumnOrder: SortComparator {}

nonisolated extension ColumnOrder {
    /// How two values compare, the table's way.
    fileprivate func ordered<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        ordered(lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame)
    }

    /// How two values that compare as `result` do, the table's way.
    fileprivate func ordered(_ result: ComparisonResult) -> ComparisonResult {
        switch (result, order) {
        case (.orderedAscending, .reverse): .orderedDescending
        case (.orderedDescending, .reverse): .orderedAscending
        default: result
        }
    }

    /// How two values that may be missing compare, the table's way: as
    /// `compare` says once both are there, and a missing one after one
    /// that's there, whichever way the table is ordered.
    fileprivate func ordered<Value>(
        _ lhs: Value?, _ rhs: Value?, by compare: (Value, Value) -> ComparisonResult
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        case (let lhs?, let rhs?): ordered(compare(lhs, rhs))
        }
    }
}

/// How the table orders its cards: by one column, either way. Cards with
/// nothing in the column, like a new card in Due and Last seen, go after the
/// others, whichever way the table is ordered. The app's preferences keep it
/// by its column's name, so the window opens in the order Lucas left it in.
nonisolated struct CardRowOrder: ColumnOrder, Codable {
    /// A column the table sorts by. Its raw value is how the preferences keep
    /// the order, and its table column's customization ID, so it never
    /// changes.
    enum Column: String, Codable {
        /// When Lucas approved the card, and then, for cards approved
        /// together, the order he approved them in.
        case created
        case front
        case step
        case due
        /// By what the Type column says, alphabetically.
        case type
        /// By the card's tags, alphabetically: by their first tags, then by
        /// their second ones, and so on.
        case tags
        case source
        case lastSeen
    }

    /// The table's order until Lucas clicks a column's header: the newest
    /// cards first, so that after a refine session he sees what he just
    /// approved.
    static let newestFirst = [CardRowOrder(.created, order: .reverse)]

    let column: Column
    var order: SortOrder

    init(_ column: Column, order: SortOrder = .forward) {
        self.column = column
        self.order = order
    }

    func compare(_ lhs: CardRow, _ rhs: CardRow) -> ComparisonResult {
        switch column {
        case .created:
            lhs.card.createdAt == rhs.card.createdAt
                ? ordered(lhs.card.id, rhs.card.id) : ordered(lhs.card.createdAt, rhs.card.createdAt)
        case .front:
            ordered(lhs.card.front.localizedStandardCompare(rhs.card.front))
        case .step:
            ordered(lhs.stepNumber, rhs.stepNumber)
        case .due:
            ordered(lhs.due, rhs.due) { $0.compare($1) }
        case .type:
            ordered(lhs.card.type.name.localizedStandardCompare(rhs.card.type.name))
        case .tags:
            ordered(lhs.tagsIfAny, rhs.tagsIfAny, by: alphabetically)
        case .source:
            ordered(lhs.card.source, rhs.card.source) { $0.localizedStandardCompare($1) }
        case .lastSeen:
            ordered(lhs.lastSeen, rhs.lastSeen) { $0.compare($1) }
        }
    }
}

extension CardRow {
    /// The card's step counted from 1, as Settings counts them, or 0 while
    /// it's new, before the first step.
    nonisolated fileprivate var stepNumber: Int {
        step.map { $0 + 1 } ?? 0
    }

    /// The card's tags, or nil when it has none.
    nonisolated fileprivate var tagsIfAny: [String]? {
        card.tags.isEmpty ? nil : card.tags
    }
}

/// How two lists of tags compare, alphabetically: by their first tags, then
/// by their second ones, and so on, a list that starts another going first.
nonisolated private func alphabetically(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
    for (left, right) in zip(lhs, rhs) {
        let result = left.localizedStandardCompare(right)
        if result != .orderedSame {
            return result
        }
    }
    return lhs.count == rhs.count ? .orderedSame : lhs.count < rhs.count ? .orderedAscending : .orderedDescending
}

/// How the inbox's table orders its rows: by one column, either way.
nonisolated private struct InboxRowOrder: ColumnOrder {
    enum Column: Hashable {
        case text
        /// By what the Kind column says, alphabetically.
        case kind
        case added
    }

    let column: Column
    var order: SortOrder

    init(_ column: Column, order: SortOrder = .forward) {
        self.column = column
        self.order = order
    }

    func compare(_ lhs: InboxRow, _ rhs: InboxRow) -> ComparisonResult {
        switch column {
        case .text: ordered(lhs.text.localizedStandardCompare(rhs.text))
        case .kind: ordered(lhs.kindName.localizedStandardCompare(rhs.kindName))
        case .added: ordered(lhs.addedAt, rhs.addedAt)
        }
    }
}

extension InboxRow {
    /// What kind of row it is, as the inbox's Kind column says it. Each kind
    /// has a key of its own, since "Capture" is also the capture window's
    /// title, and "Flagged" the sidebar's group, which a translation may word
    /// apart.
    nonisolated fileprivate var kindName: String {
        switch item {
        case .capture:
            String(
                localized: "inbox-kind.capture", defaultValue: "Capture",
                comment: "In the Cards window's inbox, the kind of a row: a capture.")
        case .expansion:
            String(
                localized: "inbox-kind.expansion", defaultValue: "Expansion",
                comment: "In the Cards window's inbox, the kind of a row: a capture attached to the card it repeats.")
        case .flaggedCard:
            String(
                localized: "inbox-kind.flagged", defaultValue: "Flagged",
                comment: "In the Cards window's inbox, the kind of a row: a flagged card.")
        }
    }

    /// The card it expands, when it's an expansion.
    fileprivate var expandedCard: Card? {
        guard case .expansion(let expansion) = item else {
            return nil
        }
        return expansion.card
    }
}

/// The card's front, after a flag when it's flagged and a mark when it's
/// buried.
private struct FrontCell: View {
    let card: Card

    var body: some View {
        HStack(spacing: 4) {
            if card.flag != nil {
                FlagIcon()
            }
            if card.buriedAt != nil {
                BuriedIcon()
            }
            Text(card.front)
                .lineLimit(1)
        }
    }
}

/// The flag beside a flagged card, in the table and the detail.
private struct FlagIcon: View {
    var body: some View {
        Image(systemName: "flag.fill")
            .foregroundStyle(.orange)
            .accessibilityLabel(Text("Flagged", comment: "The flag icon beside a flagged card, in the Cards window."))
            .help(Text("Flagged", comment: "The flag icon beside a flagged card, in the Cards window."))
    }
}

/// The mark beside a buried card, in the table and the detail: the icon the
/// review panel's Bury button has.
private struct BuriedIcon: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Buried", comment: "The icon beside a buried card, in the Cards window."))
            .help(Text("Buried", comment: "The icon beside a buried card, in the Cards window."))
    }
}

/// The selected card, whole: Lucas's note on top when it's flagged, and when
/// he buried it when it's buried, its type and tags, its front, back and
/// source, where it stands, and its review log, in a chart and in full.
private struct CardDetail: View {
    let row: CardRow
    /// The engine's time, which the due time counts from.
    let now: Date
    /// The card's review log, oldest first, or why it couldn't be read, or
    /// nil until it's read.
    let reviewLog: Result<[ReviewLogRow], EngineError>?
    /// The ladder Lucas set, whose steps the chart spans.
    let ladder: Ladder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlagAndBurial(card: row.card)
                TypeAndTags(card: row.card)
                Text(row.card.front)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.card.back)
                    .fixedSize(horizontal: false, vertical: true)
                if let source = row.card.source {
                    Text(source)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                standing
                switch reviewLog {
                case .success(let rows):
                    Divider()
                    ReviewLogView(rows: rows, ladder: ladder)
                case .failure(let error):
                    Divider()
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                case nil:
                    EmptyView()
                }
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Where the card stands: its step and wait, when it's due, when Lucas
    /// last saw it and when he approved it.
    private var standing: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                gridLabel(
                    Text("Step", comment: "In the Cards window's detail: the card's step on the ladder, and its wait."))
                Text(stepText(row))
            }
            if let due = row.due {
                GridRow {
                    gridLabel(Text("Due", comment: "In the Cards window's detail: when the card is due."))
                    HStack(spacing: 6) {
                        Text(dueText(row, at: now))
                        Text(due.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let lastSeen = row.lastSeen {
                GridRow {
                    gridLabel(
                        Text(
                            "Last seen",
                            comment:
                                "In the Cards window's detail: when Lucas last saw the card, in a first view or a review."
                        ))
                    Text(lastSeen.formatted(date: .abbreviated, time: .shortened))
                }
            }
            GridRow {
                gridLabel(Text("Created", comment: "In the Cards window's detail: when Lucas approved the card."))
                Text(row.card.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }
}

/// A word in a capsule of the window's tint, on top of a detail: a card's
/// type, or what kind of capture it is.
private struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: .capsule)
    }
}

/// A card's type, and its tags after it when it has any.
private struct TypeAndTags: View {
    let card: Card

    var body: some View {
        HStack(spacing: 8) {
            Chip(text: card.type.name)
            if !card.tags.isEmpty {
                Label(card.tags.formatted(.list(type: .and, width: .narrow)), systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The capture selected in the inbox, whole: what kind it is, its text, its
/// note and source, when Lucas captured it, and, for an expansion, the card
/// it expands.
private struct CaptureDetail: View {
    let capture: Capture
    /// What kind it is, as the inbox's Kind column says it.
    let kind: String
    /// The card it expands, when it's an expansion.
    let expandedCard: Card?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Chip(text: kind)
                Text(capture.text)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    if let note = capture.note {
                        GridRow {
                            gridLabel(
                                Text("Note", comment: "In the Cards window's detail: what Lucas noted with a capture."))
                            Text(note)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let source = capture.source {
                        GridRow {
                            gridLabel(
                                Text(
                                    "Source",
                                    comment: "In the Cards window's detail: where Lucas came across a capture's text."))
                            Text(source)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    GridRow {
                        gridLabel(Text("Captured", comment: "In the Cards window's detail: when Lucas captured it."))
                        Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let expandedCard {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "Expands this card",
                            comment: "In the Cards window's detail of an expansion, above the card it's attached to."
                        )
                        .foregroundStyle(.secondary)
                        ExpandedCard(card: expandedCard)
                    }
                }
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The card an expansion expands, in the expansion's detail: its type and
/// tags, its front, with the marks the table gives it, and its back.
private struct ExpandedCard: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TypeAndTags(card: card)
            FrontCell(card: card)
                .font(.headline)
            Text(card.back)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 8))
    }
}

/// What the detail says on top of a card that's out of Lucas's reviews: his
/// note when it's flagged, and when he buried it when it's buried. While he
/// edits a flagged card, the note also says that saving fixes it.
private struct FlagAndBurial: View {
    let card: Card
    /// Whether Lucas is editing the card.
    var isEditing = false

    var body: some View {
        if let flag = card.flag {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(flag.note)
                    if isEditing {
                        // The same whether the card is buried or not: whether
                        // it goes back to Lucas's reviews is FichaData's to
                        // say, and the burial shows below.
                        Text(
                            "Saving fixes it, and it keeps its step.",
                            comment: "In the Cards window, under Lucas's note on a flagged card, while he edits it."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                FlagIcon()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
        }
        if let buriedAt = card.buriedAt {
            Label {
                Text(
                    "Buried on \(buriedAt.formatted(date: .abbreviated, time: .shortened))",
                    comment: "In the Cards window's detail: when Lucas buried the card, like Oct 14, 2026 at 9:00 AM."
                )
            } icon: {
                BuriedIcon()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: .rect(cornerRadius: 8))
        }
    }
}

/// The fields Lucas edits a card in, in place of its detail: its type,
/// front, back, tags and source, under his note when it's flagged. Return
/// saves, Option-Return starts a new line, and Escape cancels, as in the
/// capture window, unless he's in the window's search field. Saving with the
/// front or the back blank says, under it, what's missing. When the card
/// can't be saved, an alert says why, and the fields stay as Lucas left them.
private struct CardEditor: View {
    /// The card as it was when Lucas started editing it.
    let card: Card
    /// Whether Lucas is in the window's search field, which then keeps Return
    /// and Escape: Escape there clears the search, and leaves his edit alone.
    let isSearching: Bool
    /// Saves the card with `content`, or throws why it couldn't.
    let save: (CardContent) throws(EngineError) -> Void
    /// Ends the edit, once the card is saved or without saving it.
    let close: () -> Void
    @State private var type: CardType
    @State private var front: String
    @State private var back: String
    /// The card's tags as the Tags field holds them, separated by commas.
    @State private var tagsText: String
    @State private var source: String
    /// Whether Lucas tried to save with the front or the back blank, so that
    /// the blank one says it's missing.
    @State private var showsMissingSides = false
    @State private var failure: Failure?
    @FocusState private var isFrontFocused: Bool

    init(
        card: Card,
        isSearching: Bool,
        save: @escaping (CardContent) throws(EngineError) -> Void,
        close: @escaping () -> Void
    ) {
        self.card = card
        self.isSearching = isSearching
        self.save = save
        self.close = close
        _type = State(initialValue: card.type)
        _front = State(initialValue: card.front)
        _back = State(initialValue: card.back)
        _tagsText = State(initialValue: card.tags.joined(separator: ", "))
        _source = State(initialValue: card.source ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlagAndBurial(card: card, isEditing: true)
                fields
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EditorActions(isSearching: isSearching, cancel: close, save: submit)
        }
        .onAppear {
            isFrontFocused = true
        }
        .failureAlert($failure)
    }

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                let label = Text(
                    "Type", comment: "In the Cards window, the label of a card's type, while Lucas edits it.")
                gridLabel(label)
                Picker(selection: $type) {
                    ForEach(CardType.allCases, id: \.self) { type in
                        Text(type.name)
                            .tag(type)
                    }
                } label: {
                    label
                }
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                gridLabel(
                    Text("Front", comment: "In the Cards window, the label of a card's front, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Front", text: $front, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($isFrontFocused)
                    if showsMissingSides && CardContent.isBlank(front) {
                        missing(
                            Text(
                                "A card needs a front.",
                                comment: "In the Cards window, under a card's front, when Lucas saves it blank."))
                    }
                }
            }
            GridRow {
                gridLabel(
                    Text("Back", comment: "In the Cards window, the label of a card's back, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Back", text: $back, axis: .vertical)
                        .lineLimit(4...12)
                    if showsMissingSides && CardContent.isBlank(back) {
                        missing(
                            Text(
                                "A card needs a back.",
                                comment: "In the Cards window, under a card's back, when Lucas saves it blank."))
                    }
                }
            }
            GridRow {
                gridLabel(
                    Text("Tags", comment: "In the Cards window, the label of a card's tags, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Tags", text: $tagsText)
                    Text(
                        "Separate tags with commas.",
                        comment: "In the Cards window, under a card's tags, while Lucas edits it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            GridRow {
                gridLabel(
                    Text("Source", comment: "In the Cards window, the label of a card's source, while Lucas edits it."))
                TextField(
                    "Source", text: $source,
                    prompt: Text(
                        "A book, a podcast…",
                        comment: "In the Cards window, in a card's empty source, while Lucas edits it."),
                    axis: .vertical
                )
                .lineLimit(1...3)
            }
        }
        .textFieldStyle(.roundedBorder)
        // A focused text field keeps Return from reaching the default button.
        .onSubmit(submit)
    }

    /// The tags in the Tags field, which `CardContent` cleans up as it does
    /// wherever a card comes from.
    private var tags: [String] {
        tagsText.split(separator: ",").map(String.init)
    }

    /// Saves the card with what the fields hold, unless the front or the back
    /// is blank, and ends the edit.
    private func submit() {
        guard let content = CardContent(type: type, front: front, back: back, tags: tags, source: source) else {
            showsMissingSides = true
            return
        }
        do throws(EngineError) {
            try save(content)
            close()
        } catch {
            failure = Failure(
                title: LocalizedStringResource(
                    "Couldn't save the card", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: 1))
        }
    }
}

/// The fields Lucas edits a capture in, in place of its detail: its text,
/// note and source, as the capture window has them. Return saves,
/// Option-Return starts a new line, and Escape cancels, as in the capture
/// window, unless he's in the window's search field. Saving with the text
/// blank says, under it, that it's missing. When the capture can't be saved,
/// an alert says why, and the fields stay as Lucas left them.
private struct CaptureEditor: View {
    /// The capture as it was when Lucas started editing it.
    let capture: Capture
    /// Whether Lucas is in the window's search field, which then keeps Return
    /// and Escape, as `CardEditor` says.
    let isSearching: Bool
    /// Saves the capture with what the fields hold, its text, note and
    /// source, or throws why it couldn't.
    let save: (String, String, String) throws(EngineError) -> Void
    /// Ends the edit, once the capture is saved or without saving it.
    let close: () -> Void
    @State private var text: String
    @State private var note: String
    @State private var source: String
    /// Whether Lucas tried to save with the text blank, so that it says it's
    /// missing.
    @State private var showsMissingText = false
    @State private var failure: Failure?
    @FocusState private var isTextFocused: Bool

    init(
        capture: Capture,
        isSearching: Bool,
        save: @escaping (String, String, String) throws(EngineError) -> Void,
        close: @escaping () -> Void
    ) {
        self.capture = capture
        self.isSearching = isSearching
        self.save = save
        self.close = close
        _text = State(initialValue: capture.text)
        _note = State(initialValue: capture.note ?? "")
        _source = State(initialValue: capture.source ?? "")
    }

    var body: some View {
        ScrollView {
            fields
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EditorActions(isSearching: isSearching, cancel: close, save: submit)
        }
        .onAppear {
            isTextFocused = true
        }
        .failureAlert($failure)
    }

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                gridLabel(
                    Text("Text", comment: "In the Cards window, the label of a capture's text, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Text", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isTextFocused)
                    if showsMissingText && !fieldsMakeACapture {
                        missing(
                            Text(
                                "A capture needs a text.",
                                comment: "In the Cards window, under a capture's text, when Lucas saves it blank."))
                    }
                }
            }
            GridRow {
                gridLabel(
                    Text("Note", comment: "In the Cards window, the label of a capture's note, while Lucas edits it."))
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }
            GridRow {
                gridLabel(
                    Text(
                        "Source", comment: "In the Cards window, the label of a capture's source, while Lucas edits it."
                    ))
                TextField(
                    "Source", text: $source,
                    prompt: Text(
                        "A book, a podcast…",
                        comment: "In the Cards window, in a capture's empty source, while Lucas edits it."),
                    axis: .vertical
                )
                .lineLimit(1...3)
            }
        }
        .textFieldStyle(.roundedBorder)
        // A focused text field keeps Return from reaching the default button.
        .onSubmit(submit)
    }

    /// Whether the fields hold a capture, by the rule the engine saves it
    /// with: until there's text, they don't.
    private var fieldsMakeACapture: Bool {
        CaptureContent(text: text, note: note, source: source) != nil
    }

    /// Saves the capture with what the fields hold, unless the text is blank,
    /// and ends the edit.
    private func submit() {
        guard fieldsMakeACapture else {
            showsMissingText = true
            return
        }
        do throws(EngineError) {
            try save(text, note, source)
            close()
        } catch {
            failure = Failure(
                title: LocalizedStringResource(
                    "Couldn't save the capture", comment: "An alert's title in the Cards window."),
                message: error.messageForCaptureInCardsWindow(
                    ifItLeft: String(
                        localized: """
                            This capture left the inbox outside this window meanwhile, approved or discarded in a \
                            refine session, so nothing was saved. To keep what you typed, copy it before you cancel.
                            """,
                        comment:
                            "An alert's message in the Cards window, when the capture Lucas saves already left the inbox."
                    )))
        }
    }
}

/// What's missing, under a field Lucas left blank in one of the editors.
private func missing(_ text: Text) -> some View {
    text
        .font(.caption)
        .foregroundStyle(.red)
}

/// Cancel and Save, at the foot of an editor: Escape cancels and Return saves,
/// unless Lucas is in the window's search field, which then keeps them, so
/// that Escape there clears the search and leaves his edit alone.
private struct EditorActions: View {
    /// Whether Lucas is in the window's search field.
    let isSearching: Bool
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        ActionBar {
            Spacer()
            Button("Cancel", action: cancel)
                .keyboardShortcut(isSearching ? nil : .cancelAction)
            Button("Save", action: save)
                .keyboardShortcut(isSearching ? nil : .defaultAction)
        }
    }
}

/// The bar at the foot of the detail, always in sight, with what Lucas can
/// do there.
private struct ActionBar<Buttons: View>: View {
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                buttons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}

extension KeyEquivalent {
    /// The Delete key, ⌫, as macOS says it types: U+007F. A button's shortcut
    /// takes a key only as its event spells it, and SwiftUI's own `.delete` is
    /// U+0008, so ⌘⌫ never reached Discard with it in `make render`, which
    /// makes keys as the keyboard does.
    fileprivate static let deleteKey = KeyEquivalent("\u{7F}")
}

extension View {
    /// The view, dimmed and taking no clicks while `isWaiting`: the sidebar
    /// and the table, while Lucas edits a card or a capture.
    fileprivate func waiting(while isWaiting: Bool) -> some View {
        disabled(isWaiting)
            .opacity(isWaiting ? 0.5 : 1)
    }
}

/// A label in one of the detail's grids, before what it names: secondary, and
/// aligned to the trailing edge of its column.
private func gridLabel(_ text: Text) -> some View {
    text
        .foregroundStyle(.secondary)
        .gridColumnAlignment(.trailing)
}

/// The card's step counted from 1, as Settings counts them, with its wait,
/// like "4 · 5d", or "New" before its first view.
private func stepText(_ row: CardRow) -> String {
    guard let step = row.step, let wait = row.wait else {
        return String(localized: "New", comment: "In the Cards window: a card that hasn't had its first view yet.")
    }
    let waitText = wait.formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow))
    return String(
        localized: "\(step + 1) · \(waitText)",
        comment:
            "In the Cards window: the card's step on the ladder, counted from 1, and how long it waits, like 4 · 5d."
    )
}

/// When the card is due, counted from `now`: "now" once it's due, however
/// long ago, and before, as the Mac's locale words it, like "in 2h",
/// "tomorrow" or "in 5d" in US English. Nothing while it's new or flagged,
/// since it won't show up then.
private func dueText(_ row: CardRow, at now: Date) -> String {
    guard let due = row.due else {
        return ""
    }
    guard due > now else {
        return String(localized: "now", comment: "In the Cards window's Due column: the card is due.")
    }
    // In the ladder's units, days, hours and minutes, as Settings shows its
    // waits: "in 8d", never "next week".
    var style = Date.AnchoredRelativeFormatStyle(anchor: due, presentation: .named, unitsStyle: .narrow)
    style.allowedFields = [.day, .hour, .minute]
    return style.format(now)
}

extension CardType {
    /// The type's name, as the Cards window shows it, and as its table sorts
    /// by it.
    nonisolated fileprivate var name: String {
        switch self {
        case .word: String(localized: "Word", comment: "A card type.")
        case .concept: String(localized: "Concept", comment: "A card type.")
        case .quote: String(localized: "Quote", comment: "A card type.")
        case .question: String(localized: "Question", comment: "A card type.")
        }
    }

    /// The type's cards, as the Cards window's sidebar names them.
    fileprivate var pluralName: String {
        switch self {
        case .word: String(localized: "Words", comment: "An item of the Cards window's sidebar: the word cards.")
        case .concept:
            String(localized: "Concepts", comment: "An item of the Cards window's sidebar: the concept cards.")
        case .quote: String(localized: "Quotes", comment: "An item of the Cards window's sidebar: the quote cards.")
        case .question:
            String(localized: "Questions", comment: "An item of the Cards window's sidebar: the question cards.")
        }
    }

    /// The type's icon, in the Cards window's sidebar.
    fileprivate var symbol: String {
        switch self {
        case .word: "textformat"
        case .concept: "lightbulb"
        case .quote: "quote.opening"
        case .question: "questionmark.bubble"
        }
    }
}
