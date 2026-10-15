import Foundation

/// Where a card stands in Lucas's reviews: new until its first view, and on a
/// step of the ladder from then on.
public enum CardStanding: Sendable, Equatable {
    /// It hasn't had its first view yet.
    case new
    /// It's on this step of the ladder, counted from 0, the first step, and
    /// it's due once `due` comes.
    case onLadder(step: Int, due: Date)
}

extension CardStanding {
    /// Whether the card is due at `now`: on the ladder, with its wait over.
    public func isDue(at now: Date) -> Bool {
        guard case .onLadder(_, let due) = self else {
            return false
        }
        return due <= now
    }
}
