import Foundation

/// The cards review now brings, by id: due cards to review, then a new card
/// to meet.
public struct ReviewNowCards: Sendable, Equatable {
    /// The due cards, to review in this order.
    public let reviews: [Int64]
    /// A new card, to meet in its first view after them, if any.
    public let firstView: Int64?
}

extension ReviewSettings {
    /// The cards review now brings at `now`, out of every card, by id in the
    /// order Lucas approved them, and the whole review log, in the order it
    /// was written: the due cards, lowest step first and then the longest
    /// overdue, up to `cardsPerAppearance`, and then the first new card Lucas
    /// approved, if there's room (ADR 0003) and he hasn't met
    /// `newCardsPerDay` today, by `calendar`'s day.
    public func reviewNowCards(
        cardIDs: [Int64],
        log: [ReviewLogEntry],
        now: Date,
        calendar: Calendar
    ) throws(UnexpectedReviewLog) -> ReviewNowCards {
        var due: [(id: Int64, step: Int, due: Date)] = []
        var new: [Int64] = []
        for (id, standing) in try ladder.standings(of: cardIDs, after: log) {
            switch standing {
            case .new:
                new.append(id)
            case .onLadder(let step, let dueTime) where standing.isDue(at: now):
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
        return ReviewNowCards(reviews: reviews, firstView: hasRoom && mayMeetMore ? new.first : nil)
    }
}
