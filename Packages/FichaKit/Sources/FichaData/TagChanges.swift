import FichaCore
import Foundation
internal import GRDB

// A rename or a deletion of a tag reaches every card on every device, those
// that don't sync included (ADR 0022): the device that makes it records it as
// a change to the tag, a row of the `tagChange` table (`Schema`'s "v30
// changes to tags"), which syncs as a record of its own whatever selective
// sync chooses, as a tag's row does, and which every device that hears of it
// applies once, in the write that takes it from iCloud, to the cards it holds
// then and to the tag's rows. A device keeps the row of each change it made
// or heard of, which says it applied it: a record whose row it holds is never
// applied again. Changes never leave iCloud, as the review log's entries
// don't, so a device that comes back after any time still gets each. A
// restore's copy brings the changes it held, and a device that takes its
// cards drops its own with every row that syncs (`SyncedRestore.swift`), so
// that a change the restore undid is never sent again.
//
// A device that hears of a change applies it as a change of its own made
// when the change was, which syncs as such: the cards that don't sync, which
// only it holds, whatever their tags last did, and a card that syncs only
// when its tags haven't changed since the change was made, here or as another
// device left them, so that a card the old name came back to afterwards, as
// ADR 0021 says of a device offline meanwhile, keeps it, and no device
// applies the change to such a card as it first syncs. Its tags record the
// edit then, a later time they had here kept, and so does each of the tag's
// rows that moves or goes, as long as none of those rows changed since the
// change was made. The changes it holds that were made after this one,
// heard before it, then follow on the cards it changed, in the order they
// were made, as on the device that made them.

/// A rename or a deletion of a tag, as a device records it, which syncs to
/// the user's other devices.
struct TagChange: Sendable, Equatable {
    /// Its ID unique across devices, which its record is named by.
    let id: UUID
    let edit: TagEdit
    /// When it was made, by the engine's time on the device that made it.
    let madeAt: Date

    /// A change read from a row of the `tagChange` table.
    init(row: Row) throws {
        let uuid: String = try row.decode(forColumn: "uuid")
        guard let id = UUID(uuidString: uuid) else {
            throw unreadable("A change to a tag isn't named by a UUID")
        }
        self.id = id
        let tag: String = try row.decode(forColumn: "tag")
        let newName: String? = try row.decode(forColumn: "newName")
        edit = newName.map { .rename(tag, to: $0) } ?? .deletion(tag)
        madeAt = try row.decode(forColumn: "madeAt")
    }
}

/// Records `edit`, made on this device in the write `db`, as a change to the
/// tag, made as the write happens, which waits to be sent to the user's other
/// devices, as the database's trigger records it.
func recordTagChange(_ edit: TagEdit, in db: Database) throws {
    let newName: String? =
        switch edit {
        case .rename(_, let name): name
        case .deletion: nil
        }
    try db.execute(
        sql: "INSERT INTO tagChange (uuid, tag, newName, madeAt) VALUES (?, ?, ?, (SELECT at FROM syncWrite))",
        arguments: [UUID().uuidString, edit.tag, newName])
}

/// Takes `record`, from iCloud, of the change to a tag with this ID, in the
/// write `db`, which records no change to send: a change the device holds
/// already stays as it is, and one new to it comes in and is applied.
func applyTagChange(_ record: ICloudRecord, as id: UUID, in db: Database) throws -> Bool {
    let isNew = try !SyncedTable.tagChanges.holdsRow(with: id, in: db)
    guard try SyncedTable.tagChanges.apply(record, toRowWith: id, in: db) else {
        return false
    }
    if isNew {
        try applyHeardTagChange(id, in: db)
    }
    return true
}

/// Applies the change with this ID, which this device just heard of from
/// another, in the write `db` that took it from iCloud, which records no
/// change to send: as the file's header says, as a change of the device's own
/// made when the change was.
private func applyHeardTagChange(_ id: UUID, in db: Database) throws {
    guard let row = try Row.fetchOne(db, sql: "SELECT * FROM tagChange WHERE uuid = ?", arguments: [id.uuidString])
    else {
        throw unreadable("A change to a tag that came from iCloud isn't there")
    }
    let change = try TagChange(row: row)
    // The rows first, which a rename moves joining the tags that exist apart
    // from the tag, as the cards carry them before it, as on the device that
    // made it.
    try applyToRows(change.edit, madeAt: change.madeAt, in: db)
    var edited = try applyToCards(change.edit, madeAt: change.madeAt, among: nil, in: db)
    let later = try Row.fetchAll(
        db, sql: "SELECT * FROM tagChange WHERE madeAt > ? AND uuid <> ? ORDER BY madeAt, id",
        arguments: [change.madeAt, id.uuidString]
    ).map(TagChange.init(row:))
    for following in later where !edited.isEmpty {
        edited.formUnion(try applyToCards(following.edit, madeAt: following.madeAt, among: edited, in: db))
    }
}

/// Applies `edit`, made at `time`, to the cards among `cards`, or every card
/// when it's nil, in the write `db`, as the file's header says, and returns
/// the ids of those it changed.
private func applyToCards(_ edit: TagEdit, madeAt time: Date, among cards: Set<Int64>?, in db: Database) throws
    -> Set<Int64>
{
    var edited: [SyncedRow] = []
    let ids = try editCards(edit, among: cards, in: db) { uuid, createdAt in
        let row = try SyncedRow(recordType: SyncedRow.RecordType.card.rawValue, recordName: uuid)
        guard try syncs(row, in: db) else {
            edited.append(row)
            return true
        }
        guard (try fieldTimes(of: row, in: db)[.tags] ?? createdAt) < time else {
            return false
        }
        edited.append(row)
        return true
    }
    for card in edited {
        try stamp(.tags, of: card, at: time, in: db)
        try waitToBeSent(card, as: .saved, in: db)
    }
    return ids
}

/// Applies `edit`, made at `time`, to the rows of the `tag` table it changes,
/// in the write `db`, as `make(_:in:)` does, unless one of them, or of those
/// a rename moves them onto, changed since: each field that changes records
/// the change, made at `time`, and its tag waits to be sent.
private func applyToRows(_ edit: TagEdit, madeAt time: Date, in db: Database) throws {
    let changed = try String.fetchAll(db, sql: "SELECT name FROM tag").filter(edit.changes)
    let touched = Set(changed + changed.compactMap(edit.name(of:)))
    guard !changed.isEmpty, try touched.allSatisfy({ try lastChange(ofTag: $0, in: db).map { $0 < time } ?? true })
    else {
        return
    }
    let before = try touched.map { try ownTag($0, in: db) }
    switch edit {
    case .rename(let tag, let name):
        try moveRows(of: tag, to: name, joining: tagsThatExist(apartFrom: tag, in: db), in: db)
    case .deletion:
        for name in changed {
            try db.execute(sql: "DELETE FROM tag WHERE name = ?", arguments: [name])
        }
    }
    for old in before {
        let new = try ownTag(old.name, in: db)
        let fields = old.fieldsDiffering(from: new)
        guard !fields.isEmpty else { continue }
        for field in fields {
            try stamp(field, of: .tag(old.name), at: time, in: db)
        }
        try waitToBeSent(.tag(old.name), as: .saved, in: db)
    }
}

/// When a field of the tag `name` last changed, as far as the device knows,
/// or nil when none did since it came in.
private func lastChange(ofTag name: String, in db: Database) throws -> Date? {
    try Date.fetchOne(
        db, sql: "SELECT max(changedAt) FROM syncFieldTime WHERE recordType = ? AND recordName = ?",
        arguments: [SyncedRow.RecordType.tag.rawValue, name])
}

/// Keeps `time` as when `field` of `row` last changed, unless it changed
/// later, which it keeps.
private func stamp(_ field: SyncedField, of row: SyncedRow, at time: Date, in db: Database) throws {
    try db.execute(
        sql: """
            INSERT INTO syncFieldTime (recordType, recordName, field, changedAt) VALUES (?, ?, ?, ?)
            ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = max(changedAt, excluded.changedAt)
            """,
        arguments: [row.recordType.rawValue, row.recordName, field.rawValue, time])
}

extension CardTag {
    /// The fields of a tag's own that `other`, the same tag at another time,
    /// holds otherwise, as they sync.
    fileprivate func fieldsDiffering(from other: CardTag) -> [SyncedField] {
        var fields: [SyncedField] = []
        if switchedOn != other.switchedOn { fields.append(.switchedOn) }
        if color != other.color { fields.append(.color) }
        if emoji != other.emoji { fields.append(.emoji) }
        if chosenToSync != other.chosenToSync { fields.append(.chosenToSync) }
        if pin != other.pin { fields.append(.pin) }
        return fields
    }
}
