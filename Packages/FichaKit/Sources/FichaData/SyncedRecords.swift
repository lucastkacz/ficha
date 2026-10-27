import CryptoKit
import FichaCore
import Foundation
internal import GRDB

// How each row that syncs travels as a record in iCloud (ADR 0017): its
// record's ID, its record as the row is now, and how a record from iCloud
// changes the row. Of each field that keeps when it last changed, the latest
// change wins, and the rest merges; a row new to the device comes in whole.
// Cards, captures and the review log are described by `SyncedTable`, tags by
// `SyncedTags.swift`, and the settings that decide progress by
// `SyncedProgressSettings.swift`.

extension SyncedRow {
    /// The ID of the record iCloud keeps the row as, in the cards' zone:
    /// named by the row's ID unique across devices, a tag by its name's
    /// SHA-256 after "tag-", since a record's name is ASCII, up to 255
    /// characters, and a tag's name can be anything, and the settings that
    /// decide progress by their type.
    var recordID: ICloudRecordID {
        switch self {
        case .card(let id), .capture(let id), .reviewLogEntry(let id):
            ICloudRecordID(name: id.uuidString, zone: .cards)
        case .tag(let name):
            ICloudRecordID(
                name: "tag-" + SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined(),
                zone: .cards)
        case .progressSettings:
            ICloudRecordID(name: recordName, zone: .cards)
        }
    }

    /// The row `record`, from iCloud, holds: by its type and name, or a tag
    /// by the name it holds. It throws for a type this version of Ficha
    /// doesn't know.
    init(of record: ICloudRecord) throws {
        if record.type == RecordType.tag.rawValue {
            self = .tag(try record.text(TagKey.name))
        } else {
            try self.init(recordType: record.type, recordName: record.id.name)
        }
    }
}

/// The row that syncs as the record with this ID, as the device holds it
/// now, or nil when it holds none: a card, a capture or an entry of the
/// review log by its ID, the settings that decide progress, or a tag, which
/// needn't have a row of its own, by the name whose record it is, among
/// those that wait to be sent or that have something of their own or had.
func syncedRow(named id: ICloudRecordID, in db: Database) throws -> SyncedRow? {
    guard id.zone == .cards else {
        return nil
    }
    if let uuid = UUID(uuidString: id.name) {
        return try SyncedTable.all.first { try $0.holdsRow(with: uuid, in: db) }.map { $0.syncedRow(uuid) }
    }
    if id == SyncedRow.progressSettings.recordID {
        return .progressSettings
    }
    let tags = try String.fetchAll(
        db,
        sql: """
            SELECT recordName FROM syncPending WHERE recordType = 'tag'
            UNION SELECT name FROM tag
            UNION SELECT recordName FROM syncFieldTime WHERE recordType = 'tag'
            """)
    return tags.map(SyncedRow.tag).first { $0.recordID == id }
}

/// The record `row` syncs as, as it is now, with what iCloud said of it last,
/// or nil when the device no longer holds it.
func record(of row: SyncedRow, in db: Database) throws -> ICloudRecord? {
    let record: ICloudRecord? =
        switch row {
        case .card(let id): try SyncedTable.cards.record(ofRowWith: id, in: db)
        case .capture(let id): try SyncedTable.captures.record(ofRowWith: id, in: db)
        case .reviewLogEntry(let id): try SyncedTable.reviewLog.record(ofRowWith: id, in: db)
        case .tag(let name): try tagRecord(name, in: db)
        case .progressSettings: try progressSettingsRecord(in: db)
        }
    return try record?.with(systemFields: systemFields(of: row.recordID, in: db))
}

/// Applies `record`, from iCloud, to `row`, the row it holds: the row takes
/// each field whose change in the record is the latest, or comes in whole.
/// Returns false, changing nothing, when the record refers to a row the
/// device doesn't hold yet, such as a card's capture, for it to wait.
private func apply(_ record: ICloudRecord, to row: SyncedRow, in db: Database) throws -> Bool {
    switch row {
    case .card(let id): try SyncedTable.cards.apply(record, toRowWith: id, in: db)
    case .capture(let id): try SyncedTable.captures.apply(record, toRowWith: id, in: db)
    case .reviewLogEntry(let id): try SyncedTable.reviewLog.apply(record, toRowWith: id, in: db)
    case .tag(let name): try applyTag(record, named: name, in: db)
    case .progressSettings: try applyProgressSettings(record, in: db)
    }
}

/// What became of a record from iCloud.
enum Received: Equatable {
    /// The device holds what it holds.
    case applied
    /// It waits, until the row it refers to comes, or a version of Ficha
    /// that can read it.
    case waits
}

/// Applies `record`, from iCloud, as `apply(_:to:in:)` says, in a write that
/// records no change to send, and keeps what iCloud says of it. A record
/// that refers to a row the device doesn't hold yet waits, and so does one
/// this version of Ficha can't read, which the log says: each is tried again
/// whenever records come, until it's applied or a later version of it
/// replaces it.
func receive(_ record: ICloudRecord, in db: Database) throws -> Received {
    var applied = false
    do {
        let row = try SyncedRow(of: record)
        try db.inSavepoint {
            applied = try apply(record, to: row, in: db)
            return applied ? .commit : .rollback
        }
        if applied {
            try keep(record.systemFields, of: record.id, in: db)
            try forgetPendingSave(of: row, whenICloudHolds: record, in: db)
        }
    } catch {
        syncLogger.error(
            "A record of type \(record.type, privacy: .public) from iCloud can't be read, and waits: \(String(describing: error))"
        )
    }
    if applied {
        try db.execute(
            sql: "DELETE FROM syncIncoming WHERE zone = ? AND name = ?",
            arguments: [record.id.zone.name, record.id.name])
        return .applied
    }
    try db.execute(
        sql: """
            INSERT INTO syncIncoming (zone, name, record) VALUES (?, ?, ?)
            ON CONFLICT (zone, name) DO UPDATE SET record = excluded.record
            """,
        arguments: [record.id.zone.name, record.id.name, try JSONEncoder().encode(record)])
    return .waits
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
/// or forgets what it said when it's nil.
func keep(_ systemFields: Data?, of id: ICloudRecordID, in db: Database) throws {
    guard let systemFields else {
        try db.execute(sql: "DELETE FROM syncRecord WHERE zone = ? AND name = ?", arguments: [id.zone.name, id.name])
        return
    }
    try db.execute(
        sql: """
            INSERT INTO syncRecord (zone, name, systemFields) VALUES (?, ?, ?)
            ON CONFLICT (zone, name) DO UPDATE SET systemFields = excluded.systemFields
            """,
        arguments: [id.zone.name, id.name, systemFields])
}

/// Whether a field's change, made at `incoming` on another device, wins over
/// this device's, made at `local`: when it's as late or later. A time that's
/// nil is a field that hasn't changed since its row came in, older than any
/// change. iCloud's wins a tie, so every device ends with what iCloud holds.
func isLatest(_ incoming: Date?, comparedWith local: Date?) -> Bool {
    switch (incoming, local) {
    case (_, nil): true
    case (nil, _?): false
    case (let incoming?, let local?): incoming >= local
    }
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
        case .int?, .double?: throw unreadable("A record from iCloud holds a number where text should be")
        }
    }

    /// The time the field `key` holds, or nil when it holds nothing.
    func time(_ key: String) throws -> Date? {
        switch value(of: key) {
        case nil: return nil
        case .int(let milliseconds)?: return Date(wholeMilliseconds: milliseconds)
        case .string?, .double?: throw unreadable("A record from iCloud holds something else where a time should be")
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
