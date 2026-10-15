/// How well Lucas says he knew a card in a review. Each raw value is how the
/// review log names it.
public enum Rating: String, Sendable {
    /// "No lo sé": the card goes back to the first step.
    case again
    /// "Más o menos": the card stays on its step.
    case hard
    /// "Lo sé": the card moves up one step.
    case good
}
