/// What opened the review panel. Each raw value is how the review log names
/// it.
public enum Trigger: String, Sendable {
    /// Lucas opened it himself: a review now.
    case reviewNow
    /// It showed up on its own: an appearance.
    case appearance
}
