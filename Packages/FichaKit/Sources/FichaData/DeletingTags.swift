import FichaCore
import Foundation
internal import GRDB

// Deleting tags (ADR 0022): a tag deleted, with every tag inside it, comes
// off every card that carries it, on every device, those that don't sync
// included, as a change to the tag (`TagChanges.swift`), and its rows go; no
// card is deleted. Each card records the edit to its tags (ADR 0017), and
// under selective sync a card left with no chosen tag stops syncing as when
// the user unticks one (ADR 0020). Clear Unused Tags deletes the tags no card
// carries, which stay listed only for something of their own.

/// What deleting some tags does on this device, as Delete…'s question says it
/// before, and the `ficha` CLI prints it after, leaving out
/// `cardsThatStopSyncing` when it's nil.
public struct TagDeletion: Sendable, Equatable, Encodable {
    /// The tags deleted, each once, in the order given.
    public let tags: [String]
    /// The tags inside them that go with them, in the order a tree lists
    /// them, but those among `tags`.
    public let tagsInside: [String]
    /// How many cards carry them, or a tag inside them, buried ones too, each
    /// of which loses them.
    public let cards: Int
    /// How many of those cards come back to the user's reviews: set aside by
    /// the tags, or by a tag they sit inside, and not after.
    public let cardsBackInReviews: Int
    /// How many of those cards stop syncing, left with no chosen tag, while
    /// sync is on and only the cards with a chosen tag sync; nil otherwise.
    public let cardsThatStopSyncing: Int?
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
    /// their pins, switches, colors, emoji and choices to sync. Each deletion
    /// reaches the cards the user's other devices hold, those that don't sync
    /// too, as a change to the tag. Returns what it did.
    @discardableResult
    public func deleteTags(_ tags: [String]) throws(EngineError) -> TagDeletion {
        try write { db in
            let deletion = try TagDeletion(of: tags, in: db)
            for tag in deletion.tags
            where !deletion.tags.contains(where: { $0 != tag && TagPath.isTag(tag, within: $0) }) {
                try makeTagEdit(.deletion(tag), in: db)
            }
            return deletion
        }
    }

    /// The tags Clear Unused Tags deletes, in the order a tree lists them:
    /// each with a row of its own that no card carries, buried ones
    /// included, nor a tag inside it. While sync is on and only the cards
    /// with a chosen tag sync, only the tags chosen to sync and those inside
    /// them, whose every card the device holds: another device may keep
    /// cards with a tag that doesn't sync.
    public func unusedTags() throws(EngineError) -> [String] {
        try read(tagsToClear(in:))
    }

    /// Deletes the tags Clear Unused Tags deletes (`unusedTags()`), in one
    /// write, and returns them. No card here carries them, so only their rows
    /// go, which sync as a tag's do: a card on another device that carries
    /// one, which doesn't sync, keeps it, as a tag with nothing of its own.
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
        let setAsideAfter = Set(remaining(own.tags(switchedOn: .setAside).map(\.name)))
        let whatSyncs = try WhatSyncs(in: db)
        let whatSyncsAfter = whatSyncs.choosing(Set(remaining(Array(whatSyncs.chosenTags))))
        let measuresSync = try isSyncOn(in: db) && whatSyncs.onlyChosenTags
        let cards = try allCards(in: db).filter { remaining($0.tags) != $0.tags }
        let names = TagPath.lineages(of: try allCards(in: db).flatMap(\.tags) + own.names)
        self.tags = tags
        tagsInside = TagPath.sortedAsTree(
            names.filter { name in !tags.contains(name) && edits.contains { $0.changes(name) } })
        self.cards = cards.count
        cardsBackInReviews =
            cards.filter { card in
                guard case .setAside = card.standing else { return false }
                let after = CardStanding(
                    flag: card.flag, buriedAt: card.buriedAt,
                    setAsideBy: CardStanding.setAsideTags(of: remaining(card.tags), among: setAsideAfter))
                return after == .inReviews
            }
            .count
        cardsThatStopSyncing =
            measuresSync
            ? cards.filter {
                whatSyncs.cardSyncs(tagged: $0.tags) && !whatSyncsAfter.cardSyncs(tagged: remaining($0.tags))
            }
            .count : nil
    }
}

/// The tags Clear Unused Tags deletes in `db` now, as `Engine.unusedTags()`
/// says.
private func tagsToClear(in db: Database) throws -> [String] {
    let carried = TagPath.lineages(of: try allCards(in: db).flatMap(\.tags))
    let whatSyncs = try WhatSyncs(in: db)
    let considersChosenOnly = try isSyncOn(in: db) && whatSyncs.onlyChosenTags
    let unused = try OwnTags(in: db).names.filter { name in
        !carried.contains(name)
            && (!considersChosenOnly || !whatSyncs.chosenTags.isDisjoint(with: TagPath.lineage(of: name)))
    }
    return TagPath.sortedAsTree(unused)
}
