import FichaCore
import Foundation
internal import GRDB

// Renaming a tag (ADR 0021), which moves it too, as its name carries the tags
// it sits inside: the Cards window's Rename… and its drops, and the `ficha`
// CLI. A tag's name is how cards carry it and the `tag` table's key, so
// renaming one changes every card that carries it or a tag inside it, and
// moves their rows: an old row is deleted and a new one written, which sync
// as a tag's rows do, and each card records an edit to its tags, whose latest
// change wins (ADR 0017). The rename is also recorded as a change to the tag,
// which reaches the cards the user's other devices hold that don't sync
// (`TagChanges.swift`), as a deletion is (`DeletingTags.swift`).

extension Engine {
    /// Renames the tag `tag` to `newName`, its levels cleaned up as a card's
    /// are (`TagPath.normalized(_:)`), and every tag inside it along with it,
    /// in one write, so the `ficha` CLI never reads a tree half renamed: each
    /// card that carries one carries the new name, and each row of the `tag`
    /// table moves to the new name with what it has of its own, its switch,
    /// color, emoji, choice to sync and pin, which keeps its place among the
    /// pinned tags. Onto a name that exists, as a tag row has it, a card
    /// carries it or a tag inside it exists, the two join, as in Anki: a card
    /// that carried both carries the name once, and the tag already there
    /// keeps exactly what it had of its own, which may be nothing, since the
    /// moved tag's row is dropped, but for its pin, which it takes from the
    /// moved tag, with its place, when it had none (ADR 0022); and so for
    /// each tag inside the renamed one. The rename reaches every card on the
    /// user's other devices, those that don't sync too, as a change to the
    /// tag. Returns the tag's new name; renaming it to its own name changes
    /// nothing. Refuses a blank name, and moving the tag inside itself or
    /// inside a tag inside it.
    @discardableResult
    public func renameTag(_ tag: String, to newName: String) throws(EngineError) -> String {
        let name = try checkedTagName(renaming: tag, to: newName)
        guard name != tag else {
            return name
        }
        try write { db in try makeTagEdit(.rename(tag, to: name), in: db) }
        return name
    }

    /// Moves `tags` inside `parent`, or to the top when it's nil, as
    /// dropping them in the Cards window's All Tags does, in one write: each
    /// is renamed `<parent>::<its last level>`, or its last level at the top,
    /// as `renameTag(_:to:)` renames it, with every tag inside it, joining a
    /// tag of that name if there's one. A tag inside another of `tags` moves
    /// along with it, and one already right inside `parent`, or at the top,
    /// stays. Refuses moving a tag inside itself, as when `parent` is one of
    /// `tags` or sits inside one, and then moves none. Returns the renames it
    /// made, in the order of `tags`.
    @discardableResult
    public func moveTags(_ tags: [String], into parent: String?) throws(EngineError) -> [TagEdit] {
        let moves = try tagMoves(of: tags, into: parent)
        try write { db in
            for move in moves {
                try makeTagEdit(move, in: db)
            }
        }
        return moves
    }
}

/// The renames that move `tags` inside `parent`, or to the top when it's nil,
/// as `Engine.moveTags(_:into:)` makes them, in the order of `tags`: none for
/// a tag inside another of them, or one there already. Refuses moving a tag
/// inside itself.
func tagMoves(of tags: [String], into parent: String?) throws(EngineError) -> [TagEdit] {
    let tags = tags.uniqued()
    if let parent, let holding = tags.first(where: { TagPath.isTag(parent, within: $0) }) {
        throw .tagInsideItself(holding)
    }
    var moves: [TagEdit] = []
    for tag in tags where !tags.contains(where: { $0 != tag && TagPath.isTag(tag, within: $0) }) {
        let level = TagPath.lastLevel(of: tag)
        let name = try checkedTagName(renaming: tag, to: parent.map { $0 + TagPath.separator + level } ?? level)
        if name != tag {
            moves.append(.rename(tag, to: name))
        }
    }
    return moves
}

/// The name the tag `tag` takes when it's renamed `newName`: `newName` with
/// its levels cleaned up as a card's tags are; or an error when it's blank,
/// or when it would put the tag inside itself or inside a tag inside it.
func checkedTagName(renaming tag: String, to newName: String) throws(EngineError) -> String {
    guard let name = TagPath.normalized(newName) else {
        throw .blankTagName
    }
    guard name == tag || !TagPath.isTag(name, within: tag) else {
        throw .tagInsideItself(tag)
    }
    return name
}

/// Makes `edit`, which the user made on this device, in the write `db`: the
/// tag's rows and its cards change (`editRows`, `editCards`), each card
/// recording an edit to its tags, and the edit is recorded as a change to
/// the tag, which reaches the user's other devices (`TagChanges.swift`).
func makeTagEdit(_ edit: TagEdit, in db: Database) throws {
    try editRows(edit, in: db)
    try editCards(edit, in: db)
    try recordTagChange(edit, in: db)
}

/// Makes `edit` to the rows of the `tag` table, in the write `db`, before
/// the cards carry it: the rows of the tag and the tags inside it move to
/// their new names, joining the tags that exist apart from them
/// (`moveRows`), or go.
func editRows(_ edit: TagEdit, in db: Database) throws {
    switch edit {
    case .rename(let tag, let name):
        try moveRows(of: tag, to: name, joining: tagsThatExist(apartFrom: tag, in: db), in: db)
    case .deletion:
        for name in try String.fetchAll(db, sql: "SELECT name FROM tag") where edit.changes(name) {
            try deleteRow(ofTag: name, in: db)
        }
    }
}

/// Deletes the row of the `tag` table of the tag `name`, with everything it
/// had of its own, in the write `db`.
func deleteRow(ofTag name: String, in db: Database) throws {
    try db.execute(sql: "DELETE FROM tag WHERE name = ?", arguments: [name])
}

/// The tags that exist apart from `tag` and the tags inside it, in `db`: each
/// that a row of the `tag` table has, each that a card carries, and each
/// that one of those sits inside, as a parent exists through the tags inside
/// it.
func tagsThatExist(apartFrom tag: String, in db: Database) throws -> Set<String> {
    let rows = try String.fetchAll(db, sql: "SELECT name FROM tag")
    let carried = try String.fetchAll(db, sql: "SELECT tags FROM card").flatMap(tagsFromJSON)
    return TagPath.lineages(of: (rows + carried).filter { !TagPath.isTag($0, within: tag) })
}

/// A card whose tags a change to a tag edited: its id, and the row it syncs
/// as.
struct EditedCard {
    let id: Int64
    let row: SyncedRow
}

/// Gives every card that carries the tag `edit` changes, or a tag inside it,
/// its tags after `edit`, in the write `db`, of those among `cards`, or of
/// every card when it's nil; and returns those it changed.
@discardableResult
func editCards(_ edit: TagEdit, among cards: Set<Int64>? = nil, in db: Database) throws -> [EditedCard] {
    var edited: [EditedCard] = []
    for row in try Row.fetchAll(db, sql: "SELECT id, uuid, tags FROM card ORDER BY id") {
        let id: Int64 = try row.decode(forColumn: "id")
        guard cards?.contains(id) ?? true else {
            continue
        }
        let tags = try tagsFromJSON(try row.decode(forColumn: "tags"))
        let after = edit.tags(after: tags)
        guard after != tags else {
            continue
        }
        try db.execute(sql: "UPDATE card SET tags = ? WHERE id = ?", arguments: [try tagsJSON(after), id])
        edited.append(
            EditedCard(
                id: id,
                row: try SyncedRow(
                    recordType: SyncedRow.RecordType.card.rawValue, recordName: row.decode(forColumn: "uuid"))))
    }
    return edited
}

/// Moves the rows of the `tag` table of `tag` and the tags inside it to the
/// new name `name`, in the write `db`: each old row goes, and a new one comes
/// with what it had of its own, unless its new name is among `existing`, the
/// tags that existed apart from the ones that move, which then keeps what it
/// had of its own, and takes the moved tag's pin when it had none, so that a
/// merge never unpins a tag (ADR 0022). The rows that move all go first, so
/// that a row that moves onto the old name of another, as moving a tag onto
/// the tag it sits inside can, never meets it.
func moveRows(of tag: String, to name: String, joining existing: Set<String>, in db: Database) throws {
    let moving = try String.fetchAll(db, sql: "SELECT name FROM tag").filter { TagPath.isTag($0, within: tag) }
        .map { try ownTag($0, in: db) }
    for own in moving {
        try deleteRow(ofTag: own.name, in: db)
    }
    for own in moving {
        guard let newName = TagPath.renaming(own.name, from: tag, to: name) else {
            continue
        }
        guard existing.contains(newName) else {
            try save(own.named(newName), in: db)
            continue
        }
        var there = try ownTag(newName, in: db)
        if !there.isPinned, let pin = own.pin {
            there.pin = pin
            try save(there, in: db)
        }
    }
}
