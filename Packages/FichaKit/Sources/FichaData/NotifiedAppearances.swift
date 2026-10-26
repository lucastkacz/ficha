import FichaCore
import Foundation

/// An appearance on the iPhone, as each of its card notifications carries it
/// (ADR 0010): when it showed, and the cards it brought.
public struct NotifiedAppearance: Sendable, Equatable {
    /// When its first card notification showed, by the engine's time.
    public let shownAt: Date
    /// The cards it brought, by id, in the order their notifications show.
    public let cardIDs: [Int64]

    public init(shownAt: Date, cardIDs: [Int64]) {
        self.shownAt = shownAt
        self.cardIDs = cardIDs
    }

    /// `upcoming`, as its card notifications carry it: shown at its time, as
    /// the engine keeps it in its plan, which is how the appearance log finds
    /// it.
    public init(_ upcoming: UpcomingAppearance) {
        self.init(shownAt: upcoming.time, cardIDs: upcoming.cards.map(\.card.id))
    }

    /// The ways it brought, in the order their notifications show: each card
    /// front first, since card notifications don't go back first (#97).
    var ways: [CardWay] {
        cardIDs.map { CardWay(cardID: $0, way: .frontFirst) }
    }
}

extension Engine {
    /// Records Lucas's answer to a card from its card notification, in
    /// `appearance`, with one of the notification's buttons, and returns the
    /// card whose notification comes next, or nil once none is left. The
    /// answer, the end of a new card's first view or a review with his
    /// rating, goes into the review log as an appearance's, with no response
    /// time, since nothing measures how long he looked at the card. An answer
    /// to a card the appearance didn't bring is refused. The next card is the
    /// first of the appearance's after this one that he can still answer, as
    /// `ReviewSettings.nextCard` says: one he rated in the app, flagged or
    /// buried meanwhile is skipped. The appearance goes into the appearance
    /// log, from when it showed to now: as finished once no card is left, and
    /// otherwise as a snooze, until his next answer from it moves its closing
    /// on. The next appearance waits from that closing.
    public func answerFromNotification(
        _ kind: ReviewLogEntry.Kind,
        of cardID: Int64,
        in appearance: NotifiedAppearance,
        settings: ReviewSettings
    ) throws(EngineError) -> PanelCard? {
        guard let answered = appearance.ways.first(where: { $0.cardID == cardID }) else {
            throw .cardNotInAppearance(cardID)
        }
        let answeredAt = time.now
        return try write { db in
            try recordAnswer(
                kind, of: answered, at: answeredAt, responseTime: nil, trigger: .appearance, settings: settings,
                reviewingAhead: false, in: db)
            let cards = try cardsThatShowUp(in: db)
            let next = try settings.nextCard(
                after: answered, in: appearance.ways, cards: cards.inReviews, now: answeredAt)
            let nextCard = try cards.panelCards(next).first
            try noteClosing(of: appearance, at: answeredAt, finished: nextCard == nil, in: db)
            return nextCard
        }
    }

    /// Records that Lucas swiped away one of `appearance`'s card
    /// notifications, a plain "not now" that leaves its cards as they were
    /// (#97): the appearance goes into the appearance log as a snooze, closed
    /// now, as the Mac's review panel does when he closes it with cards left.
    /// The next appearance waits from now.
    public func snoozeFromNotification(_ appearance: NotifiedAppearance) throws(EngineError) {
        let snoozedAt = time.now
        try write { db in
            try noteClosing(of: appearance, at: snoozedAt, finished: false, in: db)
        }
    }
}
