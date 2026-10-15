/// How well Lucas says he knew a card in a review. Each raw value is how the
/// review log names it.
public enum Rating: String, Sendable {
    /// "Don't know": the card goes back to the first step.
    case again
    /// "Sort of": the card stays on its step.
    case hard
    /// "Know it": the card moves up one step.
    case good
}
