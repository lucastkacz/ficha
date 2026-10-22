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
    /// as on the Mac. They're as many as fit in iOS's notifications. The
    /// engine keeps the plan in place of the one before, whose appearances
    /// that came and that Lucas never touched go into the appearance log
    /// first, as snoozes, closed as they showed (#97): the next appearance
    /// waits from them. With `firstTime`, as Ficha Dev's "Bring the next
    /// appearance now" asks, the first appearance comes then instead, and
    /// the plan keeps it there.
    public func upcomingAppearances(
        _ settings: ReviewSettings,
        bringingTheFirstTo firstTime: Date? = nil
    ) throws(EngineError) -> [UpcomingAppearance] {
        let now = time.now
        // The app plans again whenever the database changes, so telling it
        // would plan forever, and the plan changes no card.
        return try writeWithoutTelling { db in
            try noteUntouchedAppearances(by: now, in: db)
            let cards = try cardsInReviews(in: db)
            let planned = try settings.plannedAppearances(
                cardIDs: cards.map(\.id), log: logEntries(in: db), lastClosing: lastClosing(in: db), from: now,
                calendar: calendar, upTo: Self.mostUpcomingAppearances)
            let upcoming = try planned.enumerated().map { number, appearance in
                UpcomingAppearance(
                    time: number == 0 ? firstTime ?? appearance.time : appearance.time,
                    cards: try panelCards(appearance.cardIDs, from: cards))
            }
            try keep(upcoming, in: db)
            return upcoming
        }
    }
}

/// Keeps `plan` as the last plan the engine handed out, in place of the one
/// before.
private func keep(_ plan: [UpcomingAppearance], in db: Database) throws {
    try db.execute(sql: "DELETE FROM plannedAppearance")
    for appearance in plan {
        try db.execute(sql: "INSERT INTO plannedAppearance (time) VALUES (?)", arguments: [appearance.time])
    }
}
