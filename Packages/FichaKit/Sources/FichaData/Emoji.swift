import Foundation

/// The emoji the user gives a tag or a card type of their own: one character
/// the Mac draws as an emoji, a flag or a family among them, without the
/// spaces around it.
public struct Emoji: Sendable, Hashable {
    /// The emoji.
    public let text: String

    /// `text` as an emoji, without the spaces around it, or an error when it
    /// isn't one emoji, such as a word, two emoji, a letter or an empty text.
    public init(_ text: String) throws(EngineError) {
        let emoji = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard emoji.count == 1, let character = emoji.first, character.isDrawnAsEmoji else {
            throw .notOneEmoji
        }
        self.text = emoji
    }
}

extension Character {
    /// Whether the Mac draws it as an emoji: its first scalar shows as one
    /// on its own, as 🇦🇷's and 👩🏽‍🔬's do, has an emoji form that the
    /// variation selector U+FE0F asks for, as ❤️ and 1️⃣ do, or takes the skin
    /// tone that follows it, as ☝🏽 does without the selector. A letter, a
    /// digit or ❤ without the selector is text.
    fileprivate var isDrawnAsEmoji: Bool {
        let scalars = Array(unicodeScalars)
        guard let first = scalars.first else {
            return false
        }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && scalars.contains("\u{FE0F}"))
            || (first.properties.isEmojiModifierBase && scalars.dropFirst().first?.properties.isEmojiModifier == true)
    }
}
