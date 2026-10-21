import Foundation

/// What a card holds, cleaned up the same way wherever it comes from: its
/// type, its front and back, and its tags and source, without surrounding
/// spaces or line breaks. A tag or source left blank is no tag or source.
public struct CardContent: Sendable {
    public let type: CardType
    public let front: String
    public let back: String
    public let tags: [String]
    public let source: String?

    /// What these fields make, or nil when the front or the back is blank,
    /// since a card needs both.
    public init?(type: CardType, front: String, back: String, tags: [String], source: String?) {
        guard let front = nonBlank(front), let back = nonBlank(back) else {
            return nil
        }
        self.type = type
        self.front = front
        self.back = back
        self.tags = tags.compactMap(nonBlank)
        self.source = nonBlank(source)
    }

    /// Whether `side`, a front or a back, is blank by the rule `init` follows,
    /// for fields to say which side keeps them from making a card.
    public static func isBlank(_ side: String) -> Bool {
        nonBlank(side) == nil
    }
}
