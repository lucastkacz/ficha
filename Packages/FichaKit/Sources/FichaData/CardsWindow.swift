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
        guard card.isInReviews else {
            return nil
        }
        return standing.due
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

extension Engine {
    /// The cards in `group` that mention `search` in their front, back or
    /// source, as the Cards window lists them, in the order Lucas approved
    /// them, each standing on `ladder`. A blank search narrows nothing.
    public func cardRows(in group: CardGroup, matching search: String = "", on ladder: Ladder) throws(EngineError)
        -> [CardRow]
    {
        let now = time.now
        return try read { db in
            let entries = Dictionary(grouping: try logEntries(in: db), by: \.cardID)
            return try allCards(in: db).filter { $0.matches(search) }.map { card in
                try CardRow(card: card, after: entries[card.id] ?? [], on: ladder)
            }
            .filter { group.holds($0, at: now, on: ladder) }
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

extension Card {
    /// Whether the card's front, back or source mentions `search`.
    fileprivate func matches(_ search: String) -> Bool {
        [front, back, source].compactMap(\.self).contains { mentions($0, search) }
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
        case .flagged: row.card.flag != nil && row.card.buriedAt == nil
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
