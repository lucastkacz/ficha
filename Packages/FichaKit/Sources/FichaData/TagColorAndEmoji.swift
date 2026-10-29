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

    /// Gives `tag` `emoji`, or takes its emoji away when `emoji` is nil. The
    /// `tag` table deletes the tag's row once it has nothing left.
    public func setEmoji(_ emoji: Emoji?, of tag: String) throws(EngineError) {
        try write { db in
            var own = try ownTag(tag, in: db)
            own.emoji = emoji?.text
            try save(own, in: db)
        }
    }
}
