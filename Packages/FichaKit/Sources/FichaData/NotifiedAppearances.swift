import FichaCore
import Foundation
internal import GRDB

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
}

extension Engine {
    /// Records Lucas's answer to a card from its card notification, in
    /// `appearance`, with one of the notification's buttons, and returns the
    /// card whose notification comes next, or nil once none is left. The
    /// answer, the end of a new card's first view or a review with his
    /// rating, goes into the review log as an appearance's, with no response
    /// time, since nothing measures how long he looked at the card. The next
    /// card is the first of the appearance's after this one that he can still
    /// answer, as `ReviewSettings.nextCard` says: one he rated in the app,
    /// flagged or buried meanwhile is skipped. The appearance goes into the
    /// appearance log, from when it showed to now: as finished once no card is
    /// left, and otherwise as a snooze, until his next answer from it moves
    /// its closing on. The next appearance waits from that closing.
    public func answerFromNotification(
        _ kind: ReviewLogEntry.Kind,
        of cardID: Int64,
        in appearance: NotifiedAppearance,
        settings: ReviewSettings
    ) throws(EngineError) -> PanelCard? {
        let answeredAt = time.now
        return try write { db in
            try recordAnswer(
                kind, of: cardID, at: answeredAt, responseTime: nil, trigger: .appearance, settings: settings,
                reviewingAhead: false, in: db)
            let cards = try cardsInReviews(in: db)
            let next = try settings.nextCard(
                after: cardID, in: appearance.cardIDs, cardIDs: cards.map(\.id), log: logEntries(in: db),
                now: answeredAt)
            let nextCard = try panelCards(next, from: cards).first
            try noteClosing(of: appearance, at: answeredAt, finished: nextCard == nil, in: db)
            return nextCard
        }
    }
}

/// Notes in the appearance log that `appearance` closes at `closedAt`, as
/// Lucas answers one of its card notifications: as finished once he went
/// through its cards, and as a snooze otherwise. The first answer adds its
/// entry, and each one after it moves the entry's closing on.
private func noteClosing(of appearance: NotifiedAppearance, at closedAt: Date, finished: Bool, in db: Database)
    throws
{
    let outcome: AppearanceLogEntry.Outcome = finished ? .finished : .snoozed
    let entry = try Int64.fetchOne(
        db,
        sql: "SELECT id FROM appearanceLog WHERE trigger = ? AND shownAt = ? AND outcome != ? ORDER BY id DESC LIMIT 1",
        arguments: [Trigger.appearance.rawValue, appearance.shownAt, OutcomeName.heldBack.rawValue])
    guard let entry else {
        try insert(
            AppearanceLogEntry(trigger: .appearance, shownAt: appearance.shownAt, closedAt: closedAt, outcome: outcome),
            in: db)
        return
    }
    try db.execute(
        sql: "UPDATE appearanceLog SET closedAt = ?, outcome = ? WHERE id = ?",
        arguments: [closedAt, outcome.columns.outcome, entry])
}
