import CryptoKit
import FichaCore
import Foundation
internal import GRDB

// How each row that syncs travels as a record in iCloud (ADR 0017): its
// record's ID, its record as the row is now, and how a record from iCloud
// changes the row. Of each field that keeps when it last changed, the latest
// change wins, and the rest merges; a row new to the device comes in whole.
// Cards, captures, the review log, the user's card types and the changes to
// tags and decks are described by `SyncedTable`, tags by `SyncedTags.swift`, decks by
// `SyncedDecks.swift`, the settings that decide progress by `SyncedProgressSettings.swift`, and the
// choice of what syncs by `SelectiveSync.swift`, which also says how a row
// that stops syncing leaves iCloud.

extension SyncedRow {
    /// The ID of the record iCloud keeps the row as, in the cards' zone:
    /// named by the row's ID unique across devices, a tag by its name's
    /// SHA-256 after "tag-", since a record's name is ASCII, up to 255
    /// characters, and a tag's name can be anything, a deck by its name's
    /// after "deck-", Default's empty one too, and a row there's one of by
    /// its type.
    var recordID: ICloudRecordID {
        switch self {
        case .card(let id), .capture(let id), .reviewLogEntry(let id), .userType(let id), .tagChange(let id),
            .deckChange(let id):
            ICloudRecordID(name: id.uuidString, zone: .cards)
        case .tag(let name):
            ICloudRecordID(name: "tag-" + hashed(name), zone: .cards)
        case .deck(let name):
            ICloudRecordID(name: "deck-" + hashed(name), zone: .cards)
        case .progressSettings, .syncChoice:
            ICloudRecordID(name: recordName, zone: .cards)
        }
    }

    /// The row `record`, from iCloud, holds: by its type and name, or a tag
    /// or a deck by the name it holds. It throws for a type this version of
    /// Ficha doesn't know.
    init(of record: ICloudRecord) throws {
        if record.type == RecordType.tag.rawValue {
            self = .tag(try record.text(TagKey.name))
        } else if record.type == RecordType.deck.rawValue {
            self = try .deck(of: record)
        } else {
            try self.init(recordType: record.type, recordName: record.id.name)
        }
    }
}

/// The row that syncs as the record with this ID, as the device holds it
/// now, or nil when it holds none: a card, a capture, an entry of the review
/// log, a user type or a change to a tag or a deck by its ID, a row there's one of by
/// its type, or a tag or a deck, which needn't have a row of its own, by the
/// name whose record it is, among those that wait to be sent or that have a
/// row or had something of their own.
func syncedRow(named id: ICloudRecordID, in db: Database) throws -> SyncedRow? {
    guard id.zone == .cards else {
        return nil
    }
    if let uuid = UUID(uuidString: id.name) {
        return try SyncedTable.all.first { try $0.holdsRow(with: uuid, in: db) }.map { $0.syncedRow(uuid) }
    }
    if let row = [SyncedRow.progressSettings, .syncChoice].first(where: { $0.recordID == id }) {
        return row
    }
    let named = try [(SyncedRow.RecordType.tag, SyncedRow.tag), (.deck, SyncedRow.deck)].flatMap { type, row in
        try String.fetchAll(
            db,
            sql: """
                SELECT recordName FROM syncPending WHERE recordType = ?
                UNION SELECT name FROM \(type.rawValue)
                UNION SELECT recordName FROM syncFieldTime WHERE recordType = ?
                """,
            arguments: [type.rawValue, type.rawValue]
        ).map(row)
    }
    return named.first { $0.recordID == id }
}

/// `name`'s SHA-256, in lowercase hexadecimal, which names a tag's or a
/// deck's record.
private func hashed(_ name: String) -> String {
    SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// The record `row` syncs as, as it is now, with what iCloud said of it last,
/// or nil when the device no longer holds it, as a deck whose row went: a
/// card, a capture or an entry of the review log that doesn't sync as one
/// that left (`syncedOrLeft(_:of:in:)`).
func record(of row: SyncedRow, in db: Database) throws -> ICloudRecord? {
    let record: ICloudRecord? =
        switch row {
        case .card(let id): try SyncedTable.cards.record(ofRowWith: id, in: db)
        case .capture(let id): try SyncedTable.captures.record(ofRowWith: id, in: db)
        case .reviewLogEntry(let id): try SyncedTable.reviewLog.record(ofRowWith: id, in: db)
        case .tag(let name): try tagRecord(name, in: db)
        case .progressSettings: try progressSettingsRecord(in: db)
        case .syncChoice: try syncChoiceRecord(in: db)
        case .userType(let id): try SyncedTable.userTypes.record(ofRowWith: id, in: db)
        case .tagChange(let id): try SyncedTable.tagChanges.record(ofRowWith: id, in: db)
        case .deck(let name): try deckRecord(name, in: db)
        case .deckChange(let id): try SyncedTable.deckChanges.record(ofRowWith: id, in: db)
        }
    return try record.map { try syncedOrLeft($0, of: row, in: db) }?
        .with(systemFields: systemFields(of: row.recordID, in: db))
}

/// Applies `record`, from iCloud, to `row`, the row it holds: the row takes
/// each field whose change in the record is the latest, or comes in whole. A
/// change to a tag or a deck new to the device is applied as it comes in
/// (`TagChanges.swift`, `DeckChanges.swift`), and one it holds already never
/// again.
/// Returns false, changing nothing, when the record refers to a row the
/// device doesn't hold yet, such as a card's capture, for it to wait.
private func apply(_ record: ICloudRecord, to row: SyncedRow, in db: Database) throws -> Bool {
    switch row {
    case .card(let id): try SyncedTable.cards.apply(record, toRowWith: id, in: db)
    case .capture(let id): try SyncedTable.captures.apply(record, toRowWith: id, in: db)
    case .reviewLogEntry(let id):
        // An entry from a version of Ficha before FSRS comes in carried over
        // to the scheduler's, as the migration carried over this device's.
        try SyncedTable.reviewLog.apply(
            try SyncedTable.reviewLog.holdsRow(with: id, in: db) ? record : try carriedOver(record, as: id, in: db),
            toRowWith: id, in: db)
    case .tag(let name): try applyTag(record, named: name, in: db)
    case .progressSettings: try applyProgressSettings(record, in: db)
    case .syncChoice: try applySyncChoice(record, in: db)
    case .userType(let id): try SyncedTable.userTypes.apply(record, toRowWith: id, in: db)
    case .tagChange(let id): try applyTagChange(record, as: id, in: db)
    case .deck(let name): try applyDeck(record, named: name, in: db)
    case .deckChange(let id): try applyDeckChange(record, as: id, in: db)
    }
}

/// What became of a record from iCloud.
enum Received: Equatable {
    /// The device holds what it holds.
    case applied
    /// It waits, until the row it refers to comes, or a version of Ficha
    /// that can read it.
    case waits
    /// It's dropped: the device deleted its row, and the deletion, which
    /// waits to be sent, wins.
    case dropped
}

/// Applies `record`, from iCloud, as `apply(_:to:in:)` says, in a write that
/// records no change to send, and keeps what iCloud says of it. A record of
/// a row that left iCloud is taken as `takeWhatLeft(_:of:in:)` says, which
/// never deletes or makes a row. A record that refers to a row the device
/// doesn't hold yet waits, and so does one this version of Ficha can't read,
/// which the log says: each is tried again whenever records come, until it's
/// applied or a later version of it replaces it. A record of a row the
/// device deleted, whose deletion waits to be sent, is dropped. A failure of
/// the database itself throws.
func receive(_ record: ICloudRecord, in db: Database) throws -> Received {
    if try pendingDeletion(of: record.id, in: db) != nil {
        try dropWaitingRecord(of: record.id, in: db)
        return .dropped
    }
    let row: SyncedRow
    var applied = false
    do {
        row = try SyncedRow(of: record)
        try db.inSavepoint {
            if record.hasLeft {
                try takeWhatLeft(record, of: row, in: db)
                applied = true
            } else {
                applied = try apply(record, to: row, in: db)
            }
            return applied ? .commit : .rollback
        }
    } catch let error where isUnreadable(error) {
        syncLogger.error(
            "A record of type \(record.type, privacy: .public) from iCloud can't be read, and waits: \(String(describing: error))"
        )
        return try keepWaiting(record, in: db)
    }
    guard applied else {
        return try keepWaiting(record, in: db)
    }
    try keep(record.systemFields, of: record.id, hasLeft: record.hasLeft, in: db)
    try forgetPendingSave(of: row, whenICloudHolds: record, in: db)
    try dropWaitingRecord(of: record.id, in: db)
    return .applied
}

/// Keeps `record` waiting to be applied, in place of an older version of it.
private func keepWaiting(_ record: ICloudRecord, in db: Database) throws -> Received {
    try db.execute(
        sql: """
            INSERT INTO syncIncoming (zone, name, record) VALUES (?, ?, ?)
            ON CONFLICT (zone, name) DO UPDATE SET record = excluded.record
            """,
        arguments: [record.id.zone.name, record.id.name, try JSONEncoder().encode(record)])
    return .waits
}

/// Whether `error`, from applying a record, says the record holds what this
/// version of Ficha can't read or keep, rather than that the database
/// failed: a type or a value it doesn't know, or one its tables refuse.
private func isUnreadable(_ error: any Error) -> Bool {
    switch error {
    case is DecodingError, is RowDecodingError: true
    case let error as DatabaseError: error.resultCode == .SQLITE_CONSTRAINT
    default: false
    }
}

/// Applies the records that wait, as long as one more of them can be.
func applyWaitingRecords(in db: Database) throws {
    var appliedOne = true
    while appliedOne {
        appliedOne = false
        for data in try Data.fetchAll(db, sql: "SELECT record FROM syncIncoming ORDER BY rowid") {
            let record = try JSONDecoder().decode(ICloudRecord.self, from: data)
            if try receive(record, in: db) == .applied {
                appliedOne = true
            }
        }
    }
}

/// Drops the version of the record with this ID that waited to be applied,
/// if one did.
func dropWaitingRecord(of id: ICloudRecordID, in db: Database) throws {
    try db.execute(sql: "DELETE FROM syncIncoming WHERE zone = ? AND name = ?", arguments: [id.zone.name, id.name])
}

/// Forgets the change of `row` that waits to be sent, when `record`, as
/// iCloud holds it, holds what the row holds now: iCloud has it already.
func forgetPendingSave(of row: SyncedRow, whenICloudHolds record: ICloudRecord, in db: Database) throws {
    guard try hasPendingSave(row, in: db), let current = try FichaData.record(of: row, in: db),
        current.holdsTheSame(as: record)
    else {
        return
    }
    try db.execute(
        sql: "DELETE FROM syncPending WHERE recordType = ? AND recordName = ? AND NOT isDeletion",
        arguments: [row.recordType.rawValue, row.recordName])
}

/// Whether `row` waits to be sent as saved.
func hasPendingSave(_ row: SyncedRow, in db: Database) throws -> Bool {
    try Bool.fetchOne(
        db,
        sql: "SELECT EXISTS (SELECT 1 FROM syncPending WHERE recordType = ? AND recordName = ? AND NOT isDeletion)",
        arguments: [row.recordType.rawValue, row.recordName]) == true
}

/// What iCloud said last of the record with this ID, or nil when the device
/// never heard of it from iCloud.
func systemFields(of id: ICloudRecordID, in db: Database) throws -> Data? {
    try Data.fetchOne(
        db, sql: "SELECT systemFields FROM syncRecord WHERE zone = ? AND name = ?", arguments: [id.zone.name, id.name])
}

/// Keeps `systemFields` as what iCloud said last of the record with this ID,
/// with whether it holds it as one whose row left iCloud, or forgets what it
/// said when it's nil.
func keep(_ systemFields: Data?, of id: ICloudRecordID, hasLeft: Bool = false, in db: Database) throws {
    guard let systemFields else {
        try db.execute(sql: "DELETE FROM syncRecord WHERE zone = ? AND name = ?", arguments: [id.zone.name, id.name])
        return
    }
    try db.execute(
        sql: """
            INSERT INTO syncRecord (zone, name, systemFields, hasLeft) VALUES (?, ?, ?, ?)
            ON CONFLICT (zone, name) DO UPDATE SET systemFields = excluded.systemFields, hasLeft = excluded.hasLeft
            """,
        arguments: [id.zone.name, id.name, systemFields, hasLeft])
}

/// The record `row` syncs as, without what iCloud said of it: `values`, and
/// when each of `fields` last changed, of those that changed since the row
/// came in.
func syncedRecord(
    of row: SyncedRow, holding values: [String: ICloudValue?], andTimesOf fields: [SyncedField], in db: Database
) throws -> ICloudRecord {
    let times = try fieldTimes(of: row, in: db)
    var values = values
    for field in fields {
        values[field.timeKey] = times[field].map { .int($0.wholeMilliseconds) }
    }
    return ICloudRecord(id: row.recordID, type: row.recordType.rawValue, fields: values, systemFields: nil)
}

/// Has `take` apply to `row` those of `fields` whose change in `record`, from
/// iCloud, wins over the one in `own`, the record the row syncs as on this
/// device, as `FieldChange` decides, then keeps when each of them changed, as
/// `record` says. Each field's value is under its name in both records.
func takeLatestChanges(
    of fields: [SyncedField], in record: ICloudRecord, over own: ICloudRecord, to row: SyncedRow, in db: Database,
    with take: (_ won: Set<SyncedField>) throws -> Void
) throws {
    let incoming = try record.fieldTimes(of: fields)
    let local = try own.fieldTimes(of: fields)
    let won = Set(
        fields.filter { field in
            FieldChange(changedAt: incoming[field], holdsSomething: record.value(of: field.rawValue) != nil)
                .wins(over: FieldChange(changedAt: local[field], holdsSomething: own.value(of: field.rawValue) != nil))
        })
    try take(won)
    try stamp(incoming.filter { won.contains($0.key) }, of: row, in: db)
}

/// Keeps `times` as when each of `row`'s fields last changed.
func stamp(_ times: [SyncedField: Date], of row: SyncedRow, in db: Database) throws {
    for (field, time) in times {
        try db.execute(
            sql: """
                INSERT INTO syncFieldTime (recordType, recordName, field, changedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt
                """,
            arguments: [row.recordType.rawValue, row.recordName, field.rawValue, time])
    }
}

extension SyncedField {
    /// The key of the field of a record that holds when this field last
    /// changed.
    var timeKey: String {
        "\(rawValue)ChangedAt"
    }
}

extension ICloudRecord {
    /// When each of `fields` last changed, as the record holds it, of those
    /// that changed since their row came in.
    func fieldTimes(of fields: some Sequence<SyncedField>) throws -> [SyncedField: Date] {
        var times: [SyncedField: Date] = [:]
        for field in fields {
            times[field] = try time(field.timeKey)
        }
        return times
    }

    /// The text the field `key` holds, or an error when it holds none.
    func text(_ key: String) throws -> String {
        guard let text = try optionalText(key) else {
            throw unreadable("A record from iCloud has no text where it should")
        }
        return text
    }

    /// The text the field `key` holds, or nil when it holds nothing.
    func optionalText(_ key: String) throws -> String? {
        switch value(of: key) {
        case nil: return nil
        case .string(let text)?: return text
        case .int?, .double?, .bytes?, .asset?:
            throw unreadable("A record from iCloud holds something else where text should be")
        }
    }

    /// The time the field `key` holds, or nil when it holds nothing.
    func time(_ key: String) throws -> Date? {
        switch value(of: key) {
        case nil: return nil
        case .int(let milliseconds)?: return Date(wholeMilliseconds: milliseconds)
        case .string?, .double?, .bytes?, .asset?:
            throw unreadable("A record from iCloud holds something else where a time should be")
        }
    }

    /// The whole number the field `key` holds, or an error when it holds
    /// none.
    func integer(_ key: String) throws -> Int {
        guard let number = try optionalInteger(key) else {
            throw unreadable("A record from iCloud has no number where it should")
        }
        return number
    }

    /// The number with a fraction the field `key` holds, or nil when it
    /// holds nothing: a whole number reads as one too, as a column of
    /// numbers with a fraction reads it (`SyncedColumn`).
    func optionalNumber(_ key: String) throws -> Double? {
        switch value(of: key) {
        case nil: return nil
        case .double(let number)?: return number
        case .int(let number)?: return Double(number)
        case .string?, .bytes?, .asset?:
            throw unreadable("A record from iCloud holds something else where a number should be")
        }
    }

    /// The whole number the field `key` holds, or nil when it holds nothing.
    func optionalInteger(_ key: String) throws -> Int? {
        switch value(of: key) {
        case nil: return nil
        case .int(let number)?:
            guard let number = Int(exactly: number) else {
                throw unreadable("A record from iCloud holds a number too large for this device")
            }
            return number
        case .string?, .double?, .bytes?, .asset?:
            throw unreadable("A record from iCloud holds something else where a number should be")
        }
    }
}

extension Date {
    /// The time as whole milliseconds since 1970, as the database keeps it,
    /// and as it travels in a record.
    var wholeMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }

    /// The time that's this many whole milliseconds since 1970.
    init(wholeMilliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(wholeMilliseconds) / 1000)
    }
}
