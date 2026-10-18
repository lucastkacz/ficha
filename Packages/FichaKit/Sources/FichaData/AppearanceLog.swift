import FichaCore
import Foundation
internal import GRDB

/// One entry in the appearance log: an appearance, or a review now that
/// brought cards, from when the review panel showed to when it closed, and
/// how it closed; or an appearance a suppression held back, once, when it was
/// held back.
public struct AppearanceLogEntry: Sendable, Equatable {
    /// How the review panel closed, or what held the appearance back.
    public enum Outcome: Sendable, Equatable {
        /// No card it brought was left: Lucas answered, flagged or buried
        /// each one, and maybe some that "See more" added.
        case finished
        /// Lucas closed it with cards left, which stay as they were: a
        /// snooze.
        case snoozed
        /// It closed on its own with cards left, untouched for a while or as
        /// the Mac or its screens went to sleep: it counts as a snooze.
        case autoClosed
        /// It never showed: this suppression held it back. It comes once the
        /// suppression is over, as another entry.
        case heldBack(Suppression)
    }

    public let trigger: Trigger
    /// When the review panel showed, or, held back, when it was held back.
    public let shownAt: Date
    /// When the review panel closed, or, held back, when it was held back.
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
        guard
            let outcome = Outcome(
                outcome: try row.decode(forColumn: "outcome"), heldBackBy: try row.decode(forColumn: "heldBackBy"))
        else {
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

extension AppearanceLogEntry.Outcome {
    /// The outcome that the `appearanceLog` table's `outcome` and
    /// `heldBackBy` columns name, or nil when this version of Ficha doesn't
    /// know it.
    fileprivate init?(outcome: String, heldBackBy: String?) {
        switch (outcome, heldBackBy) {
        case ("finished", nil): self = .finished
        case ("snoozed", nil): self = .snoozed
        case ("autoClosed", nil): self = .autoClosed
        case ("heldBack", let suppression?):
            guard let suppression = Suppression(rawValue: suppression) else {
                return nil
            }
            self = .heldBack(suppression)
        default: return nil
        }
    }

    /// The values of the `appearanceLog` table's `outcome` and `heldBackBy`
    /// columns that name this outcome.
    var columns: (outcome: String, heldBackBy: String?) {
        switch self {
        case .finished: ("finished", nil)
        case .snoozed: ("snoozed", nil)
        case .autoClosed: ("autoClosed", nil)
        case .heldBack(let suppression): ("heldBack", suppression.rawValue)
        }
    }
}
