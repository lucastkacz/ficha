import FichaCore
import FichaData
import SwiftUI

/// The Cards window's content, in three panes as Mail lays out its own: a
/// sidebar to choose what to see, a table with one row per card, and the
/// selected card whole beside it. It reads the cards again whenever the
/// engine says they changed, from the app or the `ficha` CLI, when Lucas
/// changes the ladder in Settings, and every minute, since cards come due as
/// time passes.
struct CardsView: View {
    let model: AppModel
    /// The cards the table lists, or why they couldn't be read.
    @State private var rows: Result<[CardRow], EngineError>?
    /// The engine's time when the cards were read, which the Due column
    /// counts from.
    @State private var now: Date
    @State private var sidebarSelection: SidebarItem? = .allCards
    @State private var selection: CardRow.ID?
    /// The table's order: the newest cards first, until Lucas clicks a
    /// column's header.
    @State private var sortOrder = [CardRowOrder(.created, order: .reverse)]

    init(model: AppModel) {
        self.model = model
        _now = State(initialValue: model.now)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Label("All cards", systemImage: "rectangle.stack")
                    .tag(SidebarItem.allCards)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 280)
        } content: {
            table
                .navigationSplitViewColumnWidth(min: 380, ideal: 440)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
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
    }

    /// Reads the cards again, as they are now.
    private func reload() {
        now = model.now
        rows = Result { () throws(EngineError) in try model.cardRows() }
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
                    ContentUnavailableView(
                        "No cards yet", systemImage: "rectangle.stack",
                        description: Text("The cards you approve in a refine session show up here."))
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

    @ViewBuilder
    private var detail: some View {
        if case .success(let rows) = rows, let row = rows.first(where: { $0.id == selection }) {
            CardDetail(row: row, now: now)
        } else {
            ContentUnavailableView("No card selected", systemImage: "rectangle.on.rectangle")
        }
    }
}

/// What the sidebar offers to see.
private enum SidebarItem: Hashable {
    /// Every card that isn't buried.
    case allCards
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
        guard case .onLadder(let step, _) = standing else {
            return 0
        }
        return step + 1
    }
}

/// The card's front, after a mark when it's flagged.
private struct FrontCell: View {
    let card: Card

    var body: some View {
        HStack(spacing: 4) {
            if card.flag != nil {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Flagged", comment: "A mark on a flagged card, in the Cards window."))
                    .help(Text("Flagged", comment: "A mark on a flagged card, in the Cards window."))
            }
            Text(card.front)
                .lineLimit(1)
        }
    }
}

/// The selected card, whole: Lucas's note on top when it's flagged, its type
/// and tags, its front, back and source, and where it stands.
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
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(
                                Text("Flagged", comment: "A mark on a flagged card, in the Cards window."))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
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
    guard case .onLadder(let step, _) = row.standing, let wait = row.wait else {
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
/// long ago, "in 2h", "tomorrow" or "in 5d" before, and nothing while it's
/// new or flagged, since it won't show up then.
private func dueText(_ row: CardRow, at now: Date) -> String {
    guard let due = row.due else {
        return ""
    }
    guard due > now else {
        return String(localized: "now", comment: "In the Cards window's Due column: the card is due.")
    }
    // In the ladder's units, as Settings shows its waits: "in 8d", not
    // "next week".
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
}
