import Foundation

/// What a card holds, and the one check of what a valid card is, wherever it
/// comes from: approving a capture or an expansion, fixing or editing a card,
/// creating one, and the sample cards. A new way in, such as a form or an
/// import, builds one too, and never writes a card's content around it, so
/// that no way in lets in a card another refuses. It cleans the content up
/// the same way each time: its type, if it has one, its front and back, and
/// its tags and source, without surrounding spaces or line breaks. A tag or
/// source left blank is no tag or source.
public struct CardContent: Sendable, Equatable {
    /// Its type, or nil when it has none.
    public let type: CardType?
    public let front: String
    public let back: String
    public let tags: [String]
    public let source: String?

    /// What these fields make, or nil when the front or the back is blank,
    /// since a card needs both. A nil type is no type.
    public init?(type: CardType?, front: String, back: String, tags: [String], source: String?) {
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
