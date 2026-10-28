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
// replaces the cards iCloud holds with this device's.

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
