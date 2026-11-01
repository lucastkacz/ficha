import FichaCore
import Foundation
internal import GRDB

/// A card as the Cards window lists it: the card, where it stands, in Lucas's
/// reviews and in the scheduler each way, and when he last saw it.
public struct CardRow: Sendable, Equatable, Identifiable {
    public let card: Card
    /// The card's tags, in its order, each with what it has of its own, as
    /// the Tags column shows them.
    public let tags: [CardTag]
    /// Where the card stands: in Lucas's reviews, waiting in the inbox to be
    /// fixed, buried, or set aside.
    public let cardStanding: CardStanding
    /// Where its front-first way stands, which every card has, as the
    /// Interval and Due columns show it.
    public let frontFirst: WayProgress
    /// Where its back-first way stands, as the Back-first interval and
    /// Back-first due columns show it, or nil while the card goes one way,
    /// also once Lucas switched Both ways off, which keeps that way's
    /// progress.
    public let backFirst: WayProgress?
    /// When the user last saw it, either way: its review log's latest
    /// review, or nil while it's new, or while it has only the placement an
    /// import gave it (ADR 0013).
    public let lastSeen: Date?

    public var id: Int64 {
        card.id
    }

    /// Whether the card is due at `time`: in Lucas's reviews, with either
    /// way's wait over.
    func isDue(at time: Date) -> Bool {
        frontFirst.isDue(at: time) || backFirst?.isDue(at: time) == true
    }

    /// Whether the card is new in Lucas's reviews: its front-first way
    /// hasn't had its first review yet, whatever its back-first way did.
    var isNew: Bool {
        frontFirst.isNew
    }

    /// Whether the card is learned in Lucas's reviews: its front-first way
    /// graduated with an interval of 21 days or more, as the menu counts it,
    /// so that switching Both ways on changes nothing there.
    var isLearned: Bool {
        frontFirst.isLearned
    }
}

/// Where one of a card's ways stands, as the Cards window shows it: in the
/// scheduler after that way's review log, as if it were a card of its own
/// (ADR 0016), and in Lucas's reviews or out of them with the card, both ways
/// together.
public struct WayProgress: Sendable, Equatable {
    /// Where the way stands in the scheduler: new, or at a stage, waiting
    /// its interval until it's due, worked out from its entries in the review
    /// log. A flagged, buried or set-aside card keeps it, and `cardStanding`
    /// says whether the card is in Lucas's reviews.
    public let standing: WayStanding
    /// Where the card stands, both ways together.
    let cardStanding: CardStanding

    /// How long the way waits after its last entry, or nil while it's new.
    public var interval: Duration? {
        standing.interval
    }

    /// When the way is due, as the Cards window says it: nil while it's new,
    /// or while the card is out of Lucas's reviews, flagged, buried or set
    /// aside, since it won't show up then.
    public var due: Date? {
        cardStanding.due(given: standing)
    }

    /// What the Due column, or the Back-first due column, says of the way.
    public enum DueColumn: Sendable, Equatable {
        /// When it's due: the card is in Lucas's reviews, and the way isn't
        /// new.
        case due(Date)
        /// That the card is set aside, so it won't show up until neither its
        /// deck nor any deck that deck sits inside is.
        case setAside
        /// Nothing: the way is new, or the card flagged or buried, which the
        /// interval's column and the Front column's marks say.
        case nothing
    }

    /// What the way's due column says of it: when it's due, or that the card
    /// is set aside, or nothing.
    public var dueColumn: DueColumn {
        if case .setAside = cardStanding {
            .setAside
        } else if let due {
            .due(due)
        } else {
            .nothing
        }
    }

    /// Whether the way is due at `time`: the card is in Lucas's reviews, and
    /// the way's wait is over.
    public func isDue(at time: Date) -> Bool {
        cardStanding.isDue(at: time, given: standing)
    }

    /// Whether the way is new in Lucas's reviews: it hasn't had its first
    /// review yet.
    var isNew: Bool {
        cardStanding.isNew(given: standing)
    }

    /// Whether the way is learned in Lucas's reviews: graduated, with an
    /// interval of 21 days or more.
    var isLearned: Bool {
        cardStanding.isLearned(given: standing)
    }
}

/// An entry of a card's review log as the Cards window shows it under the
/// card, in its chart and its list: the review or placement, and the
/// interval the entry's way waited after it.
public struct ReviewLogRow: Sendable, Equatable {
    /// The review or placement, as the review log keeps it.
    public let entry: ReviewLogEntry
    /// The interval the entry's way waited after it, as the scheduler works
    /// it out from the way's entries up to this one.
    public let interval: Duration
}

/// A group of cards the Cards window's sidebar offers, which the window lists
/// one at a time.
public enum CardGroup: Sendable, Hashable {
    /// Every card that isn't buried, flagged and set-aside ones too.
    case all
    /// The cards in Lucas's reviews that haven't had their first review yet,
    /// front first.
    case new
    /// The cards in Lucas's reviews with either of their ways due now: each
    /// card once, where the menu counts each way that's due.
    case due
    /// The cards in Lucas's reviews that he learned, as the menu counts them.
    case learned
    /// The flagged cards that wait in the inbox to be fixed: those that
    /// aren't buried.
    case flagged
    /// Every buried card, flagged or not.
    case buried
    /// The cards that live in the deck with this whole name, or in a deck
    /// inside it, and aren't buried, set-aside ones too: Default's, by
    /// `Deck.defaultName`, are those that live in Default alone.
    case deck(String)
    /// The cards with this tag, or a tag inside it, that aren't buried,
    /// set-aside ones too.
    case tag(String)
    /// The cards of this type that aren't buried: a user type's by its ID,
    /// whatever its name now.
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
    /// them, each standing as `scheduler` replays its log. A blank search
    /// narrows nothing.
    public func cardRows(in group: CardGroup, matching search: String = "", with scheduler: Scheduler)
        throws(EngineError) -> [CardRow]
    {
        let now = time.now
        return try read { db in
            try FichaData.cardRows(in: group, matching: search, with: scheduler, at: now, in: db)
        }
    }

    /// What waits in the inbox that mentions `search`, as the Cards window
    /// lists it, the latest added first: the captures, the expansions and the
    /// follow-ups that mention it in their text or source, and the flagged
    /// cards that mention it in their front, back or source, as Flagged lists
    /// them, each standing as `scheduler` replays its log. A blank search
    /// narrows nothing.
    public func inboxRows(matching search: String = "", with scheduler: Scheduler) throws(EngineError)
        -> [InboxRow]
    {
        let now = time.now
        return try read { db in
            let captures = try capturesWaiting(in: db).filter { $0.matches(search) }.map { capture in
                InboxRow(
                    item: try capture.expansion(in: db).map(InboxRow.Item.expansion)
                        ?? capture.followUp(in: db).map(InboxRow.Item.followUp) ?? .capture(capture),
                    addedAt: capture.createdAt)
            }
            let flaggedCards = try FichaData.cardRows(
                in: .flagged, matching: search, with: scheduler, at: now, in: db
            )
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

    /// The type groups the Cards window's sidebar lists: one for each of the
    /// four types Ficha comes with, in their order, then one for each of the
    /// user's types, in alphabetical order, also while no card has it, and No
    /// Type after them while a card that isn't buried has no type.
    func sidebarTypeGroups() throws(EngineError) -> [CardGroup] {
        try read { db in
            let someCardHasNoType = try allCards(in: db).contains { card in
                card.type == nil && card.standing.isInAllCards
            }
            let userTypes = try UserTypes(in: db).sorted.map(CardType.user)
            return (CardType.builtIn + userTypes).map(CardGroup.type) + (someCardHasNoType ? [.noType] : [])
        }
    }

    /// A card's review log as the Cards window shows it under the card,
    /// oldest first, also when it joins two devices' entries, which come in
    /// any order: each review and placement, either way, in the order the
    /// scheduler replays them, with the interval `scheduler` gives the
    /// entry's way after it. Empty while the card is new.
    public func reviewLogRows(of cardID: Int64, with scheduler: Scheduler) throws(EngineError) -> [ReviewLogRow] {
        try read { db in
            let entries = try logEntries(ofExisting: cardID, in: db).sorted { $0.precedes($1) }
            // Each interval is the one the scheduler gives the entry's way
            // after that way's entries up to this one, as it works out the
            // way's standing from its whole log, so the way's last one is the
            // Interval column's. That goes over the log again for each entry,
            // but a card has few.
            return try entries.indices.map { end in
                let wayUpToEntry = entries[...end].filter { $0.way == entries[end].way }
                guard let interval = try scheduler.standing(after: Array(wayUpToEntry)).interval else {
                    // The scheduler starts a way with an entry, or throws.
                    logger.error("Card \(cardID)'s review log left it new after an entry")
                    throw EngineError.unreadableReviewLog(cardID)
                }
                return ReviewLogRow(entry: entries[end], interval: interval)
            }
        }
    }
}

/// The cards in `group` that mention `search` in their front, back or source,
/// in the order Lucas approved them, each standing as `scheduler` replays its
/// log at `now`.
func cardRows(
    in group: CardGroup,
    matching search: String,
    with scheduler: Scheduler,
    at now: Date,
    in db: Database
) throws -> [CardRow] {
    let entries = Dictionary(grouping: try logEntries(in: db), by: \.cardID)
    let ownTags = try OwnTags(in: db)
    return try allCards(in: db).filter { $0.matches(search) }.map { card in
        try CardRow(card: card, tags: ownTags, after: entries[card.id] ?? [], with: scheduler)
    }
    .filter { group.holds($0, at: now) }
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
    /// Whether the group holds the card in `row`, at `now`.
    fileprivate func holds(_ row: CardRow, at now: Date) -> Bool {
        switch self {
        case .all: row.cardStanding.isInAllCards
        case .new: row.isNew
        case .due: row.isDue(at: now)
        case .learned: row.isLearned
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
        case .deck(let deck): TagPath.isTag(row.card.deck, within: deck) && row.cardStanding.isInAllCards
        case .tag(let tag): row.card.hasTag(within: tag) && row.cardStanding.isInAllCards
        case .type(let type): row.card.type?.isSameType(as: type) == true && row.cardStanding.isInAllCards
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
    /// after `entries`, its review log's, in any order: last seen either way,
    /// when Lucas last answered it, and each way standing as `scheduler`
    /// replays its log, its back-first way only while the card goes both
    /// ways.
    fileprivate init(
        card: Card, tags ownTags: OwnTags, after entries: [ReviewLogEntry], with scheduler: Scheduler
    ) throws(SchedulingError) {
        self.card = card
        tags = card.tags.map(ownTags.tag)
        cardStanding = card.standing
        frontFirst = try WayProgress(.frontFirst, of: card, after: entries, with: scheduler)
        backFirst = card.bothWays ? try WayProgress(.backFirst, of: card, after: entries, with: scheduler) : nil
        lastSeen =
            entries.filter { entry in
                if case .placement = entry.kind { false } else { true }
            }
            .map(\.answeredAt).max()
    }
}

extension WayProgress {
    /// Where `card`'s `way` stands as `scheduler` replays its entries out of
    /// `entries`, the card's review log's, in any order.
    fileprivate init(
        _ way: Way, of card: Card, after entries: [ReviewLogEntry], with scheduler: Scheduler
    ) throws(SchedulingError) {
        standing = try scheduler.standing(after: entries.filter { $0.way == way })
        cardStanding = card.standing
    }
}
