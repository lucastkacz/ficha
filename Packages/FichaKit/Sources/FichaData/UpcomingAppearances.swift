import FichaCore
import Foundation
internal import GRDB

/// An appearance the engine plans ahead, for the iPhone, which schedules it
/// as card notifications (ADR 0010): when it comes, and the cards it brings.
public struct UpcomingAppearance: Sendable, Equatable {
    /// When it comes, by the engine's time.
    public let time: Date
    /// The cards it brings, in the order they show.
    public let cards: [PanelCard]

    public init(time: Date, cards: [PanelCard]) {
        self.time = time
        self.cards = cards
    }
}

extension Engine {
    /// The most appearances the engine plans ahead: iOS keeps at most 64
    /// notifications pending for an app (#97), and the plan stops one short of
    /// them, so the app has room for one more it sends right away.
    public static let mostUpcomingAppearances = 63

    /// The appearances that come from now on, as if Lucas rated nothing in
    /// between, for the iPhone to schedule as card notifications (ADR 0010):
    /// within active hours, once a card is due or a new card may come in, and
    /// once the separation passed since the one before, or since the last
    /// appearance or review now that closed, each with the cards it brings,
    /// as on the Mac. They're as many as fit in iOS's notifications.
    public func upcomingAppearances(_ settings: ReviewSettings) throws(EngineError) -> [UpcomingAppearance] {
        let now = time.now
        return try read { db in
            let cards = try cardsInReviews(in: db)
            let planned = try settings.plannedAppearances(
                cardIDs: cards.map(\.id), log: logEntries(in: db), lastClosing: lastClosing(in: db), from: now,
                calendar: calendar, upTo: Self.mostUpcomingAppearances)
            return try planned.map { UpcomingAppearance(time: $0.time, cards: try panelCards($0.cardIDs, from: cards)) }
        }
    }
}
