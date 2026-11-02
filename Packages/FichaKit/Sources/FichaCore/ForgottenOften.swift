import Foundation

/// A card Lucas forgot often one way: that way lapsed, rated again while it
/// was graduated, as many times as his settings say, in all, since its front
/// or back last changed, as Anki counts a leech's lapses, so the review panel
/// offers to flag it, for it to be fixed. Each way of a card that goes both
/// ways counts apart (ADR 0016).
public struct ForgottenOften: Sendable, Equatable {
    /// How many times that way lapsed since then.
    public let times: Int
    /// The way he forgot it: front first, or back first.
    public let way: Way
}

extension ReviewSettings {
    /// Whether the card whose review log is `log`, its last entry the answer
    /// Lucas just gave, is forgotten often after it, and how many times he
    /// forgot it the way that answer went, or nil. Only that way's lapses
    /// since `editedAt`, when its front or back last changed, count, or all
    /// of them for a card never edited, as the scheduler tells them from its
    /// log: agains of the way while it was graduated, and not a new way's
    /// agains in its learning steps. It's forgotten often when a lapse brings
    /// them to `forgottenOftenAfter`, and again each time one brings them
    /// half of that further, rounded down and at least one, as Anki warns
    /// again about a leech.
    public func forgottenOften(after log: [ReviewLogEntry], editedAt: Date?) throws(SchedulingError)
        -> ForgottenOften?
    {
        guard let number = forgottenOftenAfter, let last = log.last, last.kind == .review(.again) else {
            return nil
        }
        let lapses = try scheduler.lapses(after: log.filter { $0.way == last.way })
        guard lapses.contains(last) else {
            return nil
        }
        let times = lapses.count { lapse in editedAt.map { lapse.answeredAt >= $0 } ?? true }
        let repeatEvery = max(1, number / 2)
        guard times >= number, (times - number).isMultiple(of: repeatEvery) else {
            return nil
        }
        return ForgottenOften(times: times, way: last.way)
    }
}
