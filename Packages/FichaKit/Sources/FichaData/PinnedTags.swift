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

    /// Pins `tag` to the Cards window's sidebar, as `pin(_:at:)` pins
    /// several: at `index` among the other pinned tags, moving there when
    /// it's pinned, or after them when `index` is nil, where a pinned tag
    /// stays where it is.
    public func pin(_ tag: String, at index: Int? = nil) throws(EngineError) {
        try pin([tag], at: index)
    }

    /// Pins `tags` to the Cards window's sidebar, next to each other in the
    /// order they're given, the first at `index` among the other pinned
    /// tags, whose order stays; an index past them puts them last. Those
    /// already pinned move there. When `index` is nil, those that aren't
    /// pinned go after the pinned tags, and the pinned ones stay where they
    /// are. In one write, where each tag that moves gets a place between its
    /// new neighbors', and its row alone changes, syncing as the tag's other
    /// fields do.
    public func pin(_ tags: [String], at index: Int? = nil) throws(EngineError) {
        try write { db in
            let pinned = try OwnTags(in: db).pinned
            if let index {
                try place(tags, at: index, among: pinned, in: db)
            } else {
                let unpinned = tags.filter { tag in !pinned.contains { $0.name == tag } }
                try place(unpinned, at: pinned.count, among: pinned, in: db)
            }
        }
    }

    /// Moves the pinned tags `tags` among the pinned tags, as `pin(_:at:)`
    /// moves them to `index`, in one write. Refuses a tag that isn't pinned,
    /// as when another device unpinned it meanwhile, and moves none of them.
    public func movePinnedTags(_ tags: [String], to index: Int) throws(EngineError) {
        try write { db in
            let pinned = try OwnTags(in: db).pinned
            if let unpinned = tags.first(where: { tag in !pinned.contains { $0.name == tag } }) {
                throw EngineError.tagNotPinned(unpinned)
            }
            try place(tags, at: index, among: pinned, in: db)
        }
    }

    /// Unpins `tag` from the Cards window's sidebar. A tag that isn't pinned
    /// stays as it is.
    public func unpin(_ tag: String) throws(EngineError) {
        try unpin([tag])
    }

    /// Unpins each of `tags`, as `unpin(_:)` does one, in one write.
    public func unpin(_ tags: [String]) throws(EngineError) {
        try write { db in
            try changeOwnTags(tags, in: db) { $0.pin = nil }
        }
    }
}

/// Puts `tags`, each once, among `pinned`, the pinned tags in their order,
/// next to each other in their order, the first at `index` among the pinned
/// tags that aren't in `tags`, or last when `index` is past them, in the
/// write `db`. Each tag of `tags` gets a place after the one before it, and
/// before the first of the others after them that's after that one, past
/// the tags two devices left in one place; when the order stays as it is,
/// nothing changes.
private func place(_ tags: [String], at index: Int, among pinned: [CardTag], in db: Database) throws {
    let moving = tags.uniqued()
    let others = pinned.filter { !moving.contains($0.name) }
    let start = min(max(index, 0), others.count)
    let order = others[..<start].map(\.name) + moving + others[start...].map(\.name)
    guard order != pinned.map(\.name) else {
        return
    }
    var before = start > 0 ? others[start - 1].pin : nil
    try changeOwnTags(moving, in: db) { own in
        let after = others[start...].lazy.compactMap(\.pin).first { pin in
            guard let before else { return true }
            return pin > before
        }
        own.pin = PinPosition.between(before, after)
        before = own.pin
    }
}
