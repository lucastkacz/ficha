/// What opened the review panel, or sent the card notifications on the
/// iPhone. Each raw value is how the review log names it.
public enum Trigger: String, Sendable {
    /// Lucas opened it himself: a review now.
    case reviewNow
    /// It showed up on its own: an appearance, in the review panel or as card
    /// notifications.
    case appearance
}

extension Trigger {
    /// How far ahead the review panel looks for due cards when this opened
    /// it: an appearance brings along the cards due within the look-ahead of
    /// `settings`, whose reviews count as on time, and review now only the due
    /// ones.
    public func lookAhead(in settings: ReviewSettings) -> Duration {
        switch self {
        case .appearance: settings.lookAhead
        case .reviewNow: .zero
        }
    }
}
