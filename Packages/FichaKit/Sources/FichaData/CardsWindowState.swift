import FichaCore
import Foundation

/// The Cards window while it's open: what its sidebar chose, what Lucas looks
/// for and what he selected, what the table lists, read from his cards on the
/// ladder he set in Settings, and so what the detail shows and what Lucas can
/// do with it. It reads his cards whenever the window asks: once the window
/// listens for the reasons to read them again, and then for each of them, the
/// engine's changes, the passing of time, a new ladder in Settings, and Ficha
/// Dev moving the time.
public struct CardsWindowState: Sendable {
    /// What the sidebar offers, one at a time: a group of cards, or the
    /// inbox.
    public enum SidebarItem: Sendable, Hashable {
        case cards(CardGroup)
        case inbox
    }

    /// What the table lists: the cards of a group, or what waits in the
    /// inbox.
    public enum Listing: Sendable, Equatable {
        case cards([CardRow])
        case inbox([InboxRow])
    }

    /// What the detail shows.
    public enum Detail: Sendable, Equatable {
        /// The capture selected in the inbox, whole.
        case capture(Capture)
        /// The expansion selected in the inbox, whole, with the card it
        /// expands.
        case expansion(Expansion)
        /// The selected card, whole, while it's the only one selected, with
        /// its review log, oldest first, or why it couldn't be read: nil only
        /// until it's read.
        case card(CardRow, reviewLog: Result<[ReviewLogRow], EngineError>?)
        /// The cards Lucas selected, when they're several, which the detail
        /// counts.
        case cards([CardRow])
        /// That nothing in the inbox is selected.
        case nothingSelectedInInbox
        /// That no card is selected.
        case noCardSelected
    }

    /// What Lucas can do with what the detail shows.
    public enum Action: Sendable, Hashable {
        /// Edit the card or the capture, in fields that take the detail's
        /// place.
        case edit
        /// Flag the card, with a note on what to fix.
        case flag
        /// Bury the cards.
        case bury
        /// Unbury the cards.
        case unbury
        /// Delete the cards for good, asking first.
        case delete
        /// Discard the capture, asking first.
        case discard
    }

    /// What the sidebar chose: All cards, until Lucas picks another group or
    /// the inbox.
    public private(set) var sidebarItem = SidebarItem.cards(.all)
    /// What Lucas looks for in what the sidebar chose, from the search field.
    public private(set) var search = ""
    /// The cards Lucas selected, which can include cards the table no longer
    /// lists: the detail and the actions take only those it lists.
    public private(set) var selection: Set<CardRow.ID> = []
    /// The row Lucas selected in the inbox, one at a time, which the table
    /// may no longer list, as with the cards.
    public private(set) var inboxSelection: InboxRow.ID?
    /// The review log of the card the detail shows, while it shows one: read
    /// with the cards, and again when Lucas selects another card.
    private var reviewLog: CardReviewLog?
    /// What the table lists, or why it couldn't be read: nil until the window
    /// first reads Lucas's cards.
    public private(set) var listing: Result<Listing, EngineError>?
    /// The tags the sidebar offers: those of the cards that aren't buried.
    public private(set) var tags: [String] = []
    /// The engine's time when the cards were read, which the Due column
    /// counts from.
    public private(set) var now: Date
    /// The ladder Lucas set in Settings, which the cards stand on, and whose
    /// steps a card's review log spans.
    public private(set) var ladder: Ladder
    private let engine: Engine

    init(engine: Engine, ladder: Ladder) {
        self.engine = engine
        self.ladder = ladder
        now = engine.now
    }

    /// Whether Lucas is looking for something, which narrows the table: a
    /// search that isn't blank.
    public var hasSearch: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The selected cards the table lists, which the detail shows and the
    /// actions act on: those Lucas selected in a group of cards, or the
    /// flagged card he selected in the inbox.
    public var selectedRows: [CardRow] {
        switch listing {
        case .success(.cards(let rows)):
            rows.filter { selection.contains($0.id) }
        case .success(.inbox):
            selectedInboxRow?.flaggedCard.map { [$0] } ?? []
        case .failure, nil:
            []
        }
    }

    /// The row Lucas selected in the inbox, while the table lists it.
    private var selectedInboxRow: InboxRow? {
        guard case .success(.inbox(let rows))? = listing else {
            return nil
        }
        return rows.first { $0.id == inboxSelection }
    }

    /// The selected card the table lists, while it's the only one.
    private var shownCard: CardRow? {
        let rows = selectedRows
        return rows.count == 1 ? rows.first : nil
    }

    /// What the detail shows: the capture or the expansion selected in the
    /// inbox, the selected cards the table lists, or that nothing is
    /// selected.
    public var detail: Detail {
        switch selectedInboxRow?.item {
        case .capture(let capture):
            return .capture(capture)
        case .expansion(let expansion):
            return .expansion(expansion)
        case .flaggedCard, nil:
            // A flagged card shows as a card, below.
            break
        }
        let rows = selectedRows
        if rows.count > 1 {
            return .cards(rows)
        } else if let row = shownCard {
            // Never another card's review log.
            return .card(row, reviewLog: reviewLog?.cardID == row.id ? reviewLog?.rows : nil)
        } else if case .inbox = sidebarItem {
            return .nothingSelectedInInbox
        } else {
            return .noCardSelected
        }
    }

    /// What Lucas can do with what the detail shows: with a capture or an
    /// expansion, edit it and discard it; with one card, edit it, flag it
    /// while it's in his reviews, bury or unbury it, and delete it; with
    /// several, bury or unbury them and delete them.
    public var actions: Set<Action> {
        switch detail {
        case .capture, .expansion:
            return [.edit, .discard]
        case .card(let row, _):
            var actions = buryOrUnbury([row]).union([.edit, .delete])
            if row.isInReviews {
                actions.insert(.flag)
            }
            return actions
        case .cards(let rows):
            return buryOrUnbury(rows).union([.delete])
        case .nothingSelectedInInbox, .noCardSelected:
            return []
        }
    }

    /// Bury, when none of the cards in `rows` is buried, or Unbury, when all
    /// of them are, or neither, so that one action never does half its job.
    private func buryOrUnbury(_ rows: [CardRow]) -> Set<Action> {
        if rows.allSatisfy({ $0.card.buriedAt == nil }) {
            [.bury]
        } else if rows.allSatisfy({ $0.card.buriedAt != nil }) {
            [.unbury]
        } else {
            []
        }
    }

    /// Lists what Lucas chose in the sidebar.
    public mutating func choose(_ item: SidebarItem) {
        guard item != sidebarItem else { return }
        sidebarItem = item
        read(on: ladder)
    }

    /// Narrows what the table lists to what mentions `search`. A blank search
    /// narrows nothing.
    public mutating func search(for search: String) {
        guard search != self.search else { return }
        self.search = search
        read(on: ladder)
    }

    /// Selects the cards in `selection`, in a group of cards.
    public mutating func select(_ selection: Set<CardRow.ID>) {
        guard selection != self.selection else { return }
        self.selection = selection
        readReviewLog()
    }

    /// Selects the row with `id` in the inbox, or none.
    public mutating func selectInInbox(_ id: InboxRow.ID?) {
        guard id != inboxSelection else { return }
        inboxSelection = id
        readReviewLog()
    }

    /// Reads the tags and what the sidebar chose, as they are now, on
    /// `ladder`, the one Lucas set in Settings, which he may have changed
    /// since the last read, and the review log of the card the detail shows.
    /// When the chosen tag is gone, because its last card was buried, edited
    /// or deleted, the sidebar goes back to All cards.
    public mutating func read(on ladder: Ladder) {
        self.ladder = ladder
        now = engine.now
        do throws(EngineError) {
            tags = try engine.tags()
            if case .cards(.tag(let tag)) = sidebarItem, !tags.contains(tag) {
                sidebarItem = .cards(.all)
            }
            switch sidebarItem {
            case .cards(let group):
                listing = .success(.cards(try engine.cardRows(in: group, matching: search, on: ladder)))
            case .inbox:
                listing = .success(.inbox(try engine.inboxRows(matching: search, on: ladder)))
            }
        } catch {
            listing = .failure(error)
        }
        readReviewLog()
    }

    /// Reads the review log of the card the detail shows, while it shows one.
    private mutating func readReviewLog() {
        guard let row = shownCard else {
            reviewLog = nil
            return
        }
        reviewLog = CardReviewLog(
            cardID: row.id, rows: Result { () throws(EngineError) in try engine.reviewLogRows(of: row.id, on: ladder) })
    }
}

/// A card's review log, as the Cards window's detail shows it under the
/// card, or why it couldn't be read.
private struct CardReviewLog: Sendable {
    let cardID: Int64
    let rows: Result<[ReviewLogRow], EngineError>
}

extension Engine {
    /// Opens the Cards window on All cards, with nothing searched or
    /// selected, for Lucas's cards standing on `ladder`, the one he set in
    /// Settings, which it reads once the window asks.
    public func openCardsWindow(on ladder: Ladder) -> CardsWindowState {
        CardsWindowState(engine: self, ladder: ladder)
    }
}
