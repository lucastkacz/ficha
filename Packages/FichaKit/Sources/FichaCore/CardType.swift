import Foundation

/// What a card holds: one of the four types Ficha comes with, a word, a
/// concept, a quote or a question, or one the user made, with a name and an
/// emoji of their choice (`GLOSSARY.md`'s Card type). The four are fixed:
/// the user can't rename, delete or hide them.
public enum CardType: Sendable, Hashable {
    /// A word.
    case word
    /// A concept.
    case concept
    /// A quote.
    case quote
    /// A question.
    case question
    /// A type the user made.
    case user(UserType)

    /// The four types Ficha comes with, in their order.
    public static let builtIn: [CardType] = [.word, .concept, .quote, .question]

    /// The type as a text file of cards and the `ficha` CLI write it: a type
    /// Ficha comes with by its raw value, which never changes, as the
    /// database names it too, and a user type by its name.
    public var writtenName: String {
        switch self {
        case .word: "word"
        case .concept: "concept"
        case .quote: "quote"
        case .question: "question"
        case .user(let type): type.name
        }
    }

    /// The raw value of a type Ficha comes with, "word", "concept", "quote"
    /// or "question", or nil for a user type.
    public var builtInName: String? {
        userType == nil ? writtenName : nil
    }

    /// The user type it is, or nil for one of the four.
    public var userType: UserType? {
        guard case .user(let type) = self else { return nil }
        return type
    }
}

extension CardType: Encodable {
    /// The type as `writtenName` writes it, as the `ficha` CLI prints a card.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(writtenName)
    }
}

/// A card type the user made (`GLOSSARY.md`'s Card type), with an ID unique
/// across devices, so that renaming it changes no card, a name, and an
/// optional emoji.
public struct UserType: Sendable, Hashable, Identifiable {
    /// Its ID unique across devices, which a card names it by.
    public let id: UUID
    /// Its name, unique among the user's types as `isSameName(_:as:)` compares
    /// them, and never a name of the four Ficha comes with.
    public let name: String
    /// Its emoji, or nil for none, when it shows a plain symbol.
    public let emoji: String?

    public init(id: UUID, name: String, emoji: String?) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }

    /// Whether `name` and `other`, two names of card types, are the same, as
    /// a type's name must be unique: trimmed, ignoring case and accents, as
    /// duplicates are compared, so “Fármaco” and “farmaco” are one.
    public static func isSameName(_ name: String, as other: String) -> Bool {
        duplicateKey(name) == duplicateKey(other)
    }
}
