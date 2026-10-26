import FichaCore
import Foundation
internal import GRDB

/// A card as the Cards window lists it: the card, where it stands, in Lucas's
/// reviews and on his ladder, and when he last saw it.
public struct CardRow: Sendable, Equatable, Identifiable {
    public let card: Card
    /// The card's tags, in its order, each with what it has of its own, as
    /// the Tags column shows them.
    public let tags: [CardTag]
    /// Where the card stands: in Lucas's reviews, waiting in the inbox to be
    /// fixed, buried, or set aside.
    public let cardStanding: CardStanding
    /// Where it stands on the ladder: new, or on a step until it's due,
    /// worked out from its review log. A flagged, buried or set-aside card
    /// keeps it, and `cardStanding` says whether the card is in Lucas's
    /// reviews.
    public let standing: LadderStanding
    /// How long its step waits, or nil while it's new.
    public let wait: Duration?
    /// When the user last saw it: its review log's latest first view or review,
    /// or nil while it's new, or while it has only the placement an import
    /// put it on its step with (ADR 0013).
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
    /// or out of Lucas's reviews, flagged, buried or set aside, since it
    /// won't show up then.
    public var due: Date? {
        cardStanding.due(given: standing)
    }

    /// What the Due column says of the card.
    public enum DueColumn: Sendable, Equatable {
        /// When it's due: it's in Lucas's reviews, on the ladder.
        case due(Date)
        /// That it's set aside, so it won't show up until none of its tags
        /// is.
        case setAside
        /// Nothing: it's new, flagged or buried, which the Step column and
        /// the Front column's marks say.
        case nothing
    }

    /// What the Due column says of the card: when it's due, or that it's set
    /// aside, or nothing.
    public var dueColumn: DueColumn {
        if case .setAside = cardStanding {
            .setAside
        } else if let due {
            .due(due)
        } else {
            .nothing
        }
    }

    /// Whether the card is due at `time`: in Lucas's reviews, with its wait
    /// over.
    public func isDue(at time: Date) -> Bool {
        cardStanding.isDue(at: time, given: standing)
    }

    /// Whether the card is new in Lucas's reviews: it hasn't had its first
    /// view yet.
    var isNew: Bool {
        cardStanding.isNew(given: standing)
    }

    /// Whether the card is learned in Lucas's reviews, standing on `ladder`:
    /// on a step that waits 30 days or more.
    func isLearned(on ladder: Ladder) -> Bool {
        cardStanding.isLearned(given: standing, on: ladder)
    }
}

/// An entry of a card's review log as the Cards window shows it under the
/// card, in its chart and its list: the first view, review or placement, and
/// the step the entry's way stood on after it.
public struct ReviewLogRow: Sendable, Equatable {
    /// The first view, review or placement, as the review log keeps it.
    public let entry: ReviewLogEntry
    /// The step the entry's way stood on after it, counted from 0, the first
    /// step.
    public let step: Int
}

/// A group of cards the Cards window's sidebar offers, which the window lists
/// one at a time.
public enum CardGroup: Sendable, Hashable {
    /// Every card that isn't buried, flagged and set-aside ones too.
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
    /// The cards with this tag that aren't buried, set-aside ones too.
    case tag(String)
    /// The cards of this type that aren't buried.
    case type(CardType)
    /// The cards with no type that aren't buried, which the sidebar offers
    /// only while there are some.
    case noType
}

/// Something that waits in the inbox, as the Cards window lists it, with when
/// it came there.
public struct InboxRow: Sendable, Equatable, Identifiable {
    /// What waits in the inbox.
    public enum Item: Sendable, Equatable {
        /// A capture that expands no card and follows none up.
        case capture(Capture)
        /// A capture attached to the card it repeats, with the card.
        case expansion(Expansion)
        /// A capture Lucas asked about a card in the review panel, tied to
        /// it, with the card.
        case followUp(FollowUp)
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
        case .followUp(let followUp): .capture(followUp.capture.id)
        case .flaggedCard(let row): .card(row.id)
        }
    }

    /// What the row says it is: a capture's text, or a flagged card's front.
    public var text: String {
        switch item {
        case .capture(let capture): capture.text
        case .expansion(let expansion): expansion.capture.text
        case .followUp(let followUp): followUp.capture.text
        case .flaggedCard(let row): row.card.front
        }
    }

    /// The capture it is, or the expansion's or the follow-up's, or nil for
    /// a flagged card.
    public var capture: Capture? {
        switch item {
        case .capture(let capture): capture
        case .expansion(let expansion): expansion.capture
        case .followUp(let followUp): followUp.capture
        case .flaggedCard: nil
        }
    }

    /// The flagged card it is, with where it stands, or nil for a capture, an
    /// expansion or a follow-up.
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
    /// lists it, the latest added first: the captures, the expansions and the
    /// follow-ups that mention it in their text or source, and the flagged
    /// cards that mention it in their front, back or source, as Flagged lists
    /// them, each standing on `ladder`. A blank search narrows nothing.
    public func inboxRows(matching search: String = "", on ladder: Ladder) throws(EngineError) -> [InboxRow] {
        let now = time.now
        return try read { db in
            let captures = try capturesWaiting(in: db).filter { $0.matches(search) }.map { capture in
                InboxRow(
                    item: try capture.expansion(in: db).map(InboxRow.Item.expansion)
                        ?? capture.followUp(in: db).map(InboxRow.Item.followUp) ?? .capture(capture),
                    addedAt: capture.createdAt)
            }
            let flaggedCards = try FichaData.cardRows(in: .flagged, matching: search, on: ladder, at: now, in: db)
                .map { row in
                    // Flagged lists only cards waiting in the inbox.
                    guard case .inInbox(let flag) = row.cardStanding else {
                        throw EngineError.cardNotFlagged(row.id)
                    }
                    return InboxRow(item: .flaggedCard(row), addedAt: flag.flaggedAt)
                }
            return (captures + flaggedCards).sorted { $0.addedAt > $1.addedAt }
        }
    }

    /// The type groups the Cards window's sidebar lists: one for each card
    /// type, in `CardType`'s order, and No Type after them while a card that
    /// isn't buried has no type.
    func sidebarTypeGroups() throws(EngineError) -> [CardGroup] {
        try read { db in
            let someCardHasNoType = try allCards(in: db).contains { card in
                card.type == nil && card.standing.isInAllCards
            }
            return CardType.allCases.map(CardGroup.type) + (someCardHasNoType ? [.noType] : [])
        }
    }

    /// A card's review log as the Cards window shows it under the card,
    /// oldest first: each first view, review and placement, either way, with
    /// the step of `ladder` the entry's way stood on after it. Empty while
    /// the card is new.
    public func reviewLogRows(of cardID: Int64, on ladder: Ladder) throws(EngineError) -> [ReviewLogRow] {
        try read { db in
            let entries = try logEntries(ofExisting: cardID, in: db)
            // Each step is where the ladder puts the entry's way after that
            // way's log up to the entry, as it works out the way's standing
            // from its whole log, so the front-first way's last one is the
            // Step column's. That goes over the log again for each entry, but
            // a card has few.
            return try entries.indices.map { end in
                let wayUpToEntry = entries[...end].filter { $0.way == entries[end].way }
                guard case .onLadder(let step, _) = try ladder.standing(after: wayUpToEntry) else {
                    // The ladder puts a card with an entry on a step, or
                    // throws.
                    logger.error("Card \(cardID)'s review log left it new after an entry")
                    throw EngineError.unreadableReviewLog(cardID)
                }
                return ReviewLogRow(entry: entries[end], step: step)
            }
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
    let ownTags = try OwnTags(in: db)
    return try allCards(in: db).filter { $0.matches(search) }.map { card in
        try CardRow(card: card, tags: ownTags, after: entries[card.id] ?? [], on: ladder)
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
        case .all: row.cardStanding.isInAllCards
        case .new: row.isNew
        case .due: row.isDue(at: now)
        case .learned: row.isLearned(on: ladder)
        case .flagged:
            switch row.cardStanding {
            case .inInbox: true
            case .inReviews, .buried, .setAside: false
            }
        case .buried:
            switch row.cardStanding {
            case .buried: true
            case .inReviews, .inInbox, .setAside: false
            }
        case .tag(let tag): row.card.tags.contains(tag) && row.cardStanding.isInAllCards
        case .type(let type): row.card.type == type && row.cardStanding.isInAllCards
        case .noType: row.card.type == nil && row.cardStanding.isInAllCards
        }
    }
}

extension CardStanding {
    /// Whether All cards holds a card standing here, as each tag and type do
    /// for theirs: unless it's buried, since only Buried holds those. Like
    /// flagged cards, set-aside cards are there.
    var isInAllCards: Bool {
        switch self {
        case .inReviews, .inInbox, .setAside: true
        case .buried: false
        }
    }
}

extension CardRow {
    /// The row of `card`, whose tags have what `ownTags` says of their own,
    /// after `entries`, its review log's, in the order they happened: last
    /// seen either way, and standing on `ladder` as its front-first way
    /// does.
    fileprivate init(
        card: Card, tags ownTags: OwnTags, after entries: [ReviewLogEntry], on ladder: Ladder
    ) throws(UnexpectedReviewLog) {
        self.card = card
        tags = card.tags.map(ownTags.tag)
        cardStanding = card.standing
        standing = try ladder.standing(after: entries.filter { $0.way == .frontFirst })
        lastSeen =
            entries.last { entry in
                if case .placement = entry.kind { false } else { true }
            }?
            .answeredAt
        if case .onLadder(let step, _) = standing {
            wait = ladder.waits[step]
        } else {
            wait = nil
        }
    }
}
