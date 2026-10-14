import FichaCore
import Testing

/// A card for a test to approve a capture into: it always has a front and a
/// back, and no tags or source unless the test gives them.
func card(
    _ type: CardType,
    front: String,
    back: String,
    tags: [String] = [],
    source: String? = nil
) throws -> CardContent {
    try #require(CardContent(type: type, front: front, back: back, tags: tags, source: source))
}
