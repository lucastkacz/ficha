import FichaCore
import Foundation
internal import GRDB

/// One entry in the appearance log: an appearance, or a review now that
/// brought cards, from when the review panel showed to when it closed, and
/// how it closed; an appearance on the iPhone, from its first card
/// notification to the last card Lucas went through, or to when he swiped
/// one away, or only as it showed, when he never touched them; or an
/// appearance a suppression held back, once, when it was held back.
public struct AppearanceLogEntry: Sendable, Equatable {
    /// How the review panel closed, how far Lucas went through an
    /// appearance's card notifications on the iPhone, or what held the
    /// appearance back.
    public enum Outcome: Sendable, Equatable {
        /// No card it brought was left: Lucas answered, flagged or buried
        /// each one, and maybe some that "See more" added.
        case finished
        /// Lucas closed it with cards left, which stay as they were: a
        /// snooze. An appearance on the iPhone is one until he goes through
        /// its last card, and also when he swipes one of its card
        /// notifications away or never touches them.
        case snoozed
        /// It closed on its own with cards left, untouched for a while or as
        /// the Mac or its screens went to sleep: it counts as a snooze.
        case autoClosed
        /// It never showed: this suppression held it back. It comes once the
        /// suppression is over, as another entry.
        case heldBack(Suppression)
    }

    public let trigger: Trigger
    /// When the review panel showed, or the first card notification on the
    /// iPhone, or, held back, when the hold started.
    public let shownAt: Date
    /// When the review panel closed, or, on the iPhone, when Lucas last went
    /// through one of its cards or swiped one away, or when it showed, if he
    /// never touched them, or, held back, when the hold ended: when the
    /// panel showed, or the appearance couldn't come any more. A hold that's
    /// still on has its shownAt here.
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

/// How the `appearanceLog` table's `outcome` column names each outcome.
enum OutcomeName: String {
    case finished, snoozed, autoClosed, heldBack
}

extension AppearanceLogEntry.Outcome {
    /// The outcome that the `appearanceLog` table's `outcome` and
    /// `heldBackBy` columns name, or nil when this version of Ficha doesn't
    /// know it.
    fileprivate init?(outcome: String, heldBackBy: String?) {
        switch (OutcomeName(rawValue: outcome), heldBackBy.map(Suppression.init(rawValue:))) {
        case (.finished, nil): self = .finished
        case (.snoozed, nil): self = .snoozed
        case (.autoClosed, nil): self = .autoClosed
        case (.heldBack, let suppression??): self = .heldBack(suppression)
        default: return nil
        }
    }

    /// The values of the `appearanceLog` table's `outcome` and `heldBackBy`
    /// columns that name this outcome.
    var columns: (outcome: String, heldBackBy: String?) {
        switch self {
        case .finished: (OutcomeName.finished.rawValue, nil)
        case .snoozed: (OutcomeName.snoozed.rawValue, nil)
        case .autoClosed: (OutcomeName.autoClosed.rawValue, nil)
        case .heldBack(let suppression): (OutcomeName.heldBack.rawValue, suppression.rawValue)
        }
    }
}
