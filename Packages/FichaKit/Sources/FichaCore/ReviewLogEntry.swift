import Foundation

/// One entry in the review log: a card's first view, or a review of it. The
/// log is the source of truth: a card's step and due time are worked out from
/// its entries (ADR 0002).
public struct ReviewLogEntry: Sendable, Equatable {
    /// What Lucas did with the card.
    public enum Kind: Sendable, Equatable {
        /// He met it whole, and ended its first view with "Got it".
        case firstView
        /// He reviewed it, and rated it.
        case review(Rating)
    }

    public let cardID: Int64
    public let kind: Kind
    /// When he answered: with "Got it", or with his rating.
    public let answeredAt: Date
    /// How long he took, from the panel showing the card to his answer.
    public let responseTime: Duration
    public let trigger: Trigger

    public init(cardID: Int64, kind: Kind, answeredAt: Date, responseTime: Duration, trigger: Trigger) {
        self.cardID = cardID
        self.kind = kind
        self.answeredAt = answeredAt
        self.responseTime = responseTime
        self.trigger = trigger
    }
}
