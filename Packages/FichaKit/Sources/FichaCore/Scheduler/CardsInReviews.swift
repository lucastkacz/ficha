import Foundation

/// The cards in Lucas's reviews, the only ones that show up, as the planners
/// pick from them: out of every card, the ways of those whose standing is in
/// his reviews, by card in the order he approved them, with which cards are
/// priority cards, the queue of decks their new ways come from, and the whole
/// review log. The planners take nothing else, so which ways can show up, and
/// which come first, is decided here, from where each card stands and its
/// deck, and `make upload` lists its changes.
public struct CardsInReviews: Sendable, Equatable {
    /// The ways in Lucas's reviews, by card in the order he approved them:
    /// each card's front-first way, and then its back-first way, when it has
    /// one.
    let ways: [CardWay]
    /// The cards in Lucas's reviews that live in a priority deck, or in a deck
    /// inside one, by id, whose ways come first when cards show up (ADR 0011,
    /// ADR 0024).
    let priorityIDs: Set<Int64>
    /// The cards in Lucas's reviews that go both ways and whose back-first
    /// way is still to come, once their front-first way has an entry, by id.
    let backFirstWaysToCome: Set<Int64>
    /// The deck at the top of the tree that each card in Lucas's reviews
    /// lives in, or inside, by the card's id: its place in the queue is the
    /// card's (ADR 0034).
    let topDecks: [Int64: String]
    /// The decks at the top of the tree that hold cards in Lucas's reviews,
    /// in the queue's order, each with its place in it.
    let queue: [PlacedDeck]
    /// The whole review log, in the order it was written.
    let log: [ReviewLogEntry]

    /// The cards in Lucas's reviews out of `cards`, every card by id with
    /// where it stands, its deck, by its whole name, whether it goes both
    /// ways and when it came in, in the order he approved them, those that
    /// live in one of `priorityDecks`, or in a deck inside one, as `TagPath`
    /// reads a deck's levels, as priority cards, along with `log`, the whole
    /// review log, in the order it was written. A card's tags never make it
    /// one.
    /// Each card in his reviews brings its front-first way, and, when it goes
    /// both ways, its back-first way, once its front-first way has any entry,
    /// its first review or a placement (ADR 0016): the card's standing is
    /// both ways'.
    /// The queue new ways come from holds each deck at the top of the tree,
    /// with the decks inside it, at its place (ADR 0034): the one in
    /// `queuePlaces`, kept when the user moved it, or else when its first
    /// card came in, so that a deck that comes in goes last. Decks at the
    /// same place go in the order their first cards were approved, and then
    /// by name. The place of a deck inside another counts for nothing.
    public init(
        _ cards: [(id: Int64, standing: CardStanding, deck: String, bothWays: Bool, createdAt: Date)],
        priorityDecks: Set<String>,
        queuePlaces: [String: Date] = [:],
        log: [ReviewLogEntry]
    ) {
        let inReviews = cards.filter { $0.standing == .inReviews }
        let metFrontFirst = Set(log.filter { $0.way == .frontFirst }.map(\.cardID))
        ways = inReviews.flatMap { card in
            let frontFirst = CardWay(cardID: card.id, way: .frontFirst)
            guard card.bothWays, metFrontFirst.contains(card.id) else {
                return [frontFirst]
            }
            return [frontFirst, CardWay(cardID: card.id, way: .backFirst)]
        }
        priorityIDs = Set(
            inReviews.filter { !priorityDecks.isDisjoint(with: TagPath.lineage(of: $0.deck)) }.map(\.id))
        backFirstWaysToCome = Set(inReviews.filter { $0.bothWays && !metFrontFirst.contains($0.id) }.map(\.id))
        topDecks = Dictionary(uniqueKeysWithValues: inReviews.map { ($0.id, TagPath.top(of: $0.deck)) })
        // Each deck at the top's first card to come in, and the order of its
        // first card approved, out of every card, so that its place stays
        // as its cards are buried, flagged or set aside.
        var firstCameIn: [String: Date] = [:]
        var firstApproved: [String: Int] = [:]
        for (order, card) in cards.enumerated() {
            let top = TagPath.top(of: card.deck)
            firstCameIn[top] = min(firstCameIn[top] ?? card.createdAt, card.createdAt)
            firstApproved[top] = firstApproved[top] ?? order
        }
        queue = Set(topDecks.values)
            .map { deck in
                let place = queuePlaces[deck] ?? firstCameIn[deck] ?? .distantFuture
                return (deck: PlacedDeck(deck: deck, place: place), order: firstApproved[deck] ?? 0)
            }
            .sorted { ($0.deck.place, $0.order, $0.deck.deck) < ($1.deck.place, $1.order, $1.deck.deck) }
            .map(\.deck)
        self.log = log
    }

    /// The same cards as `cards`, with only the ways and priority cards
    /// given.
    private init(_ cards: CardsInReviews, ways: [CardWay], priorityIDs: Set<Int64>) {
        self.ways = ways
        self.priorityIDs = priorityIDs
        backFirstWaysToCome = cards.backFirstWaysToCome
        topDecks = cards.topDecks
        queue = cards.queue
        log = cards.log
    }

    /// The same cards as if no deck were a priority deck.
    var withoutPriority: CardsInReviews {
        CardsInReviews(self, ways: ways, priorityIDs: [])
    }

    /// The same cards as if none went both ways: their front-first ways
    /// alone.
    var frontFirstOnly: CardsInReviews {
        CardsInReviews(self, ways: ways.filter { $0.way == .frontFirst }, priorityIDs: priorityIDs)
    }

    /// Where each way stands with `scheduler`'s settings, by card in the
    /// order Lucas approved them, after the review log.
    func standings(with scheduler: Scheduler) throws(SchedulingError) -> [(way: CardWay, standing: WayStanding)] {
        try scheduler.standings(of: ways, after: log)
    }

    /// `ways` split into those of priority cards and the others, each group
    /// in the order it had.
    func splitByPriority(_ ways: [CardWay]) -> (priority: [CardWay], others: [CardWay]) {
        (ways.filter { priorityIDs.contains($0.cardID) }, ways.filter { !priorityIDs.contains($0.cardID) })
    }

    /// Those of `ways` whose cards live in the deck that goes first in the
    /// queue among theirs, in the order they had: the ways new cards come
    /// from, one deck at a time (ADR 0034).
    func fromTheFirstDeck(_ ways: [CardWay]) -> [CardWay] {
        let ranks = Dictionary(uniqueKeysWithValues: queue.enumerated().map { ($0.element.deck, $0.offset) })
        let rank = { (way: CardWay) in topDecks[way.cardID].flatMap { ranks[$0] } ?? Int.max }
        guard let first = ways.map(rank).min() else {
            return []
        }
        return ways.filter { rank($0) == first }
    }

    /// The new ways, those no entry of the log started yet, by card in the
    /// order Lucas approved them, each card's front-first way first.
    var newWays: [CardWay] {
        let started = Set(log.map { CardWay(cardID: $0.cardID, way: $0.way) })
        return ways.filter { !started.contains($0) }
    }

    /// The first reviews of new ways Lucas had on `now`'s day, by
    /// `calendar`, in the order they were written: the new cards a day
    /// count these.
    func firstReviews(onTheDayOf now: Date, calendar: Calendar) -> [ReviewLogEntry] {
        log.filter { $0.isFirstReview && calendar.isDate($0.answeredAt, inSameDayAs: now) }
    }
}

/// A deck at the top of the tree in the queue new ways come from, at its
/// place (ADR 0034).
struct PlacedDeck: Sendable, Equatable {
    /// The deck's whole name, or `""` for Default.
    let deck: String
    /// Its place: the queue goes from the earliest to the latest.
    let place: Date
}
