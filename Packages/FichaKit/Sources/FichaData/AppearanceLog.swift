import FichaCore
import Foundation
internal import GRDB

/// One entry in the appearance log: an appearance, or a review now that
/// brought cards, from when the review panel showed to when it closed, and
/// how it closed.
public struct AppearanceLogEntry: Sendable, Equatable {
    /// How the review panel closed. Each raw value is how the appearance log
    /// names it.
    public enum Outcome: String, Sendable {
        /// No card it brought was left: Lucas answered, flagged or buried
        /// each one, and maybe some that "See more" added.
        case finished
        /// Lucas closed it with cards left, which stay as they were: a
        /// snooze.
        case snoozed
        /// It closed on its own with cards left, untouched for a while or as
        /// the Mac or its screens went to sleep: it counts as a snooze.
        case autoClosed
    }

    public let trigger: Trigger
    public let shownAt: Date
    public let closedAt: Date
    public let outcome: Outcome

    public init(trigger: Trigger, shownAt: Date, closedAt: Date, outcome: Outcome) {
        self.trigger = trigger
        self.shownAt = shownAt
        self.closedAt = closedAt
        self.outcome = outcome
    }
}

extension AppearanceLogEntry {
    /// An entry read from a row of the `appearanceLog` table.
    init(row: Row) throws {
        let id: Int64 = try row.decode(forColumn: "id")
        guard let trigger = Trigger(rawValue: try row.decode(forColumn: "trigger")) else {
            throw unreadable("Appearance log entry \(id) has an unknown trigger")
        }
        guard let outcome = Outcome(rawValue: try row.decode(forColumn: "outcome")) else {
            throw unreadable("Appearance log entry \(id) has an unknown outcome")
        }
        self.init(
            trigger: trigger,
            shownAt: try row.decode(forColumn: "shownAt"),
            closedAt: try row.decode(forColumn: "closedAt"),
            outcome: outcome
        )
    }
}
