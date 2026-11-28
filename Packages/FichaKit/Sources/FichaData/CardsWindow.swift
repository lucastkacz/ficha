import FichaCore
import Foundation
internal import GRDB

/// A card as the Cards window lists it: the card, where it stands, in Lucas's
/// reviews and in the scheduler each way, and when he last saw it.
public struct CardRow: Sendable, Equatable, Identifiable {
    public let card: Card
    /// Where the card stands: in Lucas's reviews, flagged and waiting in its
    /// deck to be fixed, or set aside, on its own, which the engine keeps as
    /// its burial, or with its deck.
    public let cardStanding: CardStanding
    /// Where its front-first way stands, which every card has, as the
    /// detail says in words whether the card is new and when it's back
    /// (`CardWording.swift`), its Interval and Due rows under Details show
    /// it, and its tile's mark in the grid (`CardsWindowGrid.swift`).
    public let frontFirst: WayProgress
    /// Where its back-first way stands, as the detail's words count it when
    /// they say when the card is back, and its Back-first interval and
    /// Back-first due rows under Details show it, or nil while the card goes
    /// one way, also once Lucas switched Both ways off, which keeps that
    /// way's progress.
    public let backFirst: WayProgress?
    /// When the user last saw it, either way: its review log's latest
    /// review, or nil while it's new, or while it has only the placement an
    /// import gave it (ADR 0013).
    public let lastSeen: Date?
    /// How many times the user reviewed it, either way, as the detail says
    /// it, "Seen 3 times", and its Reviews row under Details shows it: its
    /// review log's reviews, an import's from another app too, the rated
    /// points of the card's chart. A placement isn't one, even when an import
    /// made it from Anki's first review of a card whose learning steps Anki
    /// lost. A way the card no longer goes keeps its reviews here, as the
    /// chart still draws them.
    public let reviews: Int

    public var id: Int64 {
        card.id
    }

    /// Whether the card is due at `time`: in Lucas's reviews, with either
    /// way's wait over.
    func isDue(at time: Date) -> Bool {
        frontFirst.isDue(at: time) || backFirst?.isDue(at: time) == true
    }
}

/// Where one of a card's ways stands, as the Cards window shows it: in the
/// scheduler after that way's review log, as if it were a card of its own
/// (ADR 0016), and in Lucas's reviews or out of them with the card, both ways
/// together.
public struct WayProgress: Sendable, Equatable {
    /// Where the way stands in the scheduler: new, or at a stage, waiting
    /// its interval until it's due, worked out from its entries in the review
    /// log. A flagged or set-aside card keeps it, and `cardStanding`
    /// says whether the card is in Lucas's reviews.
    public let standing: WayStanding
    /// What FSRS knows of how well Lucas remembers the way, as the window
    /// read it, or nil while it's new, or while an import placed it in its
    /// learning steps without reviews.
    public let memory: WayMemory?
    /// How many times the user reviewed the card this way, as the Reviews
    /// row under the detail's Details splits the card's reviews.
    public let reviews: Int
    /// Where the card stands, both ways together.
    let cardStanding: CardStanding

    /// How long the way waits after its last entry, or nil while it's new.
    public var interval: Duration? {
        standing.interval
    }

    /// What the detail's Interval rows say of the way, as Anki's Browse says
    /// it: that it's new, that it's in its learning steps, or its interval.
    public enum IntervalWording: Sendable, Equatable {
        /// That it's new.
        case new
        /// That it's in its learning steps, whatever the step's interval,
        /// as Anki's Browse says "(learning)" there: an import's placement
        /// of a card Anki was learning too, whose interval is none when the
        /// settings have no learning steps.
        case learning(Duration)
        /// Its interval: graduated, in days, or in its relearning steps,
        /// the step's.
        case interval(Duration)
    }

    /// What the detail's Interval rows say of the way.
    public var intervalWording: IntervalWording {
        switch standing {
        case .new: .new
        case .started(.learning, let interval, _, _): .learning(interval)
        case .started(.graduated, let interval, _, _), .started(.relearning, let interval, _, _):
            .interval(interval)
        }
    }

    /// When the way is due, as the Cards window says it: nil while it's new,
    /// or while the card is out of Lucas's reviews, flagged or set aside,
    /// since it won't show up then.
    public var due: Date? {
        cardStanding.due(given: standing)
    }

    /// What the detail's Due rows say of the way.
    public enum DueWording: Sendable, Equatable {
        /// When it's due: the card is in Lucas's reviews, and the way isn't
        /// new.
        case due(Date)
        /// That the card is set aside, on its own or with its deck, so it
        /// won't show up until it's put back, or until neither its deck nor
        /// any deck that deck sits inside is.
        case setAside
        /// Nothing: the way is new, or the card flagged, which the detail's
        /// Interval row and the note above the card say.
        case nothing
    }

    /// What the way's Due rows say of it: when it's due, or that the card is
    /// set aside, or nothing.
    public var dueWording: DueWording {
        switch cardStanding {
        case .setAside, .buried: .setAside
        case .inReviews, .flagged: due.map(DueWording.due) ?? .nothing
        }
    }

    /// Whether the way is due at `time`: the card is in Lucas's reviews, and
    /// the way's wait is over.
    public func isDue(at time: Date) -> Bool {
        cardStanding.isDue(at: time, given: standing)
    }
}

/// What FSRS knows of how well Lucas remembers one of a card's ways, as a
/// card's detail shows it under Details, as Anki's Card Info does: why the
/// way shows up when it does: FSRS's memory state, its stability and
/// difficulty, as fsrs-rs's `MemoryState` and `WayStanding.Memory` name
/// them, and the retrievability they give.
public struct WayMemory: Sendable, Equatable {
    /// How long the way's memory lasts: the days it takes the chance of
    /// remembering it to fall to 90%, FSRS's stability.
    public let stabilityInDays: Double
    /// How hard the way is, from 0 to 1, as Anki shows FSRS's difficulty
    /// as a percentage (`WayStanding.Memory.difficultyAsAnkiShowsIt`).
    public let difficulty: Double
    /// The chance of remembering the way when the window read it, from 0 to
    /// 1, FSRS's retrievability.
    public let retrievability: Double
}

/// An entry of a card's review log as the Cards window shows it under the
/// card's Details, in its chart and its list: the review or placement, and
/// the interval the entry's way waited after it.
public struct ReviewLogRow: Sendable, Equatable {
    /// The review or placement, as the review log keeps it.
    public let entry: ReviewLogEntry
    /// The interval the entry's way waited after it, as the scheduler works
    /// it out from the way's entries up to this one.
    public let interval: Duration
}

/// A group of cards the engine lists: a deck the Cards window's sidebar offers,
/// which the window lists one at a time, or every card, which the sidebar
/// doesn't offer. No group of a tag or a type: the database keeps the cards'
/// tags and types, which the window doesn't show (#538).
public enum CardGroup: Sendable, Hashable {
    /// Every card that isn't set aside on its own, which the engine keeps as
    /// its burial, flagged ones and those set aside with their decks too,
    /// which the engine counts each tag's cards from (`Engine.countedTags`).
    case all
    /// Every card that lives in the deck with this whole name, or in a deck
    /// inside it, flagged ones and set-aside ones too, on their own or with
    /// their decks, as the deck's grid lists them and the engine counts them
    /// (`Engine.countedDecks`) (#539): Default's, by `Deck.defaultName`, are
    /// those that live in Default alone.
    case deck(String)
}

extension Engine {
    /// The cards in `group` that mention `search` in their front, back or
    /// source, as the Cards window lists them, in the order they came in, each
    /// standing as `scheduler` replays its log. A blank search narrows nothing.
    public func cardRows(in group: CardGroup, matching search: String = "", with scheduler: Scheduler)
        throws(EngineError) -> [CardRow]
    {
        let now = time.now
        return try read { db in
            try FichaData.cardRows(in: group, matching: search, with: scheduler, at: now, in: db)
        }
    }

    /// A card's review log as the Cards window shows it under the card's
    /// Details, oldest first, also when it joins two devices' entries, which
    /// come in any order: each review and placement, either way, in the
    /// order the scheduler replays them, with the interval `scheduler` gives
    /// the entry's way after it. Empty while the card is new.
    public func reviewLogRows(of cardID: Int64, with scheduler: Scheduler) throws(EngineError) -> [ReviewLogRow] {
        try read { db in
            let entries = try logEntries(ofExisting: cardID, in: db).sorted { $0.precedes($1) }
            // Each interval is the one the scheduler gives the entry's way
            // after that way's entries up to this one, as it works out the
            // way's standing from its whole log, so the way's last one is the
            // detail's Interval row's. That goes over the log again for each
            // entry, but a card has few.
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
/// in the order they came in, each standing as `scheduler` replays its log at
/// `now`.
func cardRows(
    in group: CardGroup,
    matching search: String,
    with scheduler: Scheduler,
    at now: Date,
    in db: Database
) throws -> [CardRow] {
    try everyCardRow(matching: search, with: scheduler, at: now, in: db).filter { group.holds($0) }
}

/// Every card that mentions `search` in its front, back or source, wherever it
/// stands, in the order they came in, each standing as `scheduler` replays its
/// log at `now`. A blank search narrows nothing.
func everyCardRow(
    matching search: String = "",
    with scheduler: Scheduler,
    at now: Date,
    in db: Database
) throws -> [CardRow] {
    let entries = Dictionary(grouping: try logEntries(in: db), by: \.cardID)
    return try allCards(in: db).filter { $0.matches(search) }.map { card in
        try CardRow(card: card, after: entries[card.id] ?? [], with: scheduler, at: now)
    }
}

extension Card {
    /// Whether the card's front, back or source mentions `search`.
    fileprivate func matches(_ search: String) -> Bool {
        [front, back, source].compactMap(\.self).contains { mentions($0, search) }
    }
}

extension CardGroup {
    /// Whether the group holds the card in `row`.
    fileprivate func holds(_ row: CardRow) -> Bool {
        switch self {
        case .all: row.cardStanding.isInAllCards
        case .deck(let deck): TagPath.isTag(row.card.deck, within: deck)
        }
    }
}

extension CardStanding {
    /// Whether the group of every card, which each tag's counts come from,
    /// holds a card standing here: unless it's set aside on its own, which
    /// the engine keeps as its burial. Like flagged cards, cards set aside
    /// with their decks are there. A deck holds every card in it (#539).
    var isInAllCards: Bool {
        switch self {
        case .inReviews, .flagged, .setAside: true
        case .buried: false
        }
    }
}

extension CardRow {
    /// The row of `card` after `entries`, its review log's, in any order:
    /// last seen either way, when Lucas last answered it, how many times he
    /// did, and each way standing as `scheduler` replays its log, with its
    /// memory at `now`, its back-first way only while the card goes both
    /// ways.
    fileprivate init(
        card: Card, after entries: [ReviewLogEntry], with scheduler: Scheduler, at now: Date
    ) throws(SchedulingError) {
        self.card = card
        cardStanding = card.standing
        frontFirst = try WayProgress(.frontFirst, of: card, after: entries, with: scheduler, at: now)
        backFirst =
            card.bothWays ? try WayProgress(.backFirst, of: card, after: entries, with: scheduler, at: now) : nil
        let rated = entries.filter { !$0.isPlacement }
        lastSeen = rated.map(\.answeredAt).max()
        reviews = rated.count
    }
}

extension WayProgress {
    /// Where `card`'s `way` stands as `scheduler` replays its entries out of
    /// `entries`, the card's review log's, in any order, with its memory at
    /// `now` and how many of its entries are reviews.
    fileprivate init(
        _ way: Way, of card: Card, after entries: [ReviewLogEntry], with scheduler: Scheduler, at now: Date
    ) throws(SchedulingError) {
        let wayEntries = entries.filter { $0.way == way }
        let standing = try scheduler.standing(after: wayEntries)
        self.standing = standing
        reviews = wayEntries.count { !$0.isPlacement }
        cardStanding = card.standing
        // The scheduler reads a retrievability whenever the way has a memory.
        memory = try scheduler.retrievability(of: standing, at: now).flatMap { retrievability in
            standing.memory.map { memory in
                WayMemory(
                    stabilityInDays: Double(memory.stability), difficulty: Double(memory.difficultyAsAnkiShowsIt),
                    retrievability: Double(retrievability))
            }
        }
    }
}
