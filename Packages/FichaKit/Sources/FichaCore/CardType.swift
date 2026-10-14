/// What a card holds. Each raw value is how the database and the `ficha` CLI
/// name the type.
public enum CardType: String, Sendable, Codable {
    /// A word (_palabra_).
    case word
    /// A concept (_concepto_).
    case concept
    /// A quote (_frase_).
    case quote
    /// A question (_pregunta_).
    case question
}
