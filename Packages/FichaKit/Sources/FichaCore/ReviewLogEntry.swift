import Foundation

/// One entry in the review log: a card's first view, or a review of it, or
/// the step an import placed it on. The log is the source of truth: a card's
/// step and due time are worked out from its entries (ADR 0002, ADR 0013).
public struct ReviewLogEntry: Sendable, Equatable {
    /// What happened to the card.
    public enum Kind: Sendable, Equatable {
        /// The user met it whole, in its first view.
        case firstView
        /// The user reviewed it, and rated it.
        case review(Rating)
        /// An import that brought its progress from another app, such as
        /// Anki, placed it on the ladder (ADR 0013). Nobody answered it: like
        /// a first view, it can only start a card's log.
        case placement(Placement)
    }

    public let cardID: Int64
    /// Which of the card's ways it went: each way has its own progress
    /// (ADR 0016).
    public let way: Way
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
    /// Lucas asked for. Only its again counts (ADR 0002). It's what the
    /// device that recorded it knew then: the ladder also counts a good as
    /// ahead when another device's good had answered the same wait
    /// (ADR 0017).
    public let isAhead: Bool
    /// Its ID unique across devices, which the review log gives it as it
    /// keeps it, or nil for an entry it doesn't keep yet.
    public let uuid: UUID?
    /// For a review, the entry it answered, by its ID unique across devices:
    /// the last entry of its way that the device knew when Lucas rated the
    /// card, which two devices' reviews of one wait share. Nil for a first
    /// view or a placement, which answer none, and for a review from before
    /// Ficha kept it, which answered the entry before it.
    public let answeredEntry: UUID?

    /// An answer: a first view or a review of the card with the id `cardID`,
    /// the way it went, front first unless it's said to go back first, which
    /// `trigger` brought, kept as `uuid` once the review log keeps it, and,
    /// for a review, answering `answeredEntry`.
    public init(
        cardID: Int64,
        way: Way = .frontFirst,
        kind: Kind,
        answeredAt: Date,
        responseTime: Duration?,
        trigger: Trigger,
        isAhead: Bool = false,
        uuid: UUID? = nil,
        answeredEntry: UUID? = nil
    ) {
        self.cardID = cardID
        self.way = way
        self.kind = kind
        self.answeredAt = answeredAt
        self.responseTime = responseTime
        self.trigger = trigger
        self.isAhead = isAhead
        self.uuid = uuid
        self.answeredEntry = answeredEntry
    }

    /// The entry of `placement`, which an import gives the card with the id
    /// `cardID`, the way it's said to go, front first unless it's said to go
    /// back first, at `placedAt`, kept as `uuid` once the review log keeps
    /// it.
    public init(
        placing cardID: Int64, way: Way = .frontFirst, on placement: Placement, at placedAt: Date, uuid: UUID? = nil
    ) {
        self.cardID = cardID
        self.way = way
        kind = .placement(placement)
        answeredAt = placedAt
        responseTime = nil
        trigger = nil
        isAhead = false
        self.uuid = uuid
        answeredEntry = nil
    }

    /// The card's way it went.
    var cardWay: CardWay {
        CardWay(cardID: cardID, way: way)
    }
}

/// Where an import that brings a card's progress from another app, such as
/// Anki, places it on the ladder, in place of a first view (ADR 0013): on
/// `step`, counted from 0, the first step, due at `due`.
public struct Placement: Sendable, Equatable {
    public let step: Int
    public let due: Date

    public init(step: Int, due: Date) {
        self.step = step
        self.due = due
    }
}
