import FichaCore
import Foundation

extension Engine {
    /// Gives `tag` `color`, one of Finder's seven, or takes its color away
    /// when `color` is nil. The `tag` table keeps it for the cards that get
    /// the tag later too, and deletes the tag's row once it has nothing
    /// left.
    public func setColor(_ color: TagColor?, of tag: String) throws(EngineError) {
        try setColor(color, of: [tag])
    }

    /// Gives each of `tags` `color`, or takes their colors away when it's
    /// nil, as `setColor(_:of:)` does for one, in one write.
    public func setColor(_ color: TagColor?, of tags: [String]) throws(EngineError) {
        try write { db in
            try changeOwnTags(tags, in: db) { $0.color = color }
        }
    }

    /// Gives `tag` `emoji`, or takes its emoji away when `emoji` is nil. The
    /// `tag` table deletes the tag's row once it has nothing left.
    public func setEmoji(_ emoji: Emoji?, of tag: String) throws(EngineError) {
        try write { db in
            try changeOwnTags([tag], in: db) { $0.emoji = emoji?.text }
        }
    }
}
