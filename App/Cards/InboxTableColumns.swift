import AppKit
import FichaData

/// The Cards window's inbox's columns, each with its header and its widths
/// in the app's language, which the table draws them at. Kind is measured
/// with its kinds' names and Added with its dates in `.tableDay`. Text
/// narrows below its texts when the table is short of room: a capture is the
/// user's text, often too long for any width. Its header fits, and the app's
/// own texts in every column.
struct InboxTableColumns {
    let text: FittedColumn
    let kind: FittedColumn
    let added: FittedColumn

    /// The columns, with the dates of their cells as they show them at `now`.
    init(now: Date) {
        text = FittedColumn(
            String(
                localized: "Text",
                comment: "A column of the Cards window's inbox: a capture's text, or a flagged card's front."),
            min: 120)
        kind = FittedColumn(
            String(
                localized: "Kind",
                comment:
                    "A column of the Cards window's inbox: whether a row is a capture, an expansion, a follow-up or a card."
            ),
            cells: InboxKind.allCases.map(\.name), min: 64, ideal: 76, max: 110)
        added = FittedColumn(
            String(
                localized: "Added",
                comment: "A column of the Cards window's inbox: when Lucas captured it, or flagged the card."),
            cells: ColumnWidth.dateTexts(.tableDay, inEachMonthOf: now), min: 80, ideal: 96, max: 140)
    }
}

/// How the inbox's table orders its rows: by one column, either way.
nonisolated struct InboxRowOrder: SortComparator {
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
        let result =
            switch column {
            case .text: lhs.text.localizedStandardCompare(rhs.text)
            case .kind: lhs.kindName.localizedStandardCompare(rhs.kindName)
            case .added: lhs.addedAt.compare(rhs.addedAt)
            }
        // The other way round when the table is ordered in reverse.
        return switch (result, order) {
        case (.orderedAscending, .reverse): .orderedDescending
        case (.orderedDescending, .reverse): .orderedAscending
        default: result
        }
    }
}

extension InboxRow {
    /// What kind of row it is, as the inbox's Kind column says it.
    nonisolated var kindName: String {
        item.kindName
    }
}
