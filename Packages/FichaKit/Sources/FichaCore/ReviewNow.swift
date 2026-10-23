import Foundation

/// The cards the review panel brings, by id: cards to review, then cards to
/// review ahead, then a new card to meet.
public struct PanelCardIDs: Sendable, Equatable {
    /// The cards to review, in this order.
    public let reviews: [Int64]
    /// The cards to review ahead, which aren't due yet, in this order.
    public let reviewsAhead: [Int64]
    /// A new card, to meet in its first view after them, if any.
    public let firstView: Int64?
}

extension ReviewSettings {
    /// The cards review now brings at `now`, out of `cards`: the due cards,
    /// and a new card, as `pickCards` picks them.
    public func reviewNowCards(
        cards: CardsInReviews,
        now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> PanelCardIDs {
        pickCards(after: try cards.standings(on: ladder), of: cards, dueBy: now, now: now, calendar: calendar)
    }

    /// The cards the review panel brings at `now`, out of `cards`, standing
    /// on the ladder as `standings` says, up to `cardsPerAppearance`: the
    /// priority cards due by `horizon`; then the first new priority card, if
    /// there's room and Lucas hasn't met `newCardsPerDay` today, by
    /// `calendar`'s day; then the other cards due by `horizon`; then, if no new
    /// card came yet, the first other new card, if there's room (ADR 0003) and
    /// he's under the limit. Due cards come lowest step first and then the
    /// longest overdue, and new cards in the order Lucas approved them. With
    /// no priority cards, that's the due cards and then the first new card.
    func pickCards(
        after standings: [(cardID: Int64, standing: LadderStanding)],
        of cards: CardsInReviews,
        dueBy horizon: Date,
        now: Date,
        calendar: Calendar
    ) -> PanelCardIDs {
        let sorted = SortedStandings(standings, dueBy: horizon)
        let due = cards.splitByPriority(sorted.due)
        let new = cards.splitByPriority(sorted.new)
        let metToday = cards.log.count { $0.kind == .firstView && calendar.isDate($0.answeredAt, inSameDayAs: now) }
        // A new priority card only waits for the due priority cards.
        var reviews = Array(due.priority.prefix(cardsPerAppearance))
        var firstView = bringsNewCard(after: reviews.count, metToday: metToday) ? new.priority.first : nil
        let slotsLeft = cardsPerAppearance - reviews.count - (firstView == nil ? 0 : 1)
        reviews += due.others.prefix(slotsLeft)
        if firstView == nil, bringsNewCard(after: reviews.count, metToday: metToday) {
            firstView = new.others.first
        }
        return PanelCardIDs(reviews: reviews, reviewsAhead: [], firstView: firstView)
    }

    /// Whether the review panel brings a new card after `reviews` cards to
    /// review, once Lucas met `metToday` new cards today: when there's room for
    /// it (ADR 0003) and he hasn't met `newCardsPerDay`.
    func bringsNewCard(after reviews: Int, metToday: Int) -> Bool {
        reviews < cardsPerAppearance && metToday < newCardsPerDay
    }

    /// The cards "See more" brings once Lucas went through the review panel's
    /// cards, those in `shown`, out of the other cards in `cards`: the cards
    /// due by `horizon` that didn't fit, as `pickCards` orders them, and then,
    /// if there's room, the cards closest to being due, as reviews ahead, up
    /// to `cardsPerAppearance`. Never a new card, so the day's new cards keep
    /// Lucas's load in the coming weeks as it was.
    public func seeMoreCards(
        cards: CardsInReviews,
        leavingOut shown: Set<Int64>,
        dueBy horizon: Date
    ) throws(UnexpectedReviewLog) -> PanelCardIDs {
        let others = try cards.standings(on: ladder).filter { !shown.contains($0.cardID) }
        let sorted = SortedStandings(others, dueBy: horizon)
        let reviews = Array(sorted.due.prefix(cardsPerAppearance))
        let reviewsAhead = Array(sorted.notDue.prefix(cardsPerAppearance - reviews.count))
        return PanelCardIDs(reviews: reviews, reviewsAhead: reviewsAhead, firstView: nil)
    }
}

/// The cards in Lucas's reviews by where they stand at a time, each group in
/// the order the review panel brings them.
private struct SortedStandings {
    /// The cards due by then: lowest step first, and then the longest overdue.
    let due: [Int64]
    /// The cards on the ladder that aren't due by then: the closest to being
    /// due first.
    let notDue: [Int64]
    /// The new cards, in the order Lucas approved them.
    let new: [Int64]

    /// The cards that stand as `standings` say, by id in the order Lucas
    /// approved them, sorted by whether they're due by `horizon`.
    init(_ standings: [(cardID: Int64, standing: LadderStanding)], dueBy horizon: Date) {
        var due: [(id: Int64, step: Int, due: Date)] = []
        var notDue: [(id: Int64, due: Date)] = []
        var new: [Int64] = []
        for (id, standing) in standings {
            switch standing {
            case .new:
                new.append(id)
            case .onLadder(let step, let dueTime) where standing.isDue(at: horizon):
                due.append((id, step, dueTime))
            case .onLadder(_, let dueTime):
                notDue.append((id, dueTime))
            }
        }
        // Cards on the same step and due at the same time come in the order
        // Lucas approved them.
        self.due = due.sorted { ($0.step, $0.due, $0.id) < ($1.step, $1.due, $1.id) }.map(\.id)
        self.notDue = notDue.sorted { ($0.due, $0.id) < ($1.due, $1.id) }.map(\.id)
        self.new = new
    }
}
