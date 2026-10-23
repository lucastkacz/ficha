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
/// can do with all of them. `CardsWindowState` decides what the window lists,
/// shows, offers and asks, and what happens when Lucas acts, and the view
/// draws it. It reads the cards again whenever
/// the engine says they changed, from the app or the `ficha` CLI, when Lucas
/// changes the ladder in Settings, and every minute, since cards come due as
/// time passes, or at once when Ficha Dev's debug menu moves the time.
struct CardsView: View {
    let model: AppModel
    /// What the sidebar chose, what Lucas looks for and selected, and so what
    /// the table lists, the detail shows and its actions offer, and what he
    /// edits, what the window asks and what failed.
    @State private var state: CardsWindowState
    @FocusState private var isSearchFocused: Bool
    /// The table's order: the one Lucas left it in with a click on a column's
    /// header, and at first the newest cards first.
    @State private var sortOrder = Preferences.cardsSortOrder
    /// The table's columns as Lucas left them: which ones show, in what order
    /// and how wide. At first Front, Step and Due, until he adds others from
    /// the headers' menu.
    @State private var columns = Preferences.cardsColumns
    /// The inbox's order: the latest added first, until Lucas clicks a
    /// column's header.
    @State private var inboxSortOrder = [InboxRowOrder(.added, order: .reverse)]
    /// Whether the table has the keyboard, which it gets back once Lucas
    /// saves or cancels an edit, for him to go on with the arrow keys.
    @FocusState private var isTableFocused: Bool

    init(model: AppModel) {
        self.model = model
        _state = State(initialValue: model.openCardsWindow())
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 280)
                .waiting(while: state.editing != nil)
        } content: {
            table
                .navigationSplitViewColumnWidth(min: 380, ideal: 440)
                .waiting(while: state.editing != nil)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        }
        .searchable(text: searchText, placement: .toolbar)
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
        .sheet(item: Binding(get: { cardToFlag }, set: { if $0 == nil { state.cancelQuestion() } })) { row in
            FlagSheet(card: row.card, failure: failure(overFlagSheet: true)) { note in
                state.flag(note: note)
            }
        }
        // Each button acts on what its dialog presents, which SwiftUI hands
        // it: closing the dialog may drop the state's question before the
        // button acts.
        .confirmationDialog(
            captureToDiscard.map {
                Text(
                    "Discard “\($0.text)”?",
                    comment: "The title of the Cards window's question before it discards a capture, with its text.")
            } ?? Text(verbatim: ""),
            isPresented: Binding(get: { captureToDiscard != nil }, set: { if !$0 { state.cancelQuestion() } }),
            titleVisibility: .visible,
            presenting: captureToDiscard
        ) { capture in
            Button(role: .destructive) {
                state.discard(capture)
            } label: {
                Text("Discard", comment: "The button that discards the capture the Cards window asks about.")
            }
        } message: { _ in
            Text(
                "It leaves the inbox without becoming cards, and you can't bring it back.",
                comment: "Under the title of the Cards window's question before it discards a capture.")
        }
        .confirmationDialog(
            cardsToDelete.map { deletionTitle(for: $0) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { cardsToDelete != nil }, set: { if !$0 { state.cancelQuestion() } }),
            titleVisibility: .visible,
            presenting: cardsToDelete
        ) { rows in
            Button(role: .destructive) {
                state.delete(rows)
            } label: {
                Text("Delete", comment: "The button that deletes the cards the Cards window asks about.")
            }
        } message: { rows in
            deletionMessage(for: rows)
        }
        .failureAlert(failure(overFlagSheet: false))
        .task {
            // Listening before reading, so no change falls in between.
            let changes = model.changes()
            readCards()
            for await _ in changes {
                readCards()
            }
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                readCards()
            }
        }
        .onChange(of: model.settings.ladder) {
            readCards()
        }
        .onChange(of: model.debugTools?.timeShift) {
            readCards()
        }
    }

    /// Reads Lucas's cards, as they are now, on the ladder he set in
    /// Settings.
    private func readCards() {
        state.read(on: model.settings.ladder)
    }

    /// The card the window asks Lucas to flag, while the flag sheet asks for
    /// his note.
    private var cardToFlag: CardRow? {
        guard case .flag(let row) = state.question else { return nil }
        return row
    }

    /// The capture the window asks whether to discard, while it asks.
    private var captureToDiscard: Capture? {
        guard case .discard(let capture) = state.question else { return nil }
        return capture
    }

    /// The cards the window asks whether to delete, while it asks.
    private var cardsToDelete: [CardRow]? {
        guard case .delete(let rows) = state.question else { return nil }
        return rows
    }

    /// What Lucas did that couldn't be saved, as an alert says it, which
    /// closing it clears: over the flag sheet while it's open, since the
    /// window's own alert can't show over its sheet, and over the window
    /// otherwise. `overFlagSheet` says which of the two alerts this is for.
    private func failure(overFlagSheet: Bool) -> Binding<Failure?> {
        Binding {
            guard overFlagSheet == (cardToFlag != nil) else { return nil }
            return state.failure.map(alert(for:))
        } set: {
            if $0 == nil {
                state.dismissFailure()
            }
        }
    }

    /// What the alert says when `failure` happened: what Lucas did that
    /// couldn't be saved, and why, in the window's words.
    private func alert(for failure: CardsWindowState.Failure) -> Failure {
        let error = failure.error
        switch failure.action {
        case .saveCard:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't save the card", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: 1))
        case .saveCapture:
            return Failure(
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
        case .discard:
            return Failure(
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
        case .flag:
            return Failure(title: "Couldn't flag the card", message: error.messageInCardsWindow(actingOn: 1))
        case .bury(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't bury \(count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: count))
        case .unbury(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't unbury \(count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: count))
        case .delete(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't delete \(count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: count))
        }
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
            if !state.tags.isEmpty {
                Section {
                    ForEach(state.tags, id: \.name) { tag in
                        Label(tag.name, systemImage: "tag")
                            .tag(SidebarItem.cards(.tag(tag.name)))
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
            state.sidebarItem
        } set: {
            if let item = $0 {
                state.choose(item)
            }
        }
    }

    /// The search field's text: what Lucas looks for.
    private var searchText: Binding<String> {
        Binding {
            state.search
        } set: {
            state.search(for: $0)
        }
    }

    /// What the table says when `group`, or the search in it, brings no
    /// cards.
    @ViewBuilder
    private func noCards(in group: CardGroup) -> some View {
        if state.hasSearch {
            ContentUnavailableView.search(text: state.search)
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
        if state.hasSearch {
            ContentUnavailableView.search(text: state.search)
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
        switch state.listing {
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
            rows.sorted(using: sortOrder), selection: selectedCards, sortOrder: $sortOrder,
            columnCustomization: $columns
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
                Text(dueText(row, at: state.now))
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
            if rows.isEmpty, case .cards(let group) = state.sidebarItem {
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
        Table(rows.sorted(using: inboxSortOrder), selection: selectedInInbox, sortOrder: $inboxSortOrder) {
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

    /// The cards' table's selection: the cards Lucas selected.
    private var selectedCards: Binding<Set<CardRow.ID>> {
        Binding {
            state.selection
        } set: {
            state.select($0)
        }
    }

    /// The inbox's table's selection: the row Lucas selected, one at a time.
    private var selectedInInbox: Binding<InboxRow.ID?> {
        Binding {
            state.inboxSelection
        } set: {
            state.selectInInbox($0)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.editing {
        case .card(let card):
            CardEditor(card: card, isSearching: isSearchFocused) { content in
                state.saveCard(content)
                focusTableOnceEditEnds()
            } cancel: {
                state.cancelEditing()
                focusTableOnceEditEnds()
            }
        case .capture(let capture):
            CaptureEditor(capture: capture, isSearching: isSearchFocused) { text, note, source in
                state.saveCapture(text: text, note: note, source: source)
                focusTableOnceEditEnds()
            } cancel: {
                state.cancelEditing()
                focusTableOnceEditEnds()
            }
        case nil:
            switch state.detail {
            case .capture(let capture):
                CaptureDetail(capture: capture, kind: InboxRow.Item.capture(capture).kindName, expandedCard: nil)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actionBar
                    }
            case .expansion(let expansion):
                CaptureDetail(
                    capture: expansion.capture, kind: InboxRow.Item.expansion(expansion).kindName,
                    expandedCard: expansion.card
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actionBar
                }
            case .cards(let rows):
                selectionSummary(rows)
            case .card(let row, let reviewLog):
                CardDetail(row: row, now: state.now, reviewLog: reviewLog, ladder: state.ladder)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actionBar
                    }
            case .nothingSelectedInInbox:
                ContentUnavailableView(
                    String(
                        localized: "Nothing selected",
                        comment: "In the Cards window's detail, when nothing in the inbox is selected."),
                    systemImage: "tray")
            case .noCardSelected:
                ContentUnavailableView("No card selected", systemImage: "rectangle.on.rectangle")
            }
        }
    }

    /// Gives the table the keyboard back once Lucas's edit ended, saved or
    /// not. A save that failed goes on with the edit, and the keyboard stays
    /// in its fields.
    private func focusTableOnceEditEnds() {
        if state.editing == nil {
            isTableFocused = true
        }
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
            state.startEditing()
        }
        .keyboardShortcut("l", modifiers: .command)
        .help(
            Text(
                "Edit (⌘L)", comment: "The tooltip of the Cards window's button that edits the card or the capture."))
    }

    /// What Lucas can do with the capture or the card the detail shows, at
    /// its foot, always in sight.
    private var actionBar: some View {
        ActionBar {
            actionButtons
            Spacer()
        }
    }

    /// What the detail says when Lucas selected several cards: how many, with
    /// what he can do with all of them.
    private func selectionSummary(_ rows: [CardRow]) -> some View {
        ContentUnavailableView {
            Label(
                String(
                    localized: "\(rows.count) cards selected",
                    comment: "In the Cards window's detail, when Lucas selected several cards in the table."),
                systemImage: "rectangle.stack")
        } actions: {
            actionButtons
        }
    }

    /// A button for each thing Lucas can do with what the detail shows, as
    /// the state offers them: Edit, Flag…, Bury or Unbury, Delete… and
    /// Discard…, in that order. Each button calls the state, which reads the
    /// selection as it is when Lucas acts, never as the button had it: SwiftUI
    /// keeps the action a keyboard shortcut had when its button first showed,
    /// so ⌘E would bury the cards selected back then.
    @ViewBuilder
    private var actionButtons: some View {
        let actions = state.actions
        if actions.contains(.edit) {
            editButton
        }
        if actions.contains(.flag) {
            flagButton
        }
        if actions.contains(.bury) {
            buryButton
        }
        if actions.contains(.unbury) {
            unburyButton
        }
        if actions.contains(.delete) {
            deleteButton
        }
        if actions.contains(.discard) {
            discardButton
        }
    }

    /// Flag…, which asks for Lucas's note on what to fix in the selected
    /// card.
    private var flagButton: some View {
        Button(
            String(
                localized: "Flag…",
                comment: "A button of the Cards window that flags the card, asking for a note on what to fix."
            )
        ) {
            state.askToFlag()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .help(Text("Flag… (⇧⌘L)", comment: "The tooltip of the Cards window's button that flags the card."))
    }

    /// Discard…, which asks whether to discard the capture selected in the
    /// inbox: ⌘⌫, as Delete… for cards, since a card's detail and a
    /// capture's never show together. While Lucas is in the search field, ⌘⌫
    /// is the field's, as in any text field: it deletes what he typed.
    private var discardButton: some View {
        Button(
            String(
                localized: "Discard…",
                comment: "A button of the Cards window that discards the capture, asking first."
            )
        ) {
            state.askToDiscard()
        }
        .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.deleteKey, modifiers: .command))
        .help(Text("Discard… (⌘⌫)", comment: "The tooltip of the Cards window's button that discards the capture."))
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
            state.askToDelete()
        }
        .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.deleteKey, modifiers: .command))
        .help(Text("Delete… (⌘⌫)", comment: "The tooltip of the Cards window's button that deletes the cards."))
    }

    /// Bury, which takes the selected cards out of Lucas's reviews: ⌘E, as
    /// Unbury, since the two never show together.
    private var buryButton: some View {
        Button(
            String(
                localized: "Bury",
                comment: "A button of the Cards window that buries the selected cards: they leave Lucas's reviews."
            )
        ) {
            state.bury()
        }
        .keyboardShortcut("e", modifiers: .command)
        .help(Text("Bury (⌘E)", comment: "The tooltip of the Cards window's button that buries the cards."))
    }

    /// Unbury, which puts each selected card back where it was: ⌘E, as Bury.
    private var unburyButton: some View {
        Button(
            String(
                localized: "Unbury",
                comment:
                    "A button of the Cards window that unburies the selected cards: each goes back where it was."
            )
        ) {
            state.unbury()
        }
        .keyboardShortcut("e", modifiers: .command)
        .help(Text("Unbury (⌘E)", comment: "The tooltip of the Cards window's button that unburies the cards."))
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

private typealias SidebarItem = CardsWindowState.SidebarItem

extension KeyEquivalent {
    /// The Delete key, ⌫, as macOS says it types: U+007F. A button's shortcut
    /// takes a key only as its event spells it, and SwiftUI's own `.delete` is
    /// U+0008, so ⌘⌫ never reached Discard with it in `make render`, which
    /// makes keys as the keyboard does.
    static let deleteKey = KeyEquivalent("\u{7F}")
}

extension View {
    /// The view, dimmed and taking no clicks while `isWaiting`: the sidebar
    /// and the table, while Lucas edits a card or a capture.
    fileprivate func waiting(while isWaiting: Bool) -> some View {
        disabled(isWaiting)
            .opacity(isWaiting ? 0.5 : 1)
    }
}
