import FichaCore
import Foundation
internal import GRDB

// A rename or a deletion of a tag reaches every card on every device, those
// that don't sync included (ADR 0022): the device that makes it records it as
// a change to the tag, a row of the `tagChange` table (`Schema`'s "v30
// changes to tags"), which syncs as a record of its own whatever selective
// sync chooses, as a tag's row does, and which every device that hears of it
// applies once, in the write that takes it from iCloud. A device keeps the
// row of each change it made or heard of, which says it applied it: a record
// whose row it holds is never applied again. Changes never leave iCloud, as
// the review log's entries don't, so a device that comes back after any time
// still gets each, but with the zone a restore leaves: a device that takes a
// restore's cards drops its changes with every row that syncs
// (`SyncedRestore.swift`), so that a change the restore undid is never sent
// again, and keeps their IDs in `tagChangeAppliedBeforeARestore`, so that the
// restore's zone, which brings those its copy held, applies none of them a
// second time.
//
// A device that hears of a change applies it as an edit of its own, which
// syncs as such, to the tag's rows as the fetch left them, and to every card
// it holds that carries the tag, or a tag inside it, synced or not, as it
// held them then: the fetch applies the changes it brings after its tags and
// before its cards (`Sync`'s `applyingRank()`). It applies to the cards that
// carry the old name when the device hears of it, and a card that gets the
// old name afterwards, here or from a device that had heard of it, keeps it,
// as ADR 0021 says of a device offline meanwhile; a device that hadn't
// renames the card it sent once it hears. Each field the edit changes, a
// card's tags or what a tag's row has of its own, records it as made when
// the change was, or, when the field changed since, a millisecond after it
// last did (`stamp`), so that a card a device offline meanwhile edited is
// renamed on every device, and a later change elsewhere still wins. The
// changes it holds that were made after this one, heard before it, then
// follow on the cards it changed, in the order they were made, as on the
// device that made them. Changes made in one write, as moving or deleting
// several tags at once makes them, share their time, so each names the one
// it follows, and waits for it, as a record that refers to a row does: a
// device applies them in the order they were made, whether it hears of them
// in one fetch or in several, in any order.

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

/// The keys of a change's record that aren't its columns' names.
enum TagChangeKey {
    /// The ID of the change made right before it in the same write.
    static let follows = "follows"
}

/// Records `edit`, made on this device in the write `db`, as a change to the
/// tag, made as the write happens, following the change with the id
/// `previous`, made right before it in the same write, if one was; it waits
/// to be sent to the user's other devices, as the database's trigger records
/// it. Returns its id.
func recordTagChange(_ edit: TagEdit, following previous: Int64?, in db: Database) throws -> Int64 {
    try db.execute(
        sql: """
            INSERT INTO tagChange (uuid, tag, newName, madeAt, followsId)
            VALUES (?, ?, ?, (SELECT at FROM syncWrite), ?)
            """,
        arguments: [UUID().uuidString, edit.tag, edit.newName, previous])
    return db.lastInsertedRowID
}

/// Takes `record`, from iCloud, of the change to a tag with this ID, in the
/// write `db`, which records no change to send: a change the device holds
/// already stays as it is, one it applied before it took a restore's cards
/// comes in again and isn't applied, and one new to it comes in and is
/// applied. One that follows a change the device doesn't hold yet returns
/// false, to wait for it as a record that refers to a row does, so that
/// every device applies a write's changes in the order they were made,
/// whatever order iCloud hands them in.
func applyTagChange(_ record: ICloudRecord, as id: UUID, in db: Database) throws -> Bool {
    let isNew = try !SyncedTable.tagChanges.holdsRow(with: id, in: db) && !wasAppliedBeforeARestore(id, in: db)
    guard try SyncedTable.tagChanges.apply(record, toRowWith: id, in: db) else {
        return false
    }
    if isNew {
        try applyHeardTagChange(id, in: db)
    }
    return true
}

/// Whether the device applied the change to a tag with this ID before it
/// took a restore's cards (`dropEverythingThatSyncs(in:)`).
private func wasAppliedBeforeARestore(_ id: UUID, in db: Database) throws -> Bool {
    try Bool.fetchOne(
        db, sql: "SELECT EXISTS (SELECT 1 FROM tagChangeAppliedBeforeARestore WHERE uuid = ?)",
        arguments: [id.uuidString]) == true
}

/// Applies the change with this ID, which this device just heard of from
/// another, in the write `db` that took it from iCloud, which records no
/// change to send: as the file's header says, as an edit of the device's
/// own.
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
    let edited = try editCards(edit, among: cards, in: db)
    for card in edited {
        try stamp(.tags, of: card.row, changedBy: time, in: db)
        try waitToBeSent(card.row, as: .saved, in: db)
    }
    return Set(edited.map(\.id))
}

/// Applies `edit`, made at `time`, to the rows of the `tag` table it changes,
/// in the write `db`, as `editRows(_:in:)` makes it: each field that changes,
/// of those rows or of those a rename moves them onto, records the change
/// (`stamp`), and its tag waits to be sent.
private func applyToRows(_ edit: TagEdit, madeAt time: Date, in db: Database) throws {
    let changed = try String.fetchAll(db, sql: "SELECT name FROM tag").filter(edit.changes)
    guard !changed.isEmpty else {
        return
    }
    let touched = Set(changed + changed.compactMap(edit.name(of:))).sorted()
    let before = try touched.map { try ownTag($0, in: db) }
    try editRows(edit, in: db)
    for old in before {
        let new = try ownTag(old.name, in: db)
        let fields = old.fieldsDiffering(from: new)
        guard !fields.isEmpty else { continue }
        for field in fields {
            try stamp(field, of: .tag(old.name), changedBy: time, in: db)
        }
        try waitToBeSent(.tag(old.name), as: .saved, in: db)
    }
}

/// Records that `field` of `row` changed as the device applied a change to a
/// tag made at `time`: at `time`, or, when the field changed since, a
/// millisecond after it last did, as a record holds times, so that the edit
/// wins over every version of the row the device held, the one it sent
/// itself included, which iCloud hands back and which wins a tie, and over
/// no change made later on another device.
private func stamp(_ field: SyncedField, of row: SyncedRow, changedBy time: Date, in db: Database) throws {
    let last = try fieldTimes(of: row, in: db)[field]
    let changedAt = last.map { $0 < time ? time : Date(wholeMilliseconds: $0.wholeMilliseconds + 1) } ?? time
    try db.execute(
        sql: """
            INSERT INTO syncFieldTime (recordType, recordName, field, changedAt) VALUES (?, ?, ?, ?)
            ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt
            """,
        arguments: [row.recordType.rawValue, row.recordName, field.rawValue, changedAt])
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
