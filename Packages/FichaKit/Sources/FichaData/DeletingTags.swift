import FichaCore
import Foundation
internal import GRDB

// Deleting tags (ADR 0022): a tag deleted, with every tag inside it, comes
// off every card that carries it, on every device, those that don't sync
// included, as a change to the tag (`TagChanges.swift`), and its rows go; no
// card is deleted. Each card records the edit to its tags (ADR 0017), which
// changes neither the user's reviews nor what syncs, since decks decide both
// (ADR 0024). Clear Unused Tags deletes the tags no card here carries, which
// stay listed only for something of their own.

/// What deleting some tags does on this device, as Delete…'s question says it
/// before, and the `ficha` CLI prints it after.
public struct TagDeletion: Sendable, Equatable, Encodable {
    /// The tags deleted, each once, in the order given.
    public let tags: [String]
    /// The tags inside them that go with them, in the order a tree lists
    /// them, but those among `tags`.
    public let tagsInside: [String]
    /// How many cards carry them, or a tag inside them, buried ones too, each
    /// of which loses them.
    public let cards: Int
}

extension Engine {
    /// What deleting `tags` would do on this device now, as Delete… asks
    /// before it deletes them.
    public func deletion(of tags: [String]) throws(EngineError) -> TagDeletion {
        try read { db in try TagDeletion(of: tags, in: db) }
    }

    /// Deletes `tags`, each with every tag inside it, in one write: every
    /// card that carries one loses it, and records the edit to its tags,
    /// while every card stays, and their rows of the `tag` table go, with
    /// their pins, colors, emoji and choices to sync. Each deletion
    /// reaches the cards the user's other devices hold, those that don't sync
    /// too, as a change to the tag. Returns what it did.
    @discardableResult
    public func deleteTags(_ tags: [String]) throws(EngineError) -> TagDeletion {
        try write { db in
            let deletion = try TagDeletion(of: tags, in: db)
            try makeTagEdits(
                deletion.tags.filter { tag in
                    !deletion.tags.contains { $0 != tag && TagPath.isTag(tag, within: $0) }
                }
                .map(TagEdit.deletion), in: db)
            return deletion
        }
    }

    /// The tags Clear Unused Tags deletes, in the order a tree lists them:
    /// each with a row of its own that no card on this device carries,
    /// buried ones included, nor a tag inside it, whatever syncs.
    public func unusedTags() throws(EngineError) -> [String] {
        try read(tagsToClear(in:))
    }

    /// Deletes the tags Clear Unused Tags deletes (`unusedTags()`), in one
    /// write, and returns them. No card here carries them, so only their rows
    /// go, their pins, colors and emoji, which sync as a tag's do, and no
    /// change to the tags reaches another device's cards: under selective
    /// sync, a card there that carries one, which doesn't sync, keeps it, as
    /// a tag with nothing of its own.
    @discardableResult
    public func clearUnusedTags() throws(EngineError) -> [String] {
        try write { db in
            let unused = try tagsToClear(in: db)
            for tag in unused {
                try deleteRow(ofTag: tag, in: db)
            }
            return unused
        }
    }
}

extension TagDeletion {
    /// What deleting `tags` does in `db` now.
    fileprivate init(of tags: [String], in db: Database) throws {
        let tags = tags.uniqued()
        let edits = tags.map(TagEdit.deletion)
        /// `tags` after the deletions.
        func remaining(_ tags: [String]) -> [String] {
            edits.reduce(tags) { $1.tags(after: $0) }
        }
        let own = try OwnTags(in: db)
        let everyCard = try allCards(in: db)
        self.tags = tags
        tagsInside = own.everyTagName(carriedBy: everyCard).filter { name in
            !tags.contains(name) && edits.contains { $0.changes(name) }
        }
        cards = everyCard.count { remaining($0.tags) != $0.tags }
    }
}

/// The tags Clear Unused Tags deletes in `db` now, as `Engine.unusedTags()`
/// says.
private func tagsToClear(in db: Database) throws -> [String] {
    let carried = TagPath.lineages(of: try allCards(in: db).flatMap(\.tags))
    return TagPath.sortedAsTree(try OwnTags(in: db).names.filter { !carried.contains($0) })
}
