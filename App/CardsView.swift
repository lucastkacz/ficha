import FichaCore
import FichaData
import SwiftUI

/// The Cards window's content, in three panes as Mail lays out its own: a
/// sidebar to choose a group of cards, a table with one row per card in it,
/// narrowed by the toolbar's search field, and the selected card whole beside
/// it, with what Lucas can do with it at its foot. He selects several cards
/// with ⌘ or Shift, as in Finder, and then the detail says how many, with what
/// he can do with all of them. It reads the cards again whenever the engine
/// says they changed, from the app or the `ficha` CLI, when Lucas changes the
/// ladder in Settings, and every minute, since cards come due as time passes,
/// or at once when Ficha Dev's debug menu moves the time.
struct CardsView: View {
    let model: AppModel
    /// The cards the table lists, or why they couldn't be read.
    @State private var rows: Result<[CardRow], EngineError>?
    /// The tags the sidebar offers: those of the cards that aren't buried.
    @State private var tags: [String] = []
    /// The engine's time when the cards were read, which the Due column
    /// counts from.
    @State private var now: Date
    /// The group the sidebar chose: All cards, until Lucas picks another.
    @State private var group = CardGroup.all
    /// What Lucas looks for in the group's cards, from the search field.
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    /// The rows Lucas selected, which can include cards the table no longer
    /// lists: the detail and its actions take only those it lists.
    @State private var selection: Set<CardRow.ID> = []
    /// The table's order: the newest cards first, until Lucas clicks a
    /// column's header.
    @State private var sortOrder = [CardRowOrder(.created, order: .reverse)]
    /// The card Lucas is flagging, while the sheet asks for his note.
    @State private var flagging: CardRow?
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
        } content: {
            table
                .navigationSplitViewColumnWidth(min: 380, ideal: 440)
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
        .failureAlert($failure)
        .onChange(of: group) {
            reload()
        }
        .onChange(of: search) {
            reload()
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

    /// Reads the tags and the group's cards again, as they are now. When the
    /// chosen tag is gone, because its last card was buried or edited, the
    /// window goes back to All cards.
    private func reload() {
        now = model.now
        do throws(EngineError) {
            tags = try model.tags()
            if case .tag(let tag) = group, !tags.contains(tag) {
                group = .all
            }
            rows = .success(try model.cardRows(in: group, matching: search))
        } catch {
            rows = .failure(error)
        }
    }

    /// The groups Lucas chooses from: the cards by where they stand, then by
    /// tag, then by type. One is chosen at a time, always.
    private var sidebar: some View {
        List(selection: chosenGroup) {
            Section {
                ForEach([CardGroup.all, .new, .due, .learned, .flagged, .buried], id: \.self) { group in
                    Label(group.title, systemImage: group.symbol)
                        .tag(group)
                }
            }
            if !tags.isEmpty {
                Section {
                    ForEach(tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(CardGroup.tag(tag))
                    }
                } header: {
                    Text("Tags", comment: "A section of the Cards window's sidebar: the cards' tags.")
                }
            }
            Section {
                ForEach(CardType.allCases, id: \.self) { type in
                    Label(type.pluralName, systemImage: type.symbol)
                        .tag(CardGroup.type(type))
                }
            } header: {
                Text("Types", comment: "A section of the Cards window's sidebar: the card types.")
            }
        }
    }

    /// The sidebar's selection: the chosen group, which Lucas can change but
    /// not clear.
    private var chosenGroup: Binding<CardGroup?> {
        Binding {
            group
        } set: {
            group = $0 ?? group
        }
    }

    /// What the table says when the group, or the search in it, brings no
    /// cards.
    @ViewBuilder
    private var noCards: some View {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    @ViewBuilder
    private var table: some View {
        switch rows {
        case .success(let rows):
            Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn(
                    Text("Front", comment: "A column of the Cards window: the card's front."),
                    sortUsing: CardRowOrder(.front)
                ) {
                    row in
                    FrontCell(card: row.card)
                }
                .width(min: 120)
                TableColumn(
                    Text("Step", comment: "A column of the Cards window: the card's step on the ladder, and its wait."),
                    sortUsing: CardRowOrder(.step)
                ) { row in
                    Text(stepText(row))
                }
                .width(min: 56, ideal: 64, max: 100)
                TableColumn(
                    Text("Due", comment: "A column of the Cards window: when the card is due."),
                    sortUsing: CardRowOrder(.due)
                ) { row in
                    Text(dueText(row, at: now))
                }
                .width(min: 60, ideal: 72, max: 110)
            }
            .overlay {
                if rows.isEmpty {
                    noCards
                }
            }
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

    /// The selected cards the table lists, which the detail shows and its
    /// actions act on. The actions read them as they are when Lucas acts,
    /// never as their buttons had them: SwiftUI keeps the action a keyboard
    /// shortcut had when its button first showed, so ⌘E would bury the cards
    /// selected back then.
    private var selectedRows: [CardRow] {
        guard case .success(let rows) = rows else {
            return []
        }
        return rows.filter { selection.contains($0.id) }
    }

    @ViewBuilder
    private var detail: some View {
        let selected = selectedRows
        if selected.count > 1 {
            selectionSummary(selected)
        } else if let row = selected.first {
            CardDetail(row: row, now: now)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actions(for: row)
                }
        } else {
            ContentUnavailableView("No card selected", systemImage: "rectangle.on.rectangle")
        }
    }

    /// What Lucas can do with the selected card, at the foot of its detail,
    /// always in sight: flag it while it's in his reviews, and bury it, or
    /// unbury it once it's buried.
    private func actions(for row: CardRow) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if row.isInReviews {
                    Button(
                        String(
                            localized: "Flag…",
                            comment:
                                "A button of the Cards window that flags the card, asking for a note on what to fix."
                        )
                    ) {
                        startFlagging()
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .help(Text("Flag… (⇧⌘L)", comment: "The tooltip of the Cards window's button that flags the card."))
                }
                buryButton(for: [row])
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    /// What the detail says when Lucas selected several cards: how many, with
    /// Bury or Unbury when it works on all of them. No sidebar item lists
    /// buried cards with others, so one of the two always does.
    private func selectionSummary(_ rows: [CardRow]) -> some View {
        ContentUnavailableView {
            Label(
                String(
                    localized: "\(rows.count) cards selected",
                    comment: "In the Cards window's detail, when Lucas selected several cards in the table."),
                systemImage: "rectangle.stack")
        } actions: {
            buryButton(for: rows)
        }
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

    /// Asks for a note to flag the selected card, while it's the only one
    /// selected and it's in Lucas's reviews.
    private func startFlagging() {
        let rows = selectedRows
        guard rows.count == 1, let row = rows.first, row.isInReviews else { return }
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
            .cardStillNew, .cardNotDue, .cannotUndo, .unreadableReviewLog, .storage:
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

/// How the table orders its rows: by one column, either way. Cards without a
/// due time go after those with one, whichever way the table is ordered by
/// Due.
nonisolated private struct CardRowOrder: SortComparator {
    enum Column: Hashable {
        /// When Lucas approved the card, which no column shows yet, and then,
        /// for cards approved together, the order he approved them in.
        case created
        case front
        case step
        case due
    }

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
            switch (lhs.due, rhs.due) {
            case (nil, nil): .orderedSame
            case (nil, _): .orderedDescending
            case (_, nil): .orderedAscending
            case (let lhs?, let rhs?): ordered(lhs, rhs)
            }
        }
    }

    /// How two values compare, the table's way.
    private func ordered<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        ordered(lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame)
    }

    /// How two values that compare as `result` do, the table's way.
    private func ordered(_ result: ComparisonResult) -> ComparisonResult {
        switch (result, order) {
        case (.orderedAscending, .reverse): .orderedDescending
        case (.orderedDescending, .reverse): .orderedAscending
        default: result
        }
    }
}

extension CardRow {
    /// The card's step counted from 1, as Settings counts them, or 0 while
    /// it's new, before the first step.
    nonisolated fileprivate var stepNumber: Int {
        step.map { $0 + 1 } ?? 0
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
/// source, and where it stands.
private struct CardDetail: View {
    let row: CardRow
    /// The engine's time, which the due time counts from.
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let flag = row.card.flag {
                    Label {
                        Text(flag.note)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        FlagIcon()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
                }
                if let buriedAt = row.card.buriedAt {
                    Label {
                        Text(
                            "Buried on \(buriedAt.formatted(date: .abbreviated, time: .shortened))",
                            comment:
                                "In the Cards window's detail: when Lucas buried the card, like Oct 14, 2026 at 9:00 AM."
                        )
                    } icon: {
                        BuriedIcon()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 8))
                }
                HStack(spacing: 8) {
                    Text(row.card.type.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: .capsule)
                    if !row.card.tags.isEmpty {
                        Label(row.card.tags.formatted(.list(type: .and, width: .narrow)), systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                label(
                    Text("Step", comment: "In the Cards window's detail: the card's step on the ladder, and its wait."))
                Text(stepText(row))
            }
            if let due = row.due {
                GridRow {
                    label(Text("Due", comment: "In the Cards window's detail: when the card is due."))
                    HStack(spacing: 6) {
                        Text(dueText(row, at: now))
                        Text(due.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let lastSeen = row.lastSeen {
                GridRow {
                    label(
                        Text(
                            "Last seen",
                            comment:
                                "In the Cards window's detail: when Lucas last saw the card, in a first view or a review."
                        ))
                    Text(lastSeen.formatted(date: .abbreviated, time: .shortened))
                }
            }
            GridRow {
                label(Text("Created", comment: "In the Cards window's detail: when Lucas approved the card."))
                Text(row.card.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func label(_ text: Text) -> some View {
        text
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
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
    /// The type's name, as the Cards window shows it.
    fileprivate var name: String {
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
