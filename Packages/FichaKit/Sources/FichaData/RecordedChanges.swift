import FichaCore
import Foundation
internal import GRDB

// What renames and deletions of tags (`TagChanges.swift`, ADR 0022) and of
// decks (`DeckChanges.swift`, ADR 0024) share: each is recorded as a change,
// a row of a table of its kind, which syncs as a record of its own and which
// every device that hears of it applies once, as an edit of its own, in the
// write that takes it from iCloud, then following on with the changes of its
// kind made after it that it heard of before it; and each field such an edit
// changes records when it changed so that the edit wins as it should
// (`stamp(_:of:changedBy:in:)`).

/// A rename or a deletion of a tag or a deck, as a device records it in a
/// table of its own, which syncs to the user's other devices, each of which
/// applies it once, as `TagChanges.swift`'s header and `DeckChanges.swift`'s
/// say.
protocol RecordedChange: Sendable {
    /// The table that keeps the changes of its kind.
    static var table: SyncedTable { get }
    /// Its ID unique across devices, which its record is named by.
    var id: UUID { get }
    /// When it was made, by the engine's time on the device that made it.
    var madeAt: Date { get }
    /// A change read from a row of its table.
    init(row: Row) throws
}

/// What applying a change to a tag or a deck changed on a device, which the
/// changes made after it, heard of before it, follow on.
protocol ReachedByChanges {
    var isEmpty: Bool { get }
    mutating func formUnion(_ other: Self)
}

extension Set<Int64>: ReachedByChanges {}

extension RecordedChange {
    /// What a row of its table holds: its ID, the tag or the deck it changes,
    /// under `column`, the name it renames it to, or nil for a deletion, and
    /// when it was made.
    static func columns(of row: Row, naming column: String) throws -> (
        id: UUID, name: String, newName: String?, madeAt: Date
    ) {
        let uuid: String = try row.decode(forColumn: "uuid")
        guard let id = UUID(uuidString: uuid) else {
            throw unreadable("A change to a tag or a deck isn't named by a UUID")
        }
        return (
            id, try row.decode(forColumn: column), try row.decode(forColumn: "newName"),
            try row.decode(forColumn: "madeAt")
        )
    }

    /// Takes `record`, from iCloud, of the change with this ID, in the write
    /// `db`, which records no change to send: a change the device holds
    /// already stays as it is; one it applied before it took a restore's
    /// cards, whose IDs `<its table>AppliedBeforeARestore` keeps
    /// (`dropEverythingThatSyncs(in:)`), comes in again and isn't applied;
    /// and one new to it comes in and is applied with `apply`, to every card
    /// and row it reaches, and then each change of its kind made after it,
    /// which the device heard of before it, in the order they were made, to
    /// what the ones before it reached, while they reached something, as on
    /// the device that made them. Returns false, changing nothing, when the
    /// record refers to a row the device doesn't hold yet, for it to wait.
    static func take<Reached: ReachedByChanges>(
        _ record: ICloudRecord, as id: UUID, in db: Database,
        applying apply: (Self, _ among: Reached?) throws -> Reached
    ) throws -> Bool {
        let appliedBeforeARestore = try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM \(table.name)AppliedBeforeARestore WHERE uuid = ?)",
            arguments: [id.uuidString])
        let isNew = try !table.holdsRow(with: id, in: db) && appliedBeforeARestore != true
        guard try table.apply(record, toRowWith: id, in: db) else {
            return false
        }
        guard isNew else {
            return true
        }
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT * FROM \(table.name) WHERE uuid = ?", arguments: [id.uuidString])
        else {
            throw unreadable("A change to a tag or a deck that came from iCloud isn't there")
        }
        let change = try Self(row: row)
        var reached = try apply(change, nil)
        let later = try Row.fetchAll(
            db, sql: "SELECT * FROM \(table.name) WHERE madeAt > ? AND uuid <> ? ORDER BY madeAt, id",
            arguments: [change.madeAt, id.uuidString]
        ).map(Self.init(row:))
        for following in later where !reached.isEmpty {
            reached.formUnion(try apply(following, reached))
        }
        return true
    }
}

/// Records that `field` of `row` changed as the device applied a change to a
/// tag or a deck made at `time`: at `time`, or, when the field changed since,
/// a millisecond after it last did, as a record holds times, so that the
/// edit wins over every version of the row the device held, the one it sent
/// itself included, which iCloud hands back and which wins a tie, and over
/// no change made later on another device.
func stamp(_ field: SyncedField, of row: SyncedRow, changedBy time: Date, in db: Database) throws {
    let last = try fieldTimes(of: row, in: db)[field]
    let changedAt = last.map { $0 < time ? time : Date(wholeMilliseconds: $0.wholeMilliseconds + 1) } ?? time
    try db.execute(
        sql: """
            INSERT INTO syncFieldTime (recordType, recordName, field, changedAt) VALUES (?, ?, ?, ?)
            ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt
            """,
        arguments: [row.recordType.rawValue, row.recordName, field.rawValue, changedAt])
}
