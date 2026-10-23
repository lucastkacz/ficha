import Foundation

/// One entry in the review log: a card's first view, or a review of it, or
/// the step an import placed it on. The log is the source of truth: a card's
/// step and due time are worked out from its entries (ADR 0002, ADR 0013).
public struct ReviewLogEntry: Sendable, Equatable {
    /// What happened to the card.
    public enum Kind: Sendable, Equatable {
        /// Lucas met it whole, in its first view.
        case firstView
        /// He reviewed it, and rated it.
        case review(Rating)
        /// An import that brought its progress from another app, such as
        /// Anki, placed it on this step of the ladder, counted from 0, the
        /// first step, due at `due` (ADR 0013). Nobody answered it: like a
        /// first view, it can only start a card's log.
        case placement(step: Int, due: Date)
    }

    public let cardID: Int64
    public let kind: Kind
    /// When he answered: when he ended the first view, or when he rated the
    /// card; for a placement, when the import placed it.
    public let answeredAt: Date
    /// How long he took, from the panel showing the card to his answer, or
    /// nil when he answered from a card notification, where nothing measures
    /// it, and for a placement, which no one answered.
    public let responseTime: Duration?
    /// What brought the card, or nil for a placement, which nothing brought.
    public let trigger: Trigger?
    /// Whether it was a review ahead: of a card that wasn't due yet, which
    /// Lucas asked for. Only its again counts (ADR 0002).
    public let isAhead: Bool

    /// An answer: a first view or a review of the card with the id `cardID`,
    /// which `trigger` brought.
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

    /// The placement an import gives the card with the id `cardID` at
    /// `placedAt`: on `step`, due at `due`.
    public init(placing cardID: Int64, on step: Int, dueAt due: Date, at placedAt: Date) {
        self.cardID = cardID
        kind = .placement(step: step, due: due)
        answeredAt = placedAt
        responseTime = nil
        trigger = nil
        isAhead = false
    }
}
