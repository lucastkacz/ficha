import Foundation

/// The cards the review panel brings, each by id and the way it shows: ways
/// to review, then ways to review ahead, then a new way, unless one of them
/// comes before all the others.
public struct PanelCardIDs: Sendable, Equatable {
    /// The ways to review, in this order.
    public let reviews: [CardWay]
    /// The ways to review ahead, which aren't due yet, in this order.
    public let reviewsAhead: [CardWay]
    /// A new way, for its first review after them, if any.
    public let newWay: CardWay?
    /// The way that comes before all the others, one of them, or nil when
    /// they come in the order above: the card a click on the widget showed.
    public let shownFirst: CardWay?

    init(reviews: [CardWay], reviewsAhead: [CardWay], newWay: CardWay?, shownFirst: CardWay? = nil) {
        self.reviews = reviews
        self.reviewsAhead = reviewsAhead
        self.newWay = newWay
        self.shownFirst = shownFirst
    }
}

extension ReviewSettings {
    /// The ways review now brings at `now`, out of `cards`: the due ways, and
    /// a new way, as `pickCards` picks them. A click on the widget asks it to
    /// start with `first`, the card the widget showed, the way it showed it:
    /// then `first` comes first, when review now brings it, and the others
    /// follow in their order. When it no longer brings it, as when Lucas
    /// reviewed it meanwhile, review now brings its ways as usual.
    public func reviewNowCards(
        cards: CardsInReviews,
        now: Date,
        calendar: Calendar,
        startingWith first: CardWay? = nil
    ) throws(SchedulingError) -> PanelCardIDs {
        let picked = pickCards(
            after: try cards.standings(with: scheduler), of: cards, dueBy: now, now: now, calendar: calendar)
        guard let first, picked.reviews.contains(first) || picked.newWay == first else {
            return picked
        }
        return PanelCardIDs(
            reviews: picked.reviews, reviewsAhead: picked.reviewsAhead, newWay: picked.newWay, shownFirst: first)
    }

    /// The ways the review panel brings at `now`, out of `cards`, standing as
    /// `standings` says, up to `cardsPerAppearance`: the priority cards' ways
    /// due by `horizon`; then a new way of a priority card, if there's room
    /// and Lucas hasn't had `newCardsPerDay` first reviews of new ways today,
    /// either way, by `calendar`'s day; then the other ways due by `horizon`;
    /// then, if no new way came yet, another new way, if there's room
    /// (ADR 0003) and he's under the limit. Due ways come shortest interval
    /// first, and then the longest overdue. New cards and new back-first ways
    /// take turns: the new way goes the other way from Lucas's latest first
    /// review today, front first when he had none, unless none waits that
    /// way; each way's new ones come by card in the order he approved them.
    /// With no priority cards, that's the due ways and then a new way.
    func pickCards(
        after standings: [(way: CardWay, standing: WayStanding)],
        of cards: CardsInReviews,
        dueBy horizon: Date,
        now: Date,
        calendar: Calendar
    ) -> PanelCardIDs {
        let sorted = SortedStandings(standings, dueBy: horizon)
        let due = cards.splitByPriority(sorted.due)
        let new = cards.splitByPriority(sorted.new)
        let firstReviewsToday = cards.log.filter {
            $0.isFirstReview && calendar.isDate($0.answeredAt, inSameDayAs: now)
        }
        let metToday = firstReviewsToday.count
        let turn: Way = firstReviewsToday.last?.way == .frontFirst ? .backFirst : .frontFirst
        // A new way of a priority card only waits for the due ways of
        // priority cards.
        var reviews = Array(due.priority.prefix(cardsPerAppearance))
        var newWay =
            bringsNewCard(after: reviews.count, metToday: metToday) ? new.priority.first(preferring: turn) : nil
        let slotsLeft = cardsPerAppearance - reviews.count - (newWay == nil ? 0 : 1)
        reviews += due.others.prefix(slotsLeft)
        if newWay == nil, bringsNewCard(after: reviews.count, metToday: metToday) {
            newWay = new.others.first(preferring: turn)
        }
        return PanelCardIDs(reviews: reviews, reviewsAhead: [], newWay: newWay)
    }

    /// Whether the review panel brings a new way after `reviews` ways to
    /// review, once Lucas had `metToday` first reviews of new ways today:
    /// when there's room for it (ADR 0003) and he hasn't had
    /// `newCardsPerDay`.
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
    ) throws(SchedulingError) -> PanelCardIDs {
        let others = try cards.standings(with: scheduler).filter { !shown.contains($0.way) }
        let sorted = SortedStandings(others, dueBy: horizon)
        let due = cards.splitByPriority(sorted.due)
        let notDue = cards.splitByPriority(sorted.notDue)
        let reviews = Array((due.priority + due.others).prefix(cardsPerAppearance))
        let reviewsAhead = Array((notDue.priority + notDue.others).prefix(cardsPerAppearance - reviews.count))
        return PanelCardIDs(reviews: reviews, reviewsAhead: reviewsAhead, newWay: nil)
    }
}

extension [CardWay] {
    /// The first of these new ways that goes `turn`, the way whose turn it
    /// is, or else the first of them, or nil when there are none.
    fileprivate func first(preferring turn: Way) -> CardWay? {
        first { $0.way == turn } ?? first
    }
}

/// The ways in Lucas's reviews by where they stand at a time, each group in
/// the order the review panel brings them.
private struct SortedStandings {
    /// The ways due by then: shortest interval first, as the cards Lucas is
    /// likeliest to forget, and then the longest overdue.
    let due: [CardWay]
    /// The started ways that aren't due by then: the closest to being due
    /// first.
    let notDue: [CardWay]
    /// The new ways, by card in the order Lucas approved them, each card's
    /// front-first way first.
    let new: [CardWay]

    /// The ways that stand as `standings` say, by card in the order Lucas
    /// approved them, each card's front-first way first, sorted by whether
    /// they're due by `horizon`.
    init(_ standings: [(way: CardWay, standing: WayStanding)], dueBy horizon: Date) {
        var due: [(way: CardWay, interval: Duration, due: Date, order: Int)] = []
        var notDue: [(way: CardWay, due: Date, order: Int)] = []
        var new: [CardWay] = []
        for (order, (way, standing)) in standings.enumerated() {
            switch standing {
            case .new:
                new.append(way)
            case .started(_, let interval, let dueTime, _) where standing.isDue(at: horizon):
                due.append((way, interval, dueTime, order))
            case .started(_, _, let dueTime, _):
                notDue.append((way, dueTime, order))
            }
        }
        // Ways with the same interval and due at the same time keep their
        // order: by card in the order Lucas approved them, each card's
        // front-first way first.
        self.due = due.sorted { ($0.interval, $0.due, $0.order) < ($1.interval, $1.due, $1.order) }.map(\.way)
        self.notDue = notDue.sorted { ($0.due, $0.order) < ($1.due, $1.order) }.map(\.way)
        self.new = new
    }
}
