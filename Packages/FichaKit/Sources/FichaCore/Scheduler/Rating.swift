/// How well Lucas says he knew a card in a review. Each raw value is how the
/// review log names it.
public enum Rating: String, Sendable {
    /// He didn't know it: the card goes back to the first step.
    case again
    /// He sort of knew it: the card stays on its step.
    case hard
    /// He knew it: the card moves up one step.
    case good
}
