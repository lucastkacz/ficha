import FichaData
import Foundation

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
        /// By what the Type column says, alphabetically, and cards with no
        /// type after the others.
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
            ordered(lhs.card.type?.name, rhs.card.type?.name) { $0.localizedStandardCompare($1) }
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
nonisolated struct InboxRowOrder: ColumnOrder {
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
    /// What kind of row it is, as the inbox's Kind column says it.
    nonisolated var kindName: String {
        item.kindName
    }
}
