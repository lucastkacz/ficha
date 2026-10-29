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
    /// color, emoji and choice to sync. Onto a name that has a row already,
    /// the two join: a card that carried both carries the name once, and the
    /// row already there stays as it was, as in Anki. Returns the tag's new
    /// name; renaming it to its own name changes nothing. Refuses a blank
    /// name, and moving the tag inside itself or inside a tag inside it.
    @discardableResult
    public func renameTag(_ tag: String, to newName: String) throws(EngineError) -> String {
        let name = try checkedName(renaming: tag, to: newName)
        guard name != tag else {
            return name
        }
        try write { db in
            try FichaData.renameTag(tag, to: name, onCardsIn: db)
            try FichaData.renameTag(tag, to: name, inTagTableOf: db)
        }
        return name
    }
}

/// The name the tag `tag` takes when it's renamed `newName`: `newName` with
/// its levels cleaned up as a card's tags are; or an error when it's blank,
/// or when it would put the tag inside itself or inside a tag inside it.
func checkedName(renaming tag: String, to newName: String) throws(EngineError) -> String {
    guard let name = TagPath.normalized(newName) else {
        throw .blankTagName
    }
    guard name == tag || !TagPath.isWithin(name, tag) else {
        throw .tagInsideItself(tag)
    }
    return name
}

/// Gives every card that carries `tag`, or a tag inside it, the new name
/// `name`, each tag inside it moved along, in the write `db`: a card left
/// with a tag twice carries it once, in the place of the first.
private func renameTag(_ tag: String, to name: String, onCardsIn db: Database) throws {
    for row in try Row.fetchAll(db, sql: "SELECT id, tags FROM card ORDER BY id") {
        let id: Int64 = try row.decode(forColumn: "id")
        let column: String = try row.decode(forColumn: "tags")
        let tags = try JSONDecoder().decode([String].self, from: Data(column.utf8))
        let renamed = tags.map { TagPath.renaming($0, from: tag, to: name) ?? $0 }.uniqued()
        if renamed != tags {
            try db.execute(sql: "UPDATE card SET tags = ? WHERE id = ?", arguments: [try tagsJSON(renamed), id])
        }
    }
}

/// Moves the rows of the `tag` table of `tag` and the tags inside it to the
/// new name `name`, in the write `db`: each old row goes, and a new one comes
/// with what it had of its own, unless a row that stays already has its new
/// name, which then stays as it was. The rows that move all go first, so that
/// a row that moves onto the old name of another, as moving a tag onto the
/// tag it sits inside can, never takes it for one that stays.
private func renameTag(_ tag: String, to name: String, inTagTableOf db: Database) throws {
    let names = try String.fetchAll(db, sql: "SELECT name FROM tag")
    let moving = try names.filter { TagPath.isWithin($0, tag) }.map { try ownTag($0, in: db) }
    let staying = Set(names.filter { !TagPath.isWithin($0, tag) })
    for own in moving {
        try db.execute(sql: "DELETE FROM tag WHERE name = ?", arguments: [own.name])
    }
    for own in moving {
        guard let newName = TagPath.renaming(own.name, from: tag, to: name), !staying.contains(newName) else {
            continue
        }
        try save(
            CardTag(
                name: newName, switchedOn: own.switchedOn, color: own.color, emoji: own.emoji,
                chosenToSync: own.chosenToSync),
            in: db)
    }
}
