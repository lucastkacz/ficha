import FichaCore
import Foundation
internal import GRDB

// Renaming a tag (ADR 0021), which moves it too, as its name carries the tags
// it sits inside: the Cards window's Rename… and its drops. A tag's name is
// how cards carry it and the `tag` table's key, so renaming one changes every
// card that carries it or a tag inside it, and moves their rows: an old row
// is deleted and a new one written, which sync as a tag's rows do, and each
// card records an edit to its tags, whose latest change wins (ADR 0017).

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
    /// each tag inside the renamed one. Returns the tag's new name; renaming it to its
    /// own name changes nothing. Refuses a blank name, and moving the tag
    /// inside itself or inside a tag inside it.
    @discardableResult
    public func renameTag(_ tag: String, to newName: String) throws(EngineError) -> String {
        let name = try checkedTagName(renaming: tag, to: newName)
        guard name != tag else {
            return name
        }
        try write { db in
            let existing = try tagsThatExist(apartFrom: tag, in: db)
            try moveCards(tagged: tag, to: name, in: db)
            try moveRows(of: tag, to: name, joining: existing, in: db)
        }
        return name
    }
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

/// The tags that exist apart from `tag` and the tags inside it, in `db`: each
/// that a row of the `tag` table has, each that a card carries, and each
/// that one of those sits inside, as a parent exists through the tags inside
/// it.
private func tagsThatExist(apartFrom tag: String, in db: Database) throws -> Set<String> {
    let rows = try String.fetchAll(db, sql: "SELECT name FROM tag")
    let carried = try String.fetchAll(db, sql: "SELECT tags FROM card").flatMap(tagsFromJSON)
    return TagPath.lineages(of: (rows + carried).filter { !TagPath.isTag($0, within: tag) })
}

/// Gives every card that carries `tag`, or a tag inside it, the new name
/// `name`, each tag inside it moved along, in the write `db`: a card left
/// with a tag twice carries it once, in the place of the first.
private func moveCards(tagged tag: String, to name: String, in db: Database) throws {
    for row in try Row.fetchAll(db, sql: "SELECT id, tags FROM card ORDER BY id") {
        let id: Int64 = try row.decode(forColumn: "id")
        let tags = try tagsFromJSON(try row.decode(forColumn: "tags"))
        let renamed = tags.map { TagPath.renaming($0, from: tag, to: name) ?? $0 }.uniqued()
        if renamed != tags {
            try db.execute(sql: "UPDATE card SET tags = ? WHERE id = ?", arguments: [try tagsJSON(renamed), id])
        }
    }
}

/// Moves the rows of the `tag` table of `tag` and the tags inside it to the
/// new name `name`, in the write `db`: each old row goes, and a new one comes
/// with what it had of its own, unless its new name is among `existing`, the
/// tags that existed apart from the ones that move, which then keeps what it
/// had of its own, and takes the moved tag's pin when it had none, so that a
/// merge never unpins a tag (ADR 0022). The rows that move all go first, so
/// that a row that moves onto the old name of another, as moving a tag onto
/// the tag it sits inside can, never meets it.
private func moveRows(of tag: String, to name: String, joining existing: Set<String>, in db: Database) throws {
    let moving = try String.fetchAll(db, sql: "SELECT name FROM tag").filter { TagPath.isTag($0, within: tag) }
        .map { try ownTag($0, in: db) }
    for own in moving {
        try db.execute(sql: "DELETE FROM tag WHERE name = ?", arguments: [own.name])
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
