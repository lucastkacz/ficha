/// What a card holds. Each raw value is how the database and the `ficha` CLI
/// name the type.
public enum CardType: String, Sendable, Codable, CaseIterable {
    /// A word.
    case word
    /// A concept.
    case concept
    /// A quote.
    case quote
    /// A question.
    case question
}
