import Foundation

/// A card Lucas forgot often one way: he rated that way again, "Don't know",
/// in as many reviews as his settings say, in all, since its front or back
/// last changed, so the review panel offers to flag it, for it to be fixed.
/// Each way of a card that goes both ways counts apart (ADR 0016).
public struct ForgottenOften: Sendable, Equatable {
    /// How many reviews of that way he rated again since then.
    public let times: Int
    /// The way he forgot it: front first, or back first.
    public let way: Way
}

extension ReviewSettings {
    /// Whether the card whose review log is `log`, in the order it happened,
    /// is forgotten often after its last answer, the log's last entry, and
    /// how many times Lucas forgot it the way that answer went, or nil. Only
    /// the reviews of that way he rated again since `editedAt`, when its
    /// front or back last changed, count, or all of them for a card never
    /// edited. It's forgotten often when a rating of again brings them to
    /// `forgottenOftenAfter`, and again each time it brings them half of
    /// that further, rounded down and at least one, as Anki warns again
    /// about a leech.
    public func forgottenOften(after log: [ReviewLogEntry], editedAt: Date?) -> ForgottenOften? {
        guard let number = forgottenOftenAfter, let last = log.last, last.kind == .review(.again) else {
            return nil
        }
        let sinceEdited = log.filter { entry in
            entry.way == last.way && editedAt.map { entry.answeredAt >= $0 } ?? true
        }
        let times = sinceEdited.count { $0.kind == .review(.again) }
        let repeatEvery = max(1, number / 2)
        guard times >= number, (times - number).isMultiple(of: repeatEvery) else {
            return nil
        }
        return ForgottenOften(times: times, way: last.way)
    }
}
