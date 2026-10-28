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
// replaces the cards iCloud holds with this device's: the device sends them
// into a cards' zone of its own, and each other device that synced since
// before takes them in place of its own (`Sync`), dropping every row that
// syncs first, as `dropEverythingThatSyncs(in:)` says.

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
/// device takes a restore's cards in place of its own: the cards, their
/// review log, the captures and the tags, with what waited to be sent and
/// when each field last changed. The settings that decide progress stay, as
/// their row is never deleted, but with no time of change, so that the
/// restore's take their place as they come. Returns the images and sounds
/// the rows used, for the device to remove those iCloud doesn't hold: those
/// it holds stay, for the restore's cards that use them.
func dropEverythingThatSyncs(in db: Database) throws -> FilesReferred {
    let referred = try FilesReferred(in: db)
    try db.execute(
        sql: """
            DELETE FROM reviewLog;
            UPDATE capture SET expandsCardId = NULL, followsUpCardId = NULL;
            DELETE FROM card;
            DELETE FROM capture;
            DELETE FROM tag;
            DELETE FROM syncFieldTime;
            DELETE FROM syncPending;
            """)
    return referred
}
