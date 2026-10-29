import FichaCore
import Foundation
internal import GRDB

// A restore on a device that syncs (ADR 0017): it turns sync off, and it
// stays off across launches, so that the next sync doesn't bring back what
// the restore undid. A restored copy brings back its own sync tables, as they
// were when it was saved; the restore keeps the device's instead, as they are
// now, but for what waited to be sent and the state of iCloud's engine,
// which go: the restored database holds nothing waiting to sync, whatever
// the copy held. Of what the device knows iCloud holds, it keeps the images
// and sounds alone, which a restore leaves alone in iCloud (`SyncedFiles.swift`),
// so that turning sync on sends only those iCloud lacks. Turning it on then
// replaces the cards iCloud holds with this device's that sync
// (`SelectiveSync.swift`): the device sends them into a cards' zone it makes,
// named for the restore, and deletes the one it leaves; each other device
// that last synced in an older zone takes them in place of its own that sync
// (`Sync`), saving a copy of its cards first, and dropping every row that
// syncs, as `dropEverythingThatSyncs(in:)` says. The cards that don't sync,
// on either side, stay where they are.

/// What a device keeps of its sync through a restore, in place of the
/// restored copy's: how sync stands, with the switch turned off, and what it
/// knows iCloud holds of the images and sounds.
struct SyncKeptThroughARestore {
    let standing: SyncStandingKept
    /// What iCloud said last of each image and sound it holds, as far as the
    /// device knows, by its record's name.
    let filesInICloud: [(name: String, systemFields: Data)]

    /// What the device whose database is `db` keeps, before the restore
    /// replaces it.
    init(in db: Database) throws {
        standing = try SyncStandingKept(in: db)
        filesInICloud = try Row.fetchAll(
            db, sql: "SELECT name, systemFields FROM syncRecord WHERE zone = ? ORDER BY name",
            arguments: [ICloudZone.files.name]
        ).map { row in (try row.decode(forColumn: "name"), try row.decode(forColumn: "systemFields")) }
    }

    /// Keeps it in `db`, a restored copy migrated to this version, in place
    /// of the copy's own: nothing waits to be sent or to be applied, and of
    /// what iCloud said of each record, only the images' and sounds' stay.
    func keep(in db: Database) throws {
        try standing.keep(in: db)
        try db.execute(sql: "DELETE FROM syncPending")
        try db.execute(sql: "DELETE FROM syncIncoming")
        try db.execute(sql: "DELETE FROM syncRecord")
        for file in filesInICloud {
            try FichaData.keep(file.systemFields, of: ICloudRecordID(name: file.name, zone: .files), in: db)
        }
    }
}

/// Drops every row that syncs, in a write that records nothing to send, as a
/// device takes a restore's cards in place of its own: the cards that sync
/// (`SelectiveSync.swift`), their review log, the captures that sync and the
/// tags, with what waited to be sent and when each field of them last
/// changed. The cards that don't sync stay, with their review log, the
/// captures tied to them and those they were approved from, none of which
/// the restore's copy brings. The settings that decide progress and the
/// choice of what syncs stay, as their rows are never deleted, but with no
/// time of change, so that the restore's take their place as they come.
/// Returns the images and sounds the cards dropped used, for the device to
/// remove those iCloud doesn't hold: those it holds stay, for the restore's
/// cards that use them.
func dropEverythingThatSyncs(in db: Database) throws -> FileNames {
    var used = FileNames()
    used.images = try namesSynced(ImageName.self, in: db)
    used.sounds = try namesSynced(SoundName.self, in: db)
    let (card, capture) = (SyncedRow.RecordType.card.rawValue, SyncedRow.RecordType.capture.rawValue)
    let syncing = "SELECT id FROM card WHERE \(cardSyncs(tags: "card.tags"))"
    let untied = """
        SELECT id FROM capture WHERE expandsCardId IS NULL AND followsUpCardId IS NULL
            AND id NOT IN (SELECT captureId FROM card WHERE captureId IS NOT NULL)
        """
    try db.execute(
        sql: """
            DELETE FROM reviewLog WHERE cardId IN (\(syncing));
            UPDATE capture SET expandsCardId = NULL WHERE expandsCardId IN (\(syncing));
            UPDATE capture SET followsUpCardId = NULL WHERE followsUpCardId IN (\(syncing));
            DELETE FROM syncFieldTime
            WHERE recordType = '\(card)' AND recordName IN (SELECT uuid FROM card WHERE id IN (\(syncing)));
            DELETE FROM card WHERE id IN (\(syncing));
            DELETE FROM syncFieldTime
            WHERE recordType = '\(capture)' AND recordName IN (SELECT uuid FROM capture WHERE id IN (\(untied)));
            DELETE FROM capture WHERE id IN (\(untied));
            DELETE FROM tag;
            DELETE FROM syncFieldTime WHERE recordType NOT IN ('\(card)', '\(capture)');
            DELETE FROM syncPending;
            """)
    return used
}
