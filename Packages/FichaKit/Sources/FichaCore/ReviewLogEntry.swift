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
    /// device that recorded it knew then (ADR 0017): the ladder also counts a
    /// good as ahead when another device's good had climbed the wait it
    /// answered, and a review ahead as on time when an entry this device
    /// didn't know of had made the card due by then.
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
    /// For a review, the interval it set, which the way waits from when
    /// Lucas answered, as the scheduler's preview gave it for the rating:
    /// the scheduler keeps it, so a change to the settings leaves the way's
    /// due time alone until its next review (#404). Nil for a first view or
    /// a placement, and for a review from before Ficha kept it, which gets
    /// the one the scheduler works out.
    public let interval: Duration?

    /// An answer: a first view or a review of the card with the id `cardID`,
    /// the way it went, front first unless it's said to go back first, which
    /// `trigger` brought, kept as `uuid` once the review log keeps it, and,
    /// for a review, answering `answeredEntry` and keeping `interval`.
    public init(
        cardID: Int64,
        way: Way = .frontFirst,
        kind: Kind,
        answeredAt: Date,
        responseTime: Duration?,
        trigger: Trigger,
        isAhead: Bool = false,
        uuid: UUID? = nil,
        answeredEntry: UUID? = nil,
        interval: Duration? = nil
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
        self.interval = interval
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
        interval = nil
    }

    /// The card's way it went.
    var cardWay: CardWay {
        CardWay(cardID: cardID, way: way)
    }
}

/// Where an import that brings a card's progress from another app, such as
/// Anki, places it on the ladder, in place of a first view (ADR 0013): on
/// `step`, counted from 0, the first step, due at `due`. For the scheduler
/// it holds the card's interval there and Anki's ease, in place of a step:
/// it starts a way the import brings without reviews, or follows its
/// imported reviews to keep the due date Anki gave it (#404).
public struct Placement: Sendable, Equatable {
    public let step: Int
    public let due: Date
    /// The card's interval in the other app, which the scheduler reads: a
    /// day or more for a card it had graduated, and less for one it was
    /// learning. Nil for a placement on the ladder alone.
    public let interval: Duration?
    /// The card's ease in Anki, such as 2.5 for 250%, from which the
    /// scheduler starts the memory of a graduated card that comes without
    /// reviews. Nil when Anki gave none, as for a card it was learning.
    public let ease: Double?

    public init(step: Int, due: Date, interval: Duration? = nil, ease: Double? = nil) {
        self.step = step
        self.due = due
        self.interval = interval
        self.ease = ease
    }
}
