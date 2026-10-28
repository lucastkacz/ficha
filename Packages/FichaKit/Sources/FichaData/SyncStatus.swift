import FichaCore
import Foundation
internal import GRDB

// How sync stands on this device (ADR 0017), as Settings' Sync tab and the
// menu read it: the switch, and why it's off; whether the device is signed
// into iCloud; whether iCloud is full; and when the device last synced. The
// device keeps it in its database, which never syncs it (`Schema`'s "v24 how
// sync stands"), so it holds across launches, and across a restore, which
// keeps the device's own and turns the switch off (`SyncedRestore.swift`).
// This file is the one that writes it. A change to the switch, the account or
// a full iCloud tells every engine on the database, as a change to the cards
// does, so the app's sync and the menu follow it; when the device last synced
// doesn't, since it changes at every sync. The file also says whether what
// changes goes up to iCloud, and from what weight Ficha says what goes up
// weighs, as the Sync tab and the Import sheet both read them.

/// How sync stands on this device.
public struct SyncStatus: Sendable, Equatable {
    /// Why Settings' "Sync with iCloud" switch is off, or nil while it's on.
    public let offBecause: SyncOffReason?
    /// Whether the device is signed into iCloud, or nil until the app first
    /// asked, as in a database only the CLI opened.
    public let hasICloudAccount: Bool?
    /// Whether iCloud was full when the device last sent something: the
    /// changes that didn't fit wait until it isn't.
    public let iCloudIsFull: Bool
    /// When the device last synced, as iCloud answered it: a fetch the app
    /// asked for ended without an error, a fetch brought what the other
    /// devices changed, or iCloud took what the device sent. Nil before it
    /// first did.
    public let lastSynced: Date?

    /// Whether Settings' switch is on.
    public var isOn: Bool {
        offBecause == nil
    }

    /// Whether what changes goes up to the user's iCloud: the switch is on
    /// and the device is signed into iCloud, as far as the app heard.
    var sendsToICloud: Bool {
        isOn && hasICloudAccount == true
    }
}

/// `bytes`, what images and sounds going up to the user's iCloud weigh, when
/// it's enough for Ficha to say so, 100 MB or more, or nil under that: the
/// Sync tab's line while sync is off, and the Import sheet's while it's on
/// (#317's decision of 2026-10-28, our own: Anki never warns). 100 MB is
/// 100,000,000 bytes, as Finder writes sizes.
func weightWorthSaying(_ bytes: Int64) -> Int64? {
    bytes >= 100_000_000 ? bytes : nil
}

/// Why Settings' "Sync with iCloud" switch is off. Its raw value is how the
/// database keeps it, so it never changes.
public enum SyncOffReason: String, Sendable, Equatable {
    /// The user turned it off.
    case user
    /// The user deleted Ficha's data in iCloud's settings, which turns sync
    /// off with the cards kept, so that nothing goes back up until the user
    /// says so: turning it on sends everything.
    case purge
    /// The user restored a backup, or another copy Ficha saved, which turns
    /// sync off, so that the next sync doesn't bring back what the restore
    /// undid: turning it on replaces the cards iCloud holds with this
    /// device's, which the other devices then take in place of theirs.
    case restore
}

/// A stretch of time with sync on, from when Settings' switch turns on until
/// it next turns off, however briefly. The app's engine of iCloud's runs in
/// the stretch it started in, and stops at its end: it may have told of
/// changes while sync was off, which `Sync` left aside, so what it tells
/// after would skip them. `Sync` leaves aside what an engine of a stretch
/// that ended tells (`Sync.handle(_:from:startedIn:)`), and the next engine
/// starts from the state saved before the off, fetching them again.
public struct SyncStretch: Sendable, Equatable {
    /// How many times sync turned off before the stretch began.
    let offsBefore: Int
}

extension Engine {
    /// The stretch of time sync is on now, or nil while it's off.
    func syncStretch() throws(EngineError) -> SyncStretch? {
        try read { db in
            guard let device = try Row.fetchOne(db, sql: "SELECT isOn, timesTurnedOff FROM syncDevice") else {
                throw unreadable("The database doesn't say whether sync is on")
            }
            let isOn: Bool = try device.decode(forColumn: "isOn")
            return isOn ? SyncStretch(offsBefore: try device.decode(forColumn: "timesTurnedOff")) : nil
        }
    }

    /// How sync stands on this device now.
    public func syncStatus() throws(EngineError) -> SyncStatus {
        try read { db in
            guard
                let device = try Row.fetchOne(
                    db, sql: "SELECT isOn, offBecause, hasICloudAccount, iCloudIsFull, lastSyncedAt FROM syncDevice")
            else {
                throw unreadable("The database doesn't keep how sync stands on this device")
            }
            return SyncStatus(
                offBecause: try offReason(
                    isOn: device.decode(forColumn: "isOn"), device.decode(forColumn: "offBecause")),
                hasICloudAccount: try device.decode(forColumn: "hasICloudAccount"),
                iCloudIsFull: try device.decode(forColumn: "iCloudIsFull"),
                lastSynced: try device.decode(forColumn: "lastSyncedAt"))
        }
    }

    /// Keeps whether the device is signed into iCloud, as the app asks iCloud
    /// at launch and whenever the account changes, whether sync is on or not.
    func noteICloudAccount(signedIn: Bool) throws(EngineError) {
        try note(.hasICloudAccount, signedIn)
    }

    /// Keeps whether iCloud is full, as what the device sent last says.
    func noteICloudIsFull(_ isFull: Bool) throws(EngineError) {
        try note(.iCloudIsFull, isFull)
    }

    /// Whether the device knows iCloud is full.
    func iCloudIsFull() throws(EngineError) -> Bool {
        try read(FichaData.iCloudIsFull(in:))
    }

    /// Keeps that the device synced now, without telling the other engines:
    /// it changes at every sync, and nothing else follows it.
    func noteSynced() throws(EngineError) {
        let now = time.now
        try writeWithoutTelling { db in
            try db.execute(sql: "UPDATE syncDevice SET lastSyncedAt = ?", arguments: [now])
        }
    }

    /// Sets `flag` to `value`, telling the other engines only when it
    /// changed, so that a sync that says what it said before changes nothing
    /// else.
    private func note(_ flag: SyncDeviceFlag, _ value: Bool) throws(EngineError) {
        if try writeWithoutTelling({ db in try FichaData.note(flag, value, in: db) }) {
            databaseChanges.post()
        }
    }
}

/// What the device keeps of how sync stands that sync notes as yes or no,
/// each by its column.
private enum SyncDeviceFlag: String {
    case hasICloudAccount
    case iCloudIsFull
}

/// Keeps whether iCloud is full, in `db`'s write, as
/// `Engine.noteICloudIsFull(_:)` does in a write of its own.
func noteICloudIsFull(_ isFull: Bool, in db: Database) throws {
    _ = try note(.iCloudIsFull, isFull, in: db)
}

/// Sets `flag` to `value`, and returns whether it changed.
private func note(_ flag: SyncDeviceFlag, _ value: Bool, in db: Database) throws -> Bool {
    guard try Bool.fetchOne(db, sql: "SELECT \(flag.rawValue) FROM syncDevice") != value else {
        return false
    }
    try db.execute(sql: "UPDATE syncDevice SET \(flag.rawValue) = ?", arguments: [value])
    return true
}

/// Whether the device knows iCloud is full.
func iCloudIsFull(in db: Database) throws -> Bool {
    guard let isFull = try Bool.fetchOne(db, sql: "SELECT iCloudIsFull FROM syncDevice") else {
        throw unreadable("The database doesn't say whether iCloud is full")
    }
    return isFull
}

/// Why sync is off, or nil while it's on.
func syncOffReason(in db: Database) throws -> SyncOffReason? {
    guard let device = try Row.fetchOne(db, sql: "SELECT isOn, offBecause FROM syncDevice") else {
        throw unreadable("The database doesn't say whether sync is on")
    }
    return try offReason(isOn: device.decode(forColumn: "isOn"), device.decode(forColumn: "offBecause"))
}

/// Turns sync on, unless it's on already: a stretch of it begins
/// (`SyncStretch`). After a purge, the device forgets when it last synced:
/// iCloud no longer holds what it synced then, so the Sync tab says it hasn't
/// synced until it does again. After a restore, it keeps it: it synced then,
/// and turning sync on replaces what iCloud holds with what it holds now.
func switchSyncOn(in db: Database) throws {
    guard let reason = try syncOffReason(in: db) else {
        return
    }
    switch reason {
    case .user, .restore:
        break
    case .purge:
        try db.execute(sql: "UPDATE syncDevice SET lastSyncedAt = NULL")
    }
    try db.execute(sql: "UPDATE syncDevice SET isOn = 1, offBecause = NULL")
}

/// Turns sync off, because of `reason`, unless it's off already, which ends
/// the stretch of it (`SyncStretch`): nothing waits to be sent but the
/// deletions, which turning it on sends with every row as it is then.
func switchSyncOff(because reason: SyncOffReason, in db: Database) throws {
    try db.execute(
        sql: "UPDATE syncDevice SET isOn = 0, offBecause = ?, timesTurnedOff = timesTurnedOff + 1 WHERE isOn",
        arguments: [reason.rawValue])
    try db.execute(sql: "DELETE FROM syncPending WHERE NOT isDeletion")
}

/// How sync stands on the device, as a restore keeps it in place of the
/// copy's own, which the copy brought back as it stood when it was saved.
struct SyncStandingKept {
    let wasOn: Bool
    let hasICloudAccount: Bool?
    let iCloudIsFull: Bool
    let lastSynced: Date?
    let timesTurnedOff: Int
    /// The cards' zone the device syncs in, as the database keeps it, and
    /// since when (`ICloudZones.swift`).
    let cardsZone: String?
    let cardsZoneSince: Date?

    /// How sync stands on the device whose database is `db`, before the
    /// restore replaces it.
    init(in db: Database) throws {
        guard
            let device = try Row.fetchOne(
                db,
                sql: """
                    SELECT isOn, hasICloudAccount, iCloudIsFull, lastSyncedAt, timesTurnedOff, cardsZone,
                        cardsZoneSince
                    FROM syncDevice
                    """)
        else {
            throw unreadable("The database doesn't keep how sync stands on this device")
        }
        wasOn = try device.decode(forColumn: "isOn")
        hasICloudAccount = try device.decode(forColumn: "hasICloudAccount")
        iCloudIsFull = try device.decode(forColumn: "iCloudIsFull")
        lastSynced = try device.decode(forColumn: "lastSyncedAt")
        timesTurnedOff = try device.decode(forColumn: "timesTurnedOff")
        cardsZone = try device.decode(forColumn: "cardsZone")
        cardsZoneSince = try device.decode(forColumn: "cardsZoneSince")
    }

    /// Keeps it in `db`, a restored copy, with the switch off because of the
    /// restore, which ends the stretch of sync being on, if it was, and no
    /// state of iCloud's engine: the next engine starts from nothing.
    func keep(in db: Database) throws {
        try db.execute(
            sql: """
                UPDATE syncDevice SET isOn = 0, offBecause = ?, engineState = NULL, hasICloudAccount = ?,
                    iCloudIsFull = ?, lastSyncedAt = ?, timesTurnedOff = ?, cardsZone = ?, cardsZoneSince = ?
                """,
            arguments: [
                SyncOffReason.restore.rawValue, hasICloudAccount, iCloudIsFull, lastSynced,
                timesTurnedOff + (wasOn ? 1 : 0), cardsZone, cardsZoneSince,
            ])
    }
}

/// Why the switch is off, as the database keeps it beside whether it's on,
/// or nil while it's on; an error when the two disagree, or for a reason
/// this version of Ficha doesn't know.
private func offReason(isOn: Bool, _ reason: String?) throws -> SyncOffReason? {
    switch (isOn, reason) {
    case (true, nil):
        return nil
    case (false, let reason?):
        guard let known = SyncOffReason(rawValue: reason) else {
            throw unreadable("Sync is off for a reason, \(reason), that this version of Ficha doesn't know")
        }
        return known
    case (true, _?), (false, nil):
        throw unreadable("The database doesn't agree with itself on whether sync is on")
    }
}
