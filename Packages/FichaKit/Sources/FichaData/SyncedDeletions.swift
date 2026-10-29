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
// too. A user type deleted on one device leaves its cards with no type on
// the others, as on that one, and a card another device gave it before it
// heard of the deletion has none either (`UserTypes.swift`). A tag is never
// deleted: one with nothing of its own is just a name.

extension Sync {
    /// Takes `deletions`, which other devices made, in one write that records
    /// no change to send back but those the deletions make on this device,
    /// what refers to a row before the row (`deletionRank`); and then removes
    /// the images and sounds of the cards it deleted that no card uses.
    func takeDeletions(_ deletions: [ICloudEvent.RecordDeletion]) throws(EngineError) {
        guard !deletions.isEmpty else {
            return
        }
        let now = engine.now
        let deleted = try engine.writeWithoutRecording { db in
            try deletions.sorted { deletionRank(ofType: $0.type) < deletionRank(ofType: $1.type) }.flatMap {
                deletion in
                try receiveDeletion(of: deletion.id, type: deletion.type, at: now, in: db)
            }
        }
        engine.removeFilesNoCardUses(images: Set(deleted.flatMap(\.images)), sounds: Set(deleted.flatMap(\.sounds)))
    }

    /// Settles the deletions iCloud's engine sent: one iCloud took, or whose
    /// record it no longer holds, stops waiting; one it refused for another
    /// reason keeps waiting, for the next time the database changes, as
    /// `deletionsThatWent()` says.
    func settleSentDeletions(_ sent: ICloudEvent.SentRecordZoneChanges) throws(EngineError) {
        let gone = sent.deletionsThatWent()
        guard !gone.isEmpty else {
            return
        }
        try engine.writeWithoutTelling { db in
            for id in gone {
                try forgetDeletion(of: id, in: db)
            }
        }
    }

    /// Takes the deletion behind each of `failures`, records iCloud didn't
    /// save, that iCloud no longer holds because another device deleted it:
    /// a deletion wins. Returns the others, for `retry`.
    func takeDeletionsBehind(_ failures: [ICloudEvent.FailedRecordSave]) throws(EngineError)
        -> [ICloudEvent.FailedRecordSave]
    {
        try takeDeletions(
            failures.filter(\.lostToADeletion).map {
                ICloudEvent.RecordDeletion(id: $0.record.id, type: $0.record.type)
            })
        return failures.filter { !$0.lostToADeletion }
    }
}

extension ICloudEvent.SentRecordZoneChanges {
    /// The records whose deletion went: those iCloud deleted, and those whose
    /// zone or record it no longer had, which left all the same. A deletion
    /// iCloud refused for another reason is logged, and keeps waiting, as
    /// one the engine tries again itself does.
    func deletionsThatWent() -> [ICloudRecordID] {
        var gone = deletedRecordIDs
        for (id, error) in failedRecordDeletes {
            switch error {
            case .unknownItem, .zoneNotFound, .userDeletedZone:
                gone.append(id)
            case .retriedByTheEngine:
                break
            case .serverRecordChanged, .quotaExceeded, .other:
                syncLogger.error(
                    "iCloud didn't delete the record \(id.name, privacy: .public): \(String(describing: error))")
            }
        }
        return gone
    }
}

extension ICloudEvent.FailedRecordSave {
    /// Whether iCloud didn't save it because another device deleted it, and
    /// that deletion wins: iCloud no longer holds the record, and its row is
    /// one that's deleted for good (`deletionRank`).
    fileprivate var lostToADeletion: Bool {
        error == .unknownItem && SyncedRow.RecordType(rawValue: record.type)?.deletionRank != nil
    }
}

extension SyncedRow.RecordType {
    /// Where a deletion of a row of this type comes among those a device
    /// takes at once: what refers to a row before the row, so that the device
    /// sends again only what the deleting device didn't delete. Nil for a row
    /// that's never deleted for good, which goes again when iCloud lacks its
    /// record: a tag is just a name once it has nothing of its own.
    fileprivate var deletionRank: Int? {
        switch self {
        case .reviewLogEntry: 0
        case .card: 1
        case .capture: 2
        case .userType: 3
        default: nil
        }
    }
}

/// The `deletionRank` of a record of `type`, or the last place, `Int.max`,
/// for a row that's never deleted for good or a type this version of Ficha
/// doesn't know.
private func deletionRank(ofType type: String) -> Int {
    SyncedRow.RecordType(rawValue: type)?.deletionRank ?? .max
}

/// Takes the deletion of the record with this ID, of `type`, which another
/// device made, at `time`: forgets it as one iCloud took, in case this device
/// deleted the row too, and deletes the row it held, if the device holds it.
/// Returns the card it deleted, if it was one, for its images and sounds.
private func receiveDeletion(of id: ICloudRecordID, type: String, at time: Date, in db: Database) throws -> [Card] {
    try forgetDeletion(of: id, in: db)
    guard id.zone == .cards else {
        return []
    }
    let row: SyncedRow
    do {
        row = try SyncedRow(recordType: type, recordName: id.name)
    } catch {
        syncLogger.error(
            "A deletion of type \(type, privacy: .public) from iCloud can't be read: \(String(describing: error))")
        return []
    }
    switch row {
    case .card(let uuid):
        return try deleteCard(deletedOnAnotherDevice: uuid, at: time, in: db).map { [$0] } ?? []
    case .capture(let uuid):
        try deleteCapture(deletedOnAnotherDevice: uuid, in: db)
    case .reviewLogEntry(let uuid):
        try db.execute(sql: "DELETE FROM reviewLog WHERE uuid = ?", arguments: [uuid.uuidString])
    case .userType(let uuid):
        // Its cards' change isn't sent: the deleting device sent its own.
        try db.execute(sql: "DELETE FROM userType WHERE uuid = ?", arguments: [uuid.uuidString])
        try forgetType(uuid, in: db)
    default:
        // A row that's never deleted for good (`deletionRank`).
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
    let entries = try rows(of: .reviewLog, as: .reviewLogEntry, where: "cardId = ?", cardID, in: db)
    let expansions = try rows(of: .captures, as: .capture, where: "expandsCardId = ?", cardID, in: db)
    let followUps = try rows(of: .captures, as: .capture, where: "followsUpCardId = ?", cardID, in: db)
    let card = try deleteCard(cardID, in: db)
    for entry in entries where try systemFields(of: entry.recordID, in: db) != nil {
        try waitToBeSent(entry, as: .deleted, in: db)
    }
    for (captures, field) in [(expansions, SyncedField.expandedCard), (followUps, .followedUpCard)] {
        for capture in captures {
            try stamp([field: time], of: capture, in: db)
            try waitToBeSent(capture, as: .saved, in: db)
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
    let approved = try rows(of: .cards, as: .card, where: "captureId = ?", captureID, in: db)
    try db.execute(sql: "UPDATE card SET captureId = NULL WHERE captureId = ?", arguments: [captureID])
    try db.execute(sql: "DELETE FROM capture WHERE id = ?", arguments: [captureID])
    for card in approved {
        try waitToBeSent(card, as: .saved, in: db)
    }
}

/// The rows of `table`, each of `type`, for which `condition` holds with
/// `argument`, as they sync.
private func rows(
    of table: SyncedTable, as type: SyncedRow.RecordType, where condition: String, _ argument: Int64,
    in db: Database
) throws -> [SyncedRow] {
    try String.fetchAll(db, sql: "SELECT uuid FROM \(table.name) WHERE \(condition)", arguments: [argument]).map {
        try SyncedRow(recordType: type.rawValue, recordName: $0)
    }
}

/// Leaves `row` waiting to be sent, as `kind` says, in place of its change
/// before, while sync is on: for a change this device makes as it takes
/// another device's deletion, in a write that doesn't record its changes. The
/// database's triggers do the same in a write that does (`wait` in `Schema`'s
/// v21), whose SQL a migration keeps as it was, so it can't be shared.
private func waitToBeSent(_ row: SyncedRow, as kind: ChangeToSend.Kind, in db: Database) throws {
    try db.execute(
        sql: "DELETE FROM syncPending WHERE recordType = ? AND recordName = ?",
        arguments: [row.recordType.rawValue, row.recordName])
    try db.execute(
        sql: """
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT ?, ?, ? WHERE (SELECT isOn FROM syncDevice)
            """,
        arguments: [row.recordType.rawValue, row.recordName, kind == .deleted])
}

/// Forgets the deletion of the row the record with this ID held, which
/// iCloud no longer holds: it stops waiting, and the device forgets what
/// iCloud said of the record and a version of it that waited.
private func forgetDeletion(of id: ICloudRecordID, in db: Database) throws {
    if let sequence = try pendingDeletion(of: id, in: db) {
        try db.execute(sql: "DELETE FROM syncPending WHERE id = ?", arguments: [sequence])
    }
    try keep(nil, of: id, in: db)
    try dropWaitingRecord(of: id, in: db)
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
