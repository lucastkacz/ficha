import Foundation

/// One entry in the review log: a card's first view, or a review of it. The
/// log is the source of truth: a card's step and due time are worked out from
/// its entries (ADR 0002).
public struct ReviewLogEntry: Sendable, Equatable {
    /// What Lucas did with the card.
    public enum Kind: Sendable, Equatable {
        /// He met it whole, in its first view.
        case firstView
        /// He reviewed it, and rated it.
        case review(Rating)
    }

    public let cardID: Int64
    public let kind: Kind
    /// When he answered: when he ended the first view, or when he rated the
    /// card.
    public let answeredAt: Date
    /// How long he took, from the panel showing the card to his answer, or
    /// nil when he answered from a card notification, where nothing measures
    /// it.
    public let responseTime: Duration?
    public let trigger: Trigger
    /// Whether it was a review ahead: of a card that wasn't due yet, which
    /// Lucas asked for. Only its again counts (ADR 0002).
    public let isAhead: Bool

    public init(
        cardID: Int64,
        kind: Kind,
        answeredAt: Date,
        responseTime: Duration?,
        trigger: Trigger,
        isAhead: Bool = false
    ) {
        self.cardID = cardID
        self.kind = kind
        self.answeredAt = answeredAt
        self.responseTime = responseTime
        self.trigger = trigger
        self.isAhead = isAhead
    }
}
