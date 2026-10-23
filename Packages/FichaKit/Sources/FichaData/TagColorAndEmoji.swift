import FichaCore
import Foundation

extension Engine {
    /// Gives `tag` `color`, one of Finder's seven, or takes its color away
    /// when `color` is nil. The `tag` table keeps it for the cards that get
    /// the tag later too, and deletes the tag's row once it has nothing
    /// left.
    public func setColor(_ color: TagColor?, of tag: String) throws(EngineError) {
        try write { db in
            var own = try ownTag(tag, in: db)
            own.color = color
            try save(own, in: db)
        }
    }

    /// Gives `tag` `emoji`, without the spaces around it, or takes its emoji
    /// away when `emoji` is nil. Refuses what isn't one emoji, such as a
    /// word, two emoji or a letter. The `tag` table deletes the tag's row
    /// once it has nothing left.
    public func setEmoji(_ emoji: String?, of tag: String) throws(EngineError) {
        let emoji = try emoji.map { emoji throws(EngineError) in try tagEmoji(emoji) }
        try write { db in
            var own = try ownTag(tag, in: db)
            own.emoji = emoji
            try save(own, in: db)
        }
    }
}

/// `text` as a tag's emoji, without the spaces around it: one character the
/// Mac draws as an emoji, a flag or a family among them. Anything else, an
/// empty text too, is refused.
func tagEmoji(_ text: String) throws(EngineError) -> String {
    let emoji = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard emoji.count == 1, let character = emoji.first, character.isDrawnAsEmoji else {
        throw .notOneEmoji
    }
    return emoji
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
