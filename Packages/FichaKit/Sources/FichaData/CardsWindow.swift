import FichaCore
import Foundation
internal import GRDB

/// A card as the Cards window lists it: the card, where it stands on Lucas's
/// ladder, and when he last saw it.
public struct CardRow: Sendable, Equatable, Identifiable {
    public let card: Card
    /// Where it stands: new, or on a step until it's due, worked out from its
    /// review log.
    public let standing: CardStanding
    /// How long its step waits, or nil while it's new.
    public let wait: Duration?
    /// When Lucas last saw it: its review log's latest entry, its first view
    /// or a review, or nil while it's new.
    public let lastSeen: Date?

    public var id: Int64 {
        card.id
    }

    /// The step it stands on, counted from 0, the first step, or nil while
    /// it's new.
    public var step: Int? {
        guard case .onLadder(let step, _) = standing else {
            return nil
        }
        return step
    }

    /// When the card is due, as the Cards window says it: nil while it's new,
    /// or out of Lucas's reviews, flagged or buried, since it won't show up
    /// then.
    public var due: Date? {
        guard isInReviews else {
            return nil
        }
        return standing.due
    }

    /// Whether the card is in Lucas's reviews, neither flagged nor buried, so
    /// he can flag it, as in the review panel.
    public var isInReviews: Bool {
        card.isInReviews
    }
}

/// A group of cards the Cards window's sidebar offers, which the window lists
/// one at a time.
public enum CardGroup: Sendable, Hashable {
    /// Every card that isn't buried.
    case all
    /// The cards in Lucas's reviews that haven't had their first view yet.
    case new
    /// The cards in Lucas's reviews that are due now, as the menu counts
    /// them.
    case due
    /// The cards in Lucas's reviews that he learned, as the menu counts them.
    case learned
    /// The flagged cards that wait in the inbox to be fixed: those that
    /// aren't buried.
    case flagged
    /// Every buried card, flagged or not.
    case buried
    /// The cards with this tag that aren't buried.
    case tag(String)
    /// The cards of this type that aren't buried.
    case type(CardType)
}

/// Something that waits in the inbox, as the Cards window lists it, with when
/// it came there.
public struct InboxRow: Sendable, Equatable, Identifiable {
    /// What waits in the inbox.
    public enum Item: Sendable, Equatable {
        /// A capture that expands no card.
        case capture(Capture)
        /// A capture attached to the card it repeats, with the card.
        case expansion(Expansion)
        /// A flagged card that isn't buried, with where it stands.
        case flaggedCard(CardRow)
    }

    /// A row's id: its capture's, or its card's, which are numbered apart.
    public enum ID: Sendable, Hashable {
        case capture(Int64)
        case card(Int64)
    }

    public let item: Item
    /// When it came to the inbox: when Lucas captured it, or flagged the card.
    public let addedAt: Date

    public var id: ID {
        switch item {
        case .capture(let capture): .capture(capture.id)
        case .expansion(let expansion): .capture(expansion.capture.id)
        case .flaggedCard(let row): .card(row.id)
        }
    }

    /// What the row says it is: a capture's text, or a flagged card's front.
    public var text: String {
        switch item {
        case .capture(let capture): capture.text
        case .expansion(let expansion): expansion.capture.text
        case .flaggedCard(let row): row.card.front
        }
    }

    /// The capture it is, or the expansion's, or nil for a flagged card.
    public var capture: Capture? {
        switch item {
        case .capture(let capture): capture
        case .expansion(let expansion): expansion.capture
        case .flaggedCard: nil
        }
    }

    /// The flagged card it is, with where it stands, or nil for a capture or
    /// an expansion.
    public var flaggedCard: CardRow? {
        guard case .flaggedCard(let row) = item else {
            return nil
        }
        return row
    }
}

extension Engine {
    /// The cards in `group` that mention `search` in their front, back or
    /// source, as the Cards window lists them, in the order Lucas approved
    /// them, each standing on `ladder`. A blank search narrows nothing.
    public func cardRows(in group: CardGroup, matching search: String = "", on ladder: Ladder) throws(EngineError)
        -> [CardRow]
    {
        let now = time.now
        return try read { db in
            try FichaData.cardRows(in: group, matching: search, on: ladder, at: now, in: db)
        }
    }

    /// What waits in the inbox that mentions `search`, as the Cards window
    /// lists it, the latest added first: the captures and the expansions that
    /// mention it in their text or source, and the flagged cards that
    /// mention it in their front, back or source, as Flagged lists them, each
    /// standing on `ladder`. A blank search narrows nothing.
    public func inboxRows(matching search: String = "", on ladder: Ladder) throws(EngineError) -> [InboxRow] {
        let now = time.now
        return try read { db in
            let captures = try capturesWaiting(in: db).filter { $0.matches(search) }.map { capture in
                InboxRow(
                    item: try capture.expansion(in: db).map(InboxRow.Item.expansion) ?? .capture(capture),
                    addedAt: capture.createdAt)
            }
            let flaggedCards = try FichaData.cardRows(in: .flagged, matching: search, on: ladder, at: now, in: db)
                .map { row in
                    // Flagged lists flagged cards only.
                    guard let flag = row.card.flag else {
                        throw EngineError.cardNotFlagged(row.id)
                    }
                    return InboxRow(item: .flaggedCard(row), addedAt: flag.flaggedAt)
                }
            return (captures + flaggedCards).sorted { $0.addedAt > $1.addedAt }
        }
    }

    /// Every tag of the cards that aren't buried, once each, in alphabetical
    /// order, as the Cards window's sidebar lists them.
    public func tags() throws(EngineError) -> [String] {
        try read { db in
            Set(try allCards(in: db).filter { $0.buriedAt == nil }.flatMap(\.tags))
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
}

/// The cards in `group` that mention `search` in their front, back or source,
/// in the order Lucas approved them, each standing on `ladder` at `now`.
private func cardRows(
    in group: CardGroup,
    matching search: String,
    on ladder: Ladder,
    at now: Date,
    in db: Database
) throws -> [CardRow] {
    let entries = Dictionary(grouping: try logEntries(in: db), by: \.cardID)
    return try allCards(in: db).filter { $0.matches(search) }.map { card in
        try CardRow(card: card, after: entries[card.id] ?? [], on: ladder)
    }
    .filter { group.holds($0, at: now, on: ladder) }
}

extension Card {
    /// Whether the card's front, back or source mentions `search`.
    fileprivate func matches(_ search: String) -> Bool {
        [front, back, source].compactMap(\.self).contains { mentions($0, search) }
    }
}

extension Capture {
    /// Whether the capture's text or source mentions `search`.
    fileprivate func matches(_ search: String) -> Bool {
        [text, source].compactMap(\.self).contains { mentions($0, search) }
    }
}

extension CardGroup {
    /// Whether the group holds the card in `row`, at `now`, on `ladder`.
    fileprivate func holds(_ row: CardRow, at now: Date, on ladder: Ladder) -> Bool {
        switch self {
        case .all: row.card.buriedAt == nil
        case .new: row.card.isInReviews && row.standing == .new
        case .due: row.card.isInReviews && row.standing.isDue(at: now)
        case .learned: row.card.isInReviews && ladder.isLearned(row.standing)
        case .flagged: row.card.isInInbox
        case .buried: row.card.buriedAt != nil
        case .tag(let tag): row.card.tags.contains(tag) && row.card.buriedAt == nil
        case .type(let type): row.card.type == type && row.card.buriedAt == nil
        }
    }
}

extension CardRow {
    /// The row of `card`, standing on `ladder` after `entries`, its review
    /// log's, in the order they happened.
    fileprivate init(card: Card, after entries: [ReviewLogEntry], on ladder: Ladder) throws(UnexpectedReviewLog) {
        self.card = card
        standing = try ladder.standing(after: entries)
        lastSeen = entries.last?.answeredAt
        if case .onLadder(let step, _) = standing {
            wait = ladder.waits[step]
        } else {
            wait = nil
        }
    }
}
