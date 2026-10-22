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
    /// The cards review now brings at `now`, out of the cards in Lucas's
    /// reviews, neither flagged nor buried, by id in the order he approved
    /// them, and the whole review log, in the order it was written: the due
    /// cards, and a new card, as `pickCards` picks them.
    public func reviewNowCards(
        cardIDs: [Int64],
        log: [ReviewLogEntry],
        now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> PanelCardIDs {
        pickCards(
            after: try ladder.standings(of: cardIDs, after: log), log: log, dueBy: now, now: now, calendar: calendar)
    }

    /// The cards the review panel brings at `now`, out of where each card in
    /// Lucas's reviews stands, by id in the order he approved them, and the
    /// whole review log: the cards due by `horizon`, lowest step first and
    /// then the longest overdue, up to `cardsPerAppearance`, and then the first
    /// new card he approved, if there's room (ADR 0003) and he hasn't met
    /// `newCardsPerDay` today, by `calendar`'s day.
    func pickCards(
        after standings: [(cardID: Int64, standing: LadderStanding)],
        log: [ReviewLogEntry],
        dueBy horizon: Date,
        now: Date,
        calendar: Calendar
    ) -> PanelCardIDs {
        let sorted = SortedStandings(standings, dueBy: horizon)
        let reviews = Array(sorted.due.prefix(cardsPerAppearance))
        let metToday = log.count { $0.kind == .firstView && calendar.isDate($0.answeredAt, inSameDayAs: now) }
        return PanelCardIDs(
            reviews: reviews, reviewsAhead: [],
            firstView: bringsNewCard(after: reviews.count, metToday: metToday) ? sorted.new.first : nil)
    }

    /// Whether the review panel brings a new card after `reviews` cards to
    /// review, once Lucas met `metToday` new cards today: when there's room for
    /// it (ADR 0003) and he hasn't met `newCardsPerDay`.
    func bringsNewCard(after reviews: Int, metToday: Int) -> Bool {
        reviews < cardsPerAppearance && metToday < newCardsPerDay
    }

    /// The cards "See more" brings at `now`, once Lucas went through the
    /// review panel's cards, out of the other cards in his reviews, by id in
    /// the order he approved them, and the whole review log, in the order it
    /// was written: the cards due by `horizon` that didn't fit, as `pickCards`
    /// orders them, and then, if there's room, the cards closest to being due,
    /// as reviews ahead, up to `cardsPerAppearance`. Never a new card, so the
    /// day's new cards keep Lucas's load in the coming weeks as it was.
    public func seeMoreCards(
        cardIDs: [Int64],
        log: [ReviewLogEntry],
        dueBy horizon: Date
    ) throws(UnexpectedReviewLog) -> PanelCardIDs {
        let sorted = SortedStandings(try ladder.standings(of: cardIDs, after: log), dueBy: horizon)
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
