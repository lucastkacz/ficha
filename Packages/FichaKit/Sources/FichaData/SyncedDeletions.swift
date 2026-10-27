import FichaCore
import Foundation
internal import GRDB

// How a deletion syncs (ADR 0017): a card, a capture or an entry of the
// review log deleted on one device is deleted on the others, and wins over
// what they changed of it meanwhile. A device takes another's deletion as it
// takes its own on one device: a card goes with its review log, and the
// captures that expand it or follow it up stay in the inbox as captures; the
// cards approved from a capture stay. What that changes on the device, which
// iCloud may hold as it was, is sent like any change of its own, so that no
// device keeps waiting for a row that's gone, and iCloud keeps no review of a
// card that's gone. A record iCloud no longer holds, which the device sent
// as it changed its row, was deleted on another device: the row goes here
// too. A tag is never deleted: one with nothing of its own is just a name.

extension Sync {
    /// Deletes what other devices deleted, as iCloud says in `deletions`, in
    /// one write that records no change to send back but those the deletions
    /// make on this device, and then the images and sounds of the cards it
    /// deleted that no card uses.
    func receiveDeletions(_ deletions: [ICloudEvent.RecordDeletion]) throws(EngineError) {
        guard !deletions.isEmpty else {
            return
        }
        let now = engine.now
        let deleted = try engine.writeWithoutRecording { db in
            try deletions.sorted { $0.deletingRank < $1.deletingRank }.flatMap { deletion in
                try receiveDeletion(of: deletion.id, type: deletion.type, at: now, in: db)
            }
        }
        engine.removeFilesNoCardUses(images: Set(deleted.flatMap(\.images)), sounds: Set(deleted.flatMap(\.sounds)))
    }

    /// Settles the deletions iCloud's engine sent, and the records it sent
    /// that iCloud no longer holds because another device deleted them, whose
    /// rows go here too: a deletion wins. A deletion iCloud took, or whose
    /// record it no longer holds, stops waiting; one it refused for another
    /// reason keeps waiting, for the next time the database changes. Returns
    /// the records iCloud didn't save for any other reason, for `settle` to
    /// send again.
    func settleDeletions(_ sent: ICloudEvent.SentRecordZoneChanges) throws(EngineError)
        -> [ICloudEvent.FailedRecordSave]
    {
        var gone = sent.deletedRecordIDs
        for (id, error) in sent.failedRecordDeletes {
            switch error {
            case .unknownItem, .zoneNotFound:
                gone.append(id)
            case .retriedByTheEngine:
                break
            case .serverRecordChanged, .quotaExceeded, .other:
                syncLogger.error("iCloud didn't delete a record: \(String(describing: error), privacy: .public)")
            }
        }
        if !gone.isEmpty {
            try engine.writeWithoutTelling { db in
                for id in gone {
                    try forgetDeletion(of: id, in: db)
                }
            }
        }
        let deletedElsewhere = sent.failedRecordSaves.filter(\.lostToADeletion)
        if !deletedElsewhere.isEmpty {
            let now = engine.now
            let deleted = try engine.writeWithoutRecording { db in
                try deletedElsewhere.flatMap { failure in
                    try receiveDeletion(of: failure.record.id, type: failure.record.type, at: now, in: db)
                }
            }
            engine.removeFilesNoCardUses(
                images: Set(deleted.flatMap(\.images)), sounds: Set(deleted.flatMap(\.sounds)))
        }
        return sent.failedRecordSaves.filter { !$0.lostToADeletion }
    }
}

extension ICloudEvent.FailedRecordSave {
    /// Whether iCloud didn't save it because another device deleted it, and
    /// that deletion wins: iCloud no longer holds the record, and its row is
    /// one that's deleted for good, a card, a capture or an entry of the
    /// review log. Any other row is never deleted, or goes again when
    /// iCloud lacks it: a tag is just a name once it has nothing of its own.
    fileprivate var lostToADeletion: Bool {
        switch SyncedRow.RecordType(rawValue: record.type) {
        case .card?, .capture?, .reviewLogEntry?: error == .unknownItem
        default: false
        }
    }
}

/// Takes the deletion of the record with this ID, of `type`, which another
/// device made, at `time`: forgets it as one iCloud took, in case this device
/// deleted the row too, and deletes the row it held, if the device holds it.
/// Returns the card it deleted, if it was one, for its images and sounds.
private func receiveDeletion(of id: ICloudRecordID, type: String, at time: Date, in db: Database) throws -> [Card] {
    try forgetDeletion(of: id, in: db)
    guard id.zone == .cards, let uuid = UUID(uuidString: id.name) else {
        return []
    }
    switch SyncedRow.RecordType(rawValue: type) {
    case .card?:
        return try deleteCard(deletedOnAnotherDevice: uuid, at: time, in: db).map { [$0] } ?? []
    case .capture?:
        try deleteCapture(deletedOnAnotherDevice: uuid, in: db)
    case .reviewLogEntry?:
        try db.execute(sql: "DELETE FROM reviewLog WHERE uuid = ?", arguments: [uuid.uuidString])
    default:
        // A row that's never deleted for good.
        break
    }
    return []
}

/// Deletes the card with this ID, which another device deleted, as
/// `deleteCard(_:in:)` does on one device, and returns it, or nil when the
/// device doesn't hold it. What that changes here waits to be sent, as a
/// change of this device's, at `time`: the deletion of each entry of its
/// review log iCloud holds, which another device may have sent before the
/// deletion reached it, and each capture that let go of it, which a device
/// that holds the capture without the card would otherwise wait on.
private func deleteCard(deletedOnAnotherDevice uuid: UUID, at time: Date, in db: Database) throws -> Card? {
    guard let cardID = try Int64.fetchOne(db, sql: "SELECT id FROM card WHERE uuid = ?", arguments: [uuid.uuidString])
    else {
        return nil
    }
    let entries = try rows(of: SyncedTable.reviewLog, where: "cardId = ?", cardID, in: db)
    let expansions = try rows(of: SyncedTable.captures, where: "expandsCardId = ?", cardID, in: db)
    let followUps = try rows(of: SyncedTable.captures, where: "followsUpCardId = ?", cardID, in: db)
    let card = try deleteCard(cardID, in: db)
    for entry in entries where try systemFields(of: entry.recordID, in: db) != nil {
        try waitToBeSent(entry, deleted: true, in: db)
    }
    for (captures, field) in [(expansions, SyncedField.expandedCard), (followUps, .followedUpCard)] {
        for capture in captures {
            try stamp([field: time], of: capture, in: db)
            try waitToBeSent(capture, deleted: false, in: db)
        }
    }
    return card
}

/// Deletes the capture with this ID, which another device deleted, as the
/// review panel's ⌘Z deletes a follow-up, if the device holds it. The cards
/// approved from it here meanwhile stay, from no capture, and wait to be sent
/// again, so that a device that holds them waiting for the capture takes
/// them.
private func deleteCapture(deletedOnAnotherDevice uuid: UUID, in db: Database) throws {
    guard
        let captureID = try Int64.fetchOne(
            db, sql: "SELECT id FROM capture WHERE uuid = ?", arguments: [uuid.uuidString])
    else {
        return
    }
    let approved = try rows(of: SyncedTable.cards, where: "captureId = ?", captureID, in: db)
    try db.execute(sql: "UPDATE card SET captureId = NULL WHERE captureId = ?", arguments: [captureID])
    try db.execute(sql: "DELETE FROM capture WHERE id = ?", arguments: [captureID])
    for card in approved {
        try waitToBeSent(card, deleted: false, in: db)
    }
}

/// The rows of `table` for which `condition` holds with `argument`, as they
/// sync.
private func rows(of table: SyncedTable, where condition: String, _ argument: Int64, in db: Database) throws
    -> [SyncedRow]
{
    try String.fetchAll(db, sql: "SELECT uuid FROM \(table.name) WHERE \(condition)", arguments: [argument]).map {
        name in
        guard let uuid = UUID(uuidString: name) else {
            throw unreadable("A row that syncs has an ID that isn't a UUID")
        }
        return table.syncedRow(uuid)
    }
}

/// Leaves `row` waiting to be sent, saved or deleted, in place of its change
/// before, while sync is on, as the database's triggers do in a write that
/// records its changes: for a change this device makes as it takes another
/// device's deletion.
private func waitToBeSent(_ row: SyncedRow, deleted: Bool, in db: Database) throws {
    try db.execute(
        sql: "DELETE FROM syncPending WHERE recordType = ? AND recordName = ?",
        arguments: [row.recordType.rawValue, row.recordName])
    try db.execute(
        sql: """
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT ?, ?, ? WHERE (SELECT isOn FROM syncDevice)
            """,
        arguments: [row.recordType.rawValue, row.recordName, deleted])
}

/// Forgets the deletion of the row the record with this ID held, which
/// iCloud no longer holds: it stops waiting, and the device forgets what
/// iCloud said of the record and a version of it that waited.
private func forgetDeletion(of id: ICloudRecordID, in db: Database) throws {
    if let sequence = try pendingDeletion(of: id, in: db) {
        try db.execute(sql: "DELETE FROM syncPending WHERE id = ?", arguments: [sequence])
    }
    try keep(nil, of: id, in: db)
    try db.execute(sql: "DELETE FROM syncIncoming WHERE zone = ? AND name = ?", arguments: [id.zone.name, id.name])
}

/// The place among the changes recorded of the deletion of the row the
/// record with this ID held, which waits to be sent, or nil when none waits.
/// A row that's deleted is named by its ID unique across devices, as its
/// record is.
func pendingDeletion(of id: ICloudRecordID, in db: Database) throws -> Int64? {
    let deletions = try Row.fetchAll(
        db, sql: "SELECT id, recordType, recordName FROM syncPending WHERE isDeletion AND recordName = ?",
        arguments: [id.name])
    for deletion in deletions {
        let row = try SyncedRow(
            recordType: deletion.decode(forColumn: "recordType"), recordName: deletion.decode(forColumn: "recordName"))
        if row.recordID == id {
            return try deletion.decode(forColumn: "id")
        }
    }
    return nil
}

extension ICloudEvent.RecordDeletion {
    /// Its place among the deletions of a fetch as they're applied: what
    /// refers to a row before the row, so that a device sends again only what
    /// the deleting device didn't delete: the review log first, then cards,
    /// then captures, then any other.
    fileprivate var deletingRank: Int {
        switch SyncedRow.RecordType(rawValue: type) {
        case .reviewLogEntry?: 0
        case .card?: 1
        case .capture?: 2
        default: 3
        }
    }
}
