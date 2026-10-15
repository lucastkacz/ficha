import Foundation

/// The cards the review panel brings, by id: cards to review, then a new card
/// to meet.
public struct PanelCardIDs: Sendable, Equatable {
    /// The cards to review, in this order.
    public let reviews: [Int64]
    /// A new card, to meet in its first view after them, if any.
    public let firstView: Int64?
}

extension ReviewSettings {
    /// The cards review now brings at `now`, out of every card, by id in the
    /// order Lucas approved them, and the whole review log, in the order it
    /// was written: the due cards, and a new card, as `panelCards` picks them.
    public func reviewNowCards(
        cardIDs: [Int64],
        log: [ReviewLogEntry],
        now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> PanelCardIDs {
        panelCards(
            after: try ladder.standings(of: cardIDs, after: log), log: log, dueBy: now, now: now, calendar: calendar)
    }

    /// The cards the review panel brings at `now`, out of where every card
    /// stands, by id in the order Lucas approved them, and the whole review
    /// log: the cards due by `horizon`, lowest step first and then the
    /// longest overdue, up to `cardsPerAppearance`, and then the first new
    /// card Lucas approved, if there's room (ADR 0003) and he hasn't met
    /// `newCardsPerDay` today, by `calendar`'s day.
    func panelCards(
        after standings: [(cardID: Int64, standing: CardStanding)],
        log: [ReviewLogEntry],
        dueBy horizon: Date,
        now: Date,
        calendar: Calendar
    ) -> PanelCardIDs {
        var due: [(id: Int64, step: Int, due: Date)] = []
        var new: [Int64] = []
        for (id, standing) in standings {
            switch standing {
            case .new:
                new.append(id)
            case .onLadder(let step, let dueTime) where standing.isDue(at: horizon):
                due.append((id, step, dueTime))
            case .onLadder:
                break
            }
        }
        // Cards on the same step and due at the same time come in the order
        // Lucas approved them.
        let reviews = due.sorted { ($0.step, $0.due, $0.id) < ($1.step, $1.due, $1.id) }
            .prefix(cardsPerAppearance)
            .map(\.id)
        let hasRoom = reviews.count < cardsPerAppearance
        let metToday = log.count { $0.kind == .firstView && calendar.isDate($0.answeredAt, inSameDayAs: now) }
        let mayMeetMore = metToday < newCardsPerDay
        return PanelCardIDs(reviews: reviews, firstView: hasRoom && mayMeetMore ? new.first : nil)
    }
}
