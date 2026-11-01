import FichaCore
import Foundation
internal import GRDB

/// A table whose rows sync each as a record named by its ID unique across
/// devices (ADR 0017): the cards, the captures, the review log, the user's
/// card types and the changes to tags and decks. It says which of its columns the
/// record holds, each under which key and how, and which of them make up each
/// field that keeps when it last changed, of which the latest change wins.
struct SyncedTable: Sendable {
    /// The table's name.
    let name: String
    /// The row that syncs with this ID unique across devices.
    let syncedRow: @Sendable (UUID) -> SyncedRow
    /// The fields that keep when they last changed, each with its columns.
    let fields: [Field]
    /// The other columns the record holds, which a row takes as it comes in,
    /// and never changes after, but a later time.
    let fixedColumns: [SyncedColumn]
    /// Whether a row that comes from another device says so, as an entry of
    /// the review log does, which ⌘Z never takes back.
    let marksRowsFromAnotherDevice: Bool
    /// Reads the row with this id as the engine does, to check that a record
    /// from iCloud left a row this version of Ficha can read, or throws.
    let check: @Sendable (_ id: Int64, _ db: Database) throws -> Void

    /// A field that keeps when it last changed, with the columns it's made of.
    struct Field: Sendable {
        let syncedField: SyncedField
        let columns: [SyncedColumn]
        /// How the row with an id takes the field from a record, when one
        /// place must set it, as a card's flag and burial (`CODING_STANDARDS.md`),
        /// or nil to write its columns.
        let take: (@Sendable (_ record: ICloudRecord, _ id: Int64, _ db: Database) throws -> Void)?

        init(
            _ syncedField: SyncedField, _ columns: SyncedColumn...,
            takenWith take: (@Sendable (_ record: ICloudRecord, _ id: Int64, _ db: Database) throws -> Void)? = nil
        ) {
            self.syncedField = syncedField
            self.columns = columns
            self.take = take
        }
    }

    /// Every table whose rows sync named by their ID.
    static let all = [cards, captures, reviewLog, userTypes, tagChanges, deckChanges]

    /// A card's parts, as "What other devices changed" in #298 lists them.
    static let cards = SyncedTable(
        name: "card", syncedRow: { .card($0) },
        fields: [
            Field(.front, SyncedColumn("front", .text)),
            Field(.back, SyncedColumn("back", .text)),
            Field(.frontImage, SyncedColumn("frontImage", .text)),
            Field(.backImage, SyncedColumn("backImage", .text)),
            Field(.frontSound, SyncedColumn("frontSound", .text)),
            Field(.backSound, SyncedColumn("backSound", .text)),
            // A JSON array, as the table keeps it.
            Field(.tags, SyncedColumn("tags", .text)),
            Field(.type, SyncedColumn("type", key: "cardType", .text)),
            Field(.deck, SyncedColumn("deck", .textOrEmpty)),
            Field(.source, SyncedColumn("source", .text)),
            Field(.bothWays, SyncedColumn("bothWays", .boolean)),
            Field(.flag, SyncedColumn(CardKey.flagNote, .text), SyncedColumn(CardKey.flaggedAt, .time)) {
                record, id, db in
                _ = try takeFlag(record.flag(), of: id, in: db)
            },
            Field(.burial, SyncedColumn(CardKey.buriedAt, .time)) { record, id, db in
                _ = try takeBurial(record.time(CardKey.buriedAt), of: id, in: db)
            },
        ],
        fixedColumns: [
            SyncedColumn("createdAt", .time),
            // A change to a side on any device is a change of that side
            // (#298), for the edited time and so for the forgotten-often
            // count.
            SyncedColumn("editedAt", .laterTime),
            SyncedColumn("captureId", key: "capture", .link(to: "capture")),
        ],
        marksRowsFromAnotherDevice: false,
        check: { id, db in _ = try existingCard(id, in: db) })

    /// A capture's fields.
    static let captures = SyncedTable(
        name: "capture", syncedRow: { .capture($0) },
        fields: [
            Field(.text, SyncedColumn("text", .text)),
            Field(.note, SyncedColumn("note", .text)),
            Field(.source, SyncedColumn("source", .text)),
            Field(.refined, SyncedColumn("refinedAt", .time)),
            Field(.expandedCard, SyncedColumn("expandsCardId", key: "expandsCard", .link(to: "card"))),
            Field(.followedUpCard, SyncedColumn("followsUpCardId", key: "followsUpCard", .link(to: "card"))),
        ],
        fixedColumns: [SyncedColumn("createdAt", .time)],
        marksRowsFromAnotherDevice: false,
        check: { id, db in _ = try Capture(row: try tableRow(id, of: "capture", in: db)) })

    /// An entry of the review log, which never changes: the entries of two
    /// devices join, and each card's ways are worked out from them all (ADR
    /// 0017).
    static let reviewLog = SyncedTable(
        name: "reviewLog", syncedRow: { .reviewLogEntry($0) },
        fields: [],
        fixedColumns: [
            SyncedColumn("cardId", key: "card", .link(to: "card")),
            SyncedColumn("way", .text),
            SyncedColumn("kind", .text),
            SyncedColumn("rating", .text),
            SyncedColumn("due", .time),
            // A placement's ease, as Anki had it.
            SyncedColumn("ease", .real),
            // As this device holds it, to the millisecond, so that every
            // device replays the joined log alike.
            SyncedColumn("answeredAt", .time),
            SyncedColumn("responseTime", .real),
            SyncedColumn("trigger", .text),
            // As the device that answered decided it, never worked out again.
            SyncedColumn("isAhead", .boolean),
            // The UUID of the entry a review answered, which can come later,
            // so it's no link: the scheduler keeps a review's interval only
            // when it answered the entry replayed just before it.
            SyncedColumn("answeredEntryUuid", key: "answeredEntry", .text),
            // A review's or a placement's interval, in seconds, which an
            // entry from a Ficha before FSRS comes without, and is given as
            // it comes in (`carriedOver(_:as:in:)`).
            SyncedColumn("interval", .real),
        ],
        marksRowsFromAnotherDevice: true,
        check: { id, db in _ = try ReviewLogEntry(row: try tableRow(id, of: "reviewLog", in: db)) })

    /// A card type the user made, whose name and emoji change apart. A card
    /// names it by its ID in its type column, which syncs as text, so a card
    /// can come before its type, or after the type's deletion, and has no
    /// type then (`UserTypes.swift`).
    static let userTypes = SyncedTable(
        name: "userType", syncedRow: { .userType($0) },
        fields: [
            Field(.name, SyncedColumn("name", .text)),
            Field(.emoji, SyncedColumn("emoji", .text)),
        ],
        fixedColumns: [],
        marksRowsFromAnotherDevice: false,
        check: { id, db in _ = try UserType(row: try tableRow(id, of: "userType", in: db)) })

    /// A rename or a deletion of a tag, which never changes: it comes in
    /// whole, and is applied as it does (`TagChanges.swift`), once the
    /// change it follows in its write is there.
    static let tagChanges = SyncedTable(
        name: "tagChange", syncedRow: { .tagChange($0) },
        fields: [],
        fixedColumns: [
            SyncedColumn("tag", .text), SyncedColumn("newName", .text), SyncedColumn("madeAt", .time),
            SyncedColumn("followsId", key: TagChangeKey.follows, .link(to: "tagChange")),
        ],
        marksRowsFromAnotherDevice: false,
        check: { id, db in _ = try TagChange(row: try tableRow(id, of: "tagChange", in: db)) })

    /// A rename or a deletion of a deck, which never changes: it comes in
    /// whole, a deletion with the cards it deleted, and is applied as it
    /// does (`DeckChanges.swift`).
    static let deckChanges = SyncedTable(
        name: "deckChange", syncedRow: { .deckChange($0) },
        fields: [],
        fixedColumns: [
            SyncedColumn("deck", .text), SyncedColumn("newName", .text), SyncedColumn("madeAt", .time),
            SyncedColumn("deletedCards", .bytes),
        ],
        marksRowsFromAnotherDevice: false,
        check: { id, db in
            let row = try tableRow(id, of: "deckChange", in: db)
            _ = try DeckChange(row: row)
            _ = try DeckChange.cardsDeleted(in: row)
        })

    /// Whether the table has a row with this ID unique across devices.
    func holdsRow(with uuid: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM \(name) WHERE uuid = ?)", arguments: [uuid.uuidString]) == true
    }

    /// The record the row with this ID syncs as, as it is now, without what
    /// iCloud said of it, or nil when there's no such row.
    func record(ofRowWith uuid: UUID, in db: Database) throws -> ICloudRecord? {
        guard let stored = try storedRow(with: uuid, in: db) else {
            return nil
        }
        var values: [String: ICloudValue?] = [:]
        for column in columns {
            values[column.key] = try column.value(in: stored, in: db)
        }
        return try syncedRecord(of: syncedRow(uuid), holding: values, andTimesOf: fields.map(\.syncedField), in: db)
    }

    /// Applies `record`, from iCloud, to the row with this ID: it takes each
    /// field whose change in the record is the latest, and the later of two
    /// times that only move forward, or comes in whole, saying so when the
    /// table marks rows from another device. Returns false, changing
    /// nothing, when the record refers to a row the device doesn't hold yet.
    func apply(_ record: ICloudRecord, toRowWith uuid: UUID, in db: Database) throws -> Bool {
        let synced = syncedRow(uuid)
        let incomingTimes = try record.fieldTimes(of: fields.map(\.syncedField))
        guard let stored = try storedRow(with: uuid, in: db) else {
            return try insert(record, as: uuid, changedAt: incomingTimes, in: db)
        }
        let localTimes = try fieldTimes(of: synced, in: db)
        var assignments: [(column: String, value: DatabaseValue)] = []
        var won: [Field] = []
        for field in fields {
            let incoming = FieldChange(
                changedAt: incomingTimes[field.syncedField],
                holdsSomething: field.columns.contains { record.value(of: $0.key) != nil })
            let local = FieldChange(
                changedAt: localTimes[field.syncedField],
                holdsSomething: try field.columns.contains { try $0.holdsSomething(in: stored) })
            guard incoming.wins(over: local) else {
                continue
            }
            won.append(field)
            guard field.take == nil else {
                continue
            }
            for column in field.columns {
                guard let value = try column.databaseValue(in: record, in: db) else {
                    return false
                }
                assignments.append((column.name, value))
            }
        }
        for column in fixedColumns where column.kind == .laterTime {
            let local: Date? = try stored.decode(forColumn: column.name)
            if let incoming = try record.time(column.key), local.map({ incoming > $0 }) ?? true {
                assignments.append((column.name, incoming.databaseValue))
            }
        }
        if !assignments.isEmpty {
            try db.execute(
                sql:
                    "UPDATE \(name) SET \(assignments.map { "\($0.column) = ?" }.joined(separator: ", ")) WHERE uuid = ?",
                arguments: StatementArguments(assignments.map(\.value) + [uuid.uuidString.databaseValue]))
        }
        let id: Int64 = try stored.decode(forColumn: "id")
        for field in won {
            try field.take?(record, id, db)
        }
        try stamp(incomingTimes.filter { time in won.contains { $0.syncedField == time.key } }, of: synced, in: db)
        try check(id, db)
        return true
    }

    /// Inserts the row with this ID as `record`, from iCloud, holds it, with
    /// when each field changed, or returns false, inserting nothing, when it
    /// refers to a row the device doesn't hold yet.
    private func insert(_ record: ICloudRecord, as uuid: UUID, changedAt times: [SyncedField: Date], in db: Database)
        throws -> Bool
    {
        var assignments: [(column: String, value: DatabaseValue)] = [("uuid", uuid.uuidString.databaseValue)]
        for column in fields.filter({ $0.take == nil }).flatMap(\.columns) + fixedColumns {
            guard let value = try column.databaseValue(in: record, in: db) else {
                return false
            }
            assignments.append((column.name, value))
        }
        if marksRowsFromAnotherDevice {
            assignments.append(("isFromAnotherDevice", true.databaseValue))
        }
        try db.execute(
            sql: """
                INSERT INTO \(name) (\(assignments.map(\.column).joined(separator: ", ")))
                VALUES (\(assignments.map { _ in "?" }.joined(separator: ", ")))
                """,
            arguments: StatementArguments(assignments.map(\.value)))
        let id = db.lastInsertedRowID
        for field in fields {
            try field.take?(record, id, db)
        }
        try stamp(times, of: syncedRow(uuid), in: db)
        try check(id, db)
        return true
    }

    /// Every column the record holds.
    private var columns: [SyncedColumn] {
        fields.flatMap(\.columns) + fixedColumns
    }

    /// The row with this ID unique across devices, as the table holds it, or
    /// nil when there's none.
    private func storedRow(with uuid: UUID, in db: Database) throws -> Row? {
        try Row.fetchOne(db, sql: "SELECT * FROM \(name) WHERE uuid = ?", arguments: [uuid.uuidString])
    }
}

/// A column of a table that syncs, as its row's record holds it.
struct SyncedColumn: Sendable {
    /// The column's name.
    let name: String
    /// The key of the record's field that holds it.
    let key: String
    let kind: Kind

    /// What the column holds, and so how the record holds it.
    enum Kind: Sendable, Equatable {
        case text
        /// Text the row keeps empty for nothing, as a card keeps Default as
        /// its deck, which the record holds as nothing, so that a record from
        /// before the column, which lacks it, holds what the row would.
        case textOrEmpty
        /// True or false, which the record holds as 1 or 0.
        case boolean
        case integer
        /// A number with a fraction.
        case real
        /// Bytes, which the record holds as they are.
        case bytes
        /// A time, which the record holds as whole milliseconds since 1970.
        case time
        /// A time that only moves forward, as `time`: a row takes the later
        /// of its own and the record's.
        case laterTime
        /// The id of a row of another table, which the record holds as that
        /// row's ID unique across devices, since each device gives its rows
        /// ids of its own.
        case link(to: String)
    }

    /// The column `name`, which the record holds under the same name unless
    /// `key` says another.
    init(_ name: String, key: String? = nil, _ kind: Kind) {
        self.name = name
        self.key = key ?? name
        self.kind = kind
    }

    /// Whether the column of `row`, of the table, holds something, which the
    /// record holds too.
    func holdsSomething(in row: Row) throws -> Bool {
        switch kind {
        case .textOrEmpty: try row.decode(forColumn: name) as String != ""
        default: !(row[name] as DatabaseValue).isNull
        }
    }

    /// The value the record holds for the column of `row`, of the table, or
    /// nil for none.
    func value(in row: Row, in db: Database) throws -> ICloudValue? {
        switch kind {
        case .text:
            return (try row.decode(forColumn: name) as String?).map(ICloudValue.string)
        case .textOrEmpty:
            let text: String = try row.decode(forColumn: name)
            return text.isEmpty ? nil : .string(text)
        case .boolean:
            return (try row.decode(forColumn: name) as Bool?).map { .int($0 ? 1 : 0) }
        case .integer:
            return (try row.decode(forColumn: name) as Int64?).map(ICloudValue.int)
        case .real:
            return (try row.decode(forColumn: name) as Double?).map(ICloudValue.double)
        case .bytes:
            return (try row.decode(forColumn: name) as Data?).map(ICloudValue.bytes)
        case .time, .laterTime:
            return (try row.decode(forColumn: name) as Date?).map { .int($0.wholeMilliseconds) }
        case .link(let table):
            guard let id = try row.decode(forColumn: name) as Int64? else {
                return nil
            }
            guard let uuid = try String.fetchOne(db, sql: "SELECT uuid FROM \(table) WHERE id = ?", arguments: [id])
            else {
                throw unreadable("A row that syncs refers to a row that isn't there")
            }
            return .string(uuid)
        }
    }

    /// The value the column takes from `record`, from iCloud, or nil when it
    /// refers to a row the device doesn't hold yet. It throws when the record
    /// holds something else than the column does.
    func databaseValue(in record: ICloudRecord, in db: Database) throws -> DatabaseValue? {
        switch (kind, record.value(of: key)) {
        case (.textOrEmpty, nil):
            return "".databaseValue
        case (_, nil):
            return .null
        case (.text, .string(let text)?), (.textOrEmpty, .string(let text)?):
            return text.databaseValue
        case (.boolean, .int(let number)?) where number == 0 || number == 1:
            return (number == 1).databaseValue
        case (.integer, .int(let number)?):
            return number.databaseValue
        case (.real, .double(let number)?):
            return number.databaseValue
        case (.real, .int(let number)?):
            return Double(number).databaseValue
        case (.bytes, .bytes(let bytes)?):
            return bytes.databaseValue
        case (.time, .int(let milliseconds)?), (.laterTime, .int(let milliseconds)?):
            return Date(wholeMilliseconds: milliseconds).databaseValue
        case (.link(let table), .string(let name)?):
            guard let uuid = UUID(uuidString: name) else {
                throw unreadable("A record from iCloud refers to a row with an ID that isn't a UUID")
            }
            return try Int64.fetchOne(db, sql: "SELECT id FROM \(table) WHERE uuid = ?", arguments: [uuid.uuidString])?
                .databaseValue
        default:
            throw unreadable("A record from iCloud holds something else than its row's column does")
        }
    }
}

/// The keys of a card's flag and burial in its record, named after their
/// columns, which sync reads again as it takes them.
private enum CardKey {
    static let flagNote = "flagNote"
    static let flaggedAt = "flaggedAt"
    static let buriedAt = "buriedAt"
}

extension ICloudRecord {
    /// The flag a card's record holds, its note and when it was flagged, or
    /// nil for none. It throws for half a flag.
    fileprivate func flag() throws -> Flag? {
        switch (try optionalText(CardKey.flagNote), try time(CardKey.flaggedAt)) {
        case (nil, nil): return nil
        case (let note?, let flaggedAt?): return Flag(note: note, flaggedAt: flaggedAt)
        default: throw unreadable("A card from iCloud has a flag without its note or its time")
        }
    }
}

/// The row of `table` with this id, or an error when there's none.
private func tableRow(_ id: Int64, of table: String, in db: Database) throws -> Row {
    guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [id]) else {
        throw unreadable("A row that syncs isn't there")
    }
    return row
}
