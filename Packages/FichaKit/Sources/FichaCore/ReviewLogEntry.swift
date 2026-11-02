import Foundation

/// One entry in the review log: a review of a card's way, or the progress an
/// import placed it with. The log is the source of truth: where each way
/// stands and when it's due are worked out from its entries (#404, ADR 0013).
public struct ReviewLogEntry: Sendable, Equatable {
    /// What happened to the card.
    public enum Kind: Sendable, Equatable {
        /// The user reviewed it, and rated it: a new way's first review, or a
        /// later one.
        case review(Rating)
        /// An import that brought its progress from another app, such as
        /// Anki, placed it, with the interval, due date and ease it had there
        /// (ADR 0013). Nobody answered it.
        case placement(Placement)
    }

    public let cardID: Int64
    /// Which of the card's ways it went: each way has its own progress
    /// (ADR 0016).
    public let way: Way
    public let kind: Kind
    /// When he answered, rating the card; for a placement, when the import
    /// placed it.
    public let answeredAt: Date
    /// How long he took, from the panel showing the card to his answer, or
    /// nil when he answered from a card notification, where nothing measures
    /// it, and for a placement, which no one answered.
    public let responseTime: Duration?
    /// What brought the card, or nil for a placement, which nothing brought,
    /// and for another app's review, which an import brings (#409).
    public let trigger: Trigger?
    /// Whether it was a review ahead: of a way that wasn't due yet, which
    /// Lucas asked for, as the device that recorded it saw it then, for the
    /// Cards window's "Ahead" badge. The scheduler doesn't read it: it works
    /// out a review ahead from the time the way really waited (#404).
    public let isAhead: Bool
    /// Its ID unique across devices, which the review log gives it as it
    /// keeps it, or nil for an entry it doesn't keep yet.
    public let uuid: UUID?
    /// For a review, the entry it answered, by its ID unique across devices:
    /// the last entry of its way that the device knew when Lucas rated the
    /// card, which two devices' reviews of one interval share. Nil for a new
    /// way's first review, which answered none, and for a placement.
    public let answeredEntry: UUID?
    /// For a review, the interval it set, which the way waits from when
    /// Lucas answered, as the scheduler's preview gave it for the rating:
    /// the scheduler keeps it, so a change to the settings leaves the way's
    /// due time alone until its next review (#404). Nil for a placement,
    /// which holds its own, and for a review not kept yet that keeps none,
    /// which gets the one the scheduler works out.
    public let interval: Duration?

    /// A review of the card with the id `cardID`, the way it went, front
    /// first unless it's said to go back first, which `trigger` brought, kept
    /// as `uuid` once the review log keeps it, answering `answeredEntry` and
    /// keeping `interval`.
    public init(
        cardID: Int64,
        way: Way = .frontFirst,
        kind: Kind,
        answeredAt: Date,
        responseTime: Duration?,
        trigger: Trigger?,
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

    /// Whether the entry is a placement, which an import gives a card where
    /// the other app's reviews of it start, or after them, and nobody
    /// answered.
    public var isPlacement: Bool {
        if case .placement = kind { true } else { false }
    }

    /// The card's way it went.
    var cardWay: CardWay {
        CardWay(cardID: cardID, way: way)
    }

    /// This entry, answering `answeredEntry` and keeping `interval`, as the
    /// scheduler keeps a review it gave its interval.
    func answering(_ answeredEntry: UUID?, keeping interval: Duration) -> ReviewLogEntry {
        ReviewLogEntry(
            cardID: cardID, way: way, kind: kind, answeredAt: answeredAt, responseTime: responseTime,
            trigger: trigger, isAhead: isAhead, uuid: uuid, answeredEntry: answeredEntry, interval: interval)
    }
}

/// The progress an import that brings a card's progress from another app,
/// such as Anki, places it with (ADR 0013): the interval it had there, its
/// due time, and Anki's ease. It starts a way the import brings without
/// reviews, or with none of its first ones, or follows its imported reviews
/// to keep the due date Anki gave it (#404).
public struct Placement: Sendable, Equatable {
    /// The card's interval in the other app: a day or more for a card it had
    /// graduated, and less, zero included, for one it was learning.
    public let interval: Duration
    public let due: Date
    /// The card's ease in Anki, such as 2.5 for 250%, from which the
    /// scheduler starts the memory of a graduated card that comes without
    /// reviews. Nil when Anki gave none, as for a card it was learning.
    public let ease: Double?

    public init(interval: Duration, due: Date, ease: Double? = nil) {
        self.interval = interval
        self.due = due
        self.ease = ease
    }
}
