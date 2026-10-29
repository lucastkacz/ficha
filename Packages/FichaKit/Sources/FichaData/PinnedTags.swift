import FichaCore
import Foundation
internal import GRDB

// Pinned tags (ADR 0022): the tags the user keeps in the Cards window's
// sidebar, in an order of their own. A pin is a tag's own, as its switch is,
// so it stays while no card carries the tag, and syncs as its row does; a
// rename or a move keeps it (`RenamingTags.swift`). Each pinned tag holds its
// place as a key (`PinPosition`), so that moving one rewrites its row alone.

extension Engine {
    /// The tags the user pinned, in their order, each with what it has of its
    /// own and what it takes from the tags it sits inside.
    public func pinnedTags() throws(EngineError) -> [CardTag] {
        try read { db in
            let own = try OwnTags(in: db)
            return own.pinned.map { own.tag($0.name) }
        }
    }

    /// Pins `tag` to the Cards window's sidebar at `index` among the pinned
    /// tags, or after them when it's nil, so that the pinned tags list it
    /// there; an index past them puts it last. A pinned tag moves there, the
    /// others keeping their order, and stays where it is when `index` is
    /// nil. Its row alone changes, and it syncs as the tag's other fields do.
    public func pin(_ tag: String, at index: Int? = nil) throws(EngineError) {
        try write { db in
            var own = try ownTag(tag, in: db)
            let pinned = try OwnTags(in: db).pinned
            let others = pinned.filter { $0.name != tag }
            let place = min(max(index ?? others.count, 0), others.count)
            if own.isPinned, index == nil || pinned.firstIndex(where: { $0.name == tag }) == place {
                return
            }
            // The first place after the one before it, past the tags tied
            // with that one, which two devices can leave in one place.
            let before = place > 0 ? others[place - 1].pin : nil
            let after = others[place...].lazy.compactMap(\.pin).first { after in before.map { after > $0 } ?? true }
            own.pin = PinPosition.between(before, after)
            try save(own, in: db)
        }
    }

    /// Unpins `tag` from the Cards window's sidebar. A tag that isn't pinned
    /// stays as it is.
    public func unpin(_ tag: String) throws(EngineError) {
        try write { db in
            var own = try ownTag(tag, in: db)
            guard own.isPinned else { return }
            own.pin = nil
            try save(own, in: db)
        }
    }
}
