import Foundation

/// The cards the review panel brings, each by id and the way it shows: ways
/// to review, then ways to review ahead, then a new way to meet.
public struct PanelCardIDs: Sendable, Equatable {
    /// The ways to review, in this order.
    public let reviews: [CardWay]
    /// The ways to review ahead, which aren't due yet, in this order.
    public let reviewsAhead: [CardWay]
    /// A new way, to meet in its first view after them, if any.
    public let firstView: CardWay?
}

extension ReviewSettings {
    /// The ways review now brings at `now`, out of `cards`: the due ways, and
    /// a new way, as `pickCards` picks them.
    public func reviewNowCards(
        cards: CardsInReviews,
        now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> PanelCardIDs {
        pickCards(after: try cards.standings(on: ladder), of: cards, dueBy: now, now: now, calendar: calendar)
    }

    /// The ways the review panel brings at `now`, out of `cards`, standing on
    /// the ladder as `standings` says, up to `cardsPerAppearance`: the
    /// priority cards' ways due by `horizon`; then a new way of a priority
    /// card, if there's room and Lucas hasn't had `newCardsPerDay` first
    /// views today, either way, by `calendar`'s day; then the other ways due
    /// by `horizon`; then, if no new way came yet, another new way, if
    /// there's room (ADR 0003) and he's under the limit. Due ways come lowest
    /// step first and then the longest overdue. New cards and new back-first
    /// ways take turns: the new way goes the other way from Lucas's latest
    /// first view today, front first when he had none, unless none waits that
    /// way; each way's new ones come by card in the order he approved them.
    /// With no priority cards, that's the due ways and then a new way.
    func pickCards(
        after standings: [(way: CardWay, standing: LadderStanding)],
        of cards: CardsInReviews,
        dueBy horizon: Date,
        now: Date,
        calendar: Calendar
    ) -> PanelCardIDs {
        let sorted = SortedStandings(standings, dueBy: horizon)
        let due = cards.splitByPriority(sorted.due)
        let new = cards.splitByPriority(sorted.new)
        let firstViewsToday = cards.log.filter {
            $0.kind == .firstView && calendar.isDate($0.answeredAt, inSameDayAs: now)
        }
        let metToday = firstViewsToday.count
        let turn: Way = firstViewsToday.last?.way == .frontFirst ? .backFirst : .frontFirst
        // A new way of a priority card only waits for the due ways of
        // priority cards.
        var reviews = Array(due.priority.prefix(cardsPerAppearance))
        var firstView =
            bringsNewCard(after: reviews.count, metToday: metToday) ? new.priority.taking(turn: turn) : nil
        let slotsLeft = cardsPerAppearance - reviews.count - (firstView == nil ? 0 : 1)
        reviews += due.others.prefix(slotsLeft)
        if firstView == nil, bringsNewCard(after: reviews.count, metToday: metToday) {
            firstView = new.others.taking(turn: turn)
        }
        return PanelCardIDs(reviews: reviews, reviewsAhead: [], firstView: firstView)
    }

    /// Whether the review panel brings a new way after `reviews` ways to
    /// review, once Lucas had `metToday` first views today: when there's room
    /// for it (ADR 0003) and he hasn't had `newCardsPerDay`.
    func bringsNewCard(after reviews: Int, metToday: Int) -> Bool {
        reviews < cardsPerAppearance && metToday < newCardsPerDay
    }

    /// The ways "See more" brings once Lucas went through the review panel's
    /// ways, those in `shown`, out of the other ways in `cards`: the ways due
    /// by `horizon` that didn't fit, priority cards' first, each group as
    /// `pickCards` orders it, and then, if there's room, the ways closest to
    /// being due, priority cards' first, as reviews ahead, up to
    /// `cardsPerAppearance`. Never a new way, so the day's new cards keep
    /// Lucas's load in the coming weeks as it was.
    public func seeMoreCards(
        cards: CardsInReviews,
        leavingOut shown: Set<CardWay>,
        dueBy horizon: Date
    ) throws(UnexpectedReviewLog) -> PanelCardIDs {
        let others = try cards.standings(on: ladder).filter { !shown.contains($0.way) }
        let sorted = SortedStandings(others, dueBy: horizon)
        let due = cards.splitByPriority(sorted.due)
        let notDue = cards.splitByPriority(sorted.notDue)
        let reviews = Array((due.priority + due.others).prefix(cardsPerAppearance))
        let reviewsAhead = Array((notDue.priority + notDue.others).prefix(cardsPerAppearance - reviews.count))
        return PanelCardIDs(reviews: reviews, reviewsAhead: reviewsAhead, firstView: nil)
    }
}

extension [CardWay] {
    /// The first of these new ways that goes `turn`'s way, whose turn it is,
    /// or else the first of them, or nil when there are none.
    fileprivate func taking(turn: Way) -> CardWay? {
        first { $0.way == turn } ?? first
    }
}

/// The ways in Lucas's reviews by where they stand at a time, each group in
/// the order the review panel brings them.
private struct SortedStandings {
    /// The ways due by then: lowest step first, and then the longest overdue.
    let due: [CardWay]
    /// The ways on the ladder that aren't due by then: the closest to being
    /// due first.
    let notDue: [CardWay]
    /// The new ways, by card in the order Lucas approved them, each card's
    /// front-first way first.
    let new: [CardWay]

    /// The ways that stand as `standings` say, by card in the order Lucas
    /// approved them, each card's front-first way first, sorted by whether
    /// they're due by `horizon`.
    init(_ standings: [(way: CardWay, standing: LadderStanding)], dueBy horizon: Date) {
        var due: [(way: CardWay, step: Int, due: Date, order: Int)] = []
        var notDue: [(way: CardWay, due: Date, order: Int)] = []
        var new: [CardWay] = []
        for (order, (way, standing)) in standings.enumerated() {
            switch standing {
            case .new:
                new.append(way)
            case .onLadder(let step, let dueTime) where standing.isDue(at: horizon):
                due.append((way, step, dueTime, order))
            case .onLadder(_, let dueTime):
                notDue.append((way, dueTime, order))
            }
        }
        // Ways on the same step and due at the same time keep their order:
        // by card in the order Lucas approved them, each card's front-first
        // way first.
        self.due = due.sorted { ($0.step, $0.due, $0.order) < ($1.step, $1.due, $1.order) }.map(\.way)
        self.notDue = notDue.sorted { ($0.due, $0.order) < ($1.due, $1.order) }.map(\.way)
        self.new = new
    }
}
