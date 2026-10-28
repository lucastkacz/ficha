import FichaCore
import Foundation
internal import GRDB

// The zones a device syncs in, by their names in iCloud (ADR 0017, #317).
// Inside the device there are two, the cards' and the files', which the rest
// of sync names `ICloudZone.cards` and `ICloudZone.files`, and keeps what it
// knows of iCloud under. In iCloud each has a name of its own:
//
// - Ficha's own zones are "Cards" and "Files". An agent's scratch run of
//   Ficha Dev syncs in zones named after its scratch folder, such as
//   "Cards-agent-317" and "Files-agent-317", in the same database, so that
//   its cards never reach Ficha Dev's: each device leaves alone the zones
//   that aren't its own.
// - The cards have had more than one zone: a device that turns sync on after
//   a restore or a purge starts another, whose name says why, and when for a
//   restore, such as "Cards.restore.1761650000000" (`CardsZone`), since a
//   zone deleted and saved again under its own name reaches the other
//   devices as changed, with no deletion (P16, #316), and a device that
//   sends into it what iCloud said of its records before would take each
//   refusal as a deletion. The files' zone keeps its name.
//
// `Sync` speaks to iCloud's engine through `ICloudInItsZones`, which turns
// one set of names into the other, and leaves out what iCloud tells of any
// other zone. The device keeps which cards' zone it syncs in, and since
// when, in its database, which never syncs it (`Schema`'s "v25 the cards'
// zone in iCloud"). Naming the zones this way is our own.

/// The zones a device syncs in, by their names in iCloud: Ficha's own, or a
/// scratch run's.
public struct ICloudZones: Sendable, Equatable {
    /// What follows "Cards" and "Files" in the zones' names.
    private let suffix: String

    /// Ficha's own zones, "Cards" and "Files", which Ficha Dev and the real
    /// Ficha sync in, each in its own environment of the container.
    public static let ficha = ICloudZones(suffix: "")

    /// The zones of an agent's scratch run of Ficha Dev, whose scratch folder
    /// is `name`, written with letters, digits, `-` and `_` alone, as
    /// `FICHA_DEV_SCRATCH` names it: "Cards-<name>" and "Files-<name>".
    public static func scratch(_ name: String) -> ICloudZones {
        ICloudZones(suffix: "-\(name)")
    }

    /// The files' zone.
    var files: ICloudZone {
        ICloudZone(name: "Files\(suffix)")
    }

    /// The name of the cards' zone `zone` in iCloud: "Cards" and the suffix
    /// for the first, and after them, for another, why and when a device
    /// started it.
    func cards(_ zone: CardsZone) -> ICloudZone {
        ICloudZone(name: ["Cards\(suffix)", zone.nameEnd].compactMap(\.self).joined(separator: "."))
    }

    /// Which of the cards' zones `zone` is, or nil when it isn't one of
    /// these.
    func cardsZone(_ zone: ICloudZone) -> CardsZone? {
        let start = "Cards\(suffix)"
        guard zone.name.hasPrefix(start) else {
            return nil
        }
        let end = zone.name.dropFirst(start.count)
        if end.isEmpty {
            return .first
        }
        guard end.first == "." else {
            return nil
        }
        return CardsZone(nameEnd: end.dropFirst())
    }

    /// Whether `zone` is one of these: the files' zone, or one of the cards'
    /// zones, whichever is the device's now.
    public func contains(_ zone: ICloudZone) -> Bool {
        zone == files || cardsZone(zone) != nil
    }
}

/// One of the zones the cards have had in iCloud, apart from the files'.
/// Every device syncs in the first, until one turns sync on after a restore
/// or a purge, which starts another. The newest, by when it started, is the
/// one every device moves to: the other devices take a restore's cards in
/// place of theirs, and join a purge's, as at an account change (`Sync`).
enum CardsZone: Sendable, Hashable, Comparable {
    /// The first, which no device started on purpose: "Cards".
    case first
    /// One a device started as it turned sync on after `start`, at `time`:
    /// after a restore, when it turned it on, in whole milliseconds since
    /// 1970 by its clock; after a purge, one past the zone the purge deleted
    /// (`afterItsPurge`).
    case started(after: Start, at: Int64)

    /// Why a device started a cards' zone. Its raw value is how its name
    /// and the database say it, so it never changes.
    enum Start: String, Sendable {
        /// The device restored a backup: the other devices take its cards in
        /// place of theirs.
        case restore
        /// The user deleted Ficha's data in iCloud's settings: each device's
        /// cards join the zone.
        case purge
    }

    /// What follows the zone's first part in its name, and how the database
    /// keeps it: nothing for the first, and otherwise why and when it
    /// started, as "restore.1761650000000".
    var nameEnd: String? {
        switch self {
        case .first: nil
        case .started(let start, let time): "\(start.rawValue).\(time)"
        }
    }

    /// The zone started as `nameEnd` says, or nil when it says none.
    init?(nameEnd: Substring) {
        let parts = nameEnd.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Start(rawValue: String(parts[0])), let time = Int64(parts[1]),
            String(time) == parts[1]
        else {
            return nil
        }
        self = .started(after: start, at: time)
    }

    /// The zone each device that heard the user purge this one starts as it
    /// turns sync on again: one past it, newer than it and than every zone
    /// before it, and the same on every device, so that they all land in it,
    /// one by one, and a deletion one made while sync was off still wins, as
    /// in one zone. A restore later than the purge starts a newer one still,
    /// unless a clock is off by more than the time between them.
    var afterItsPurge: CardsZone {
        switch self {
        case .first: .started(after: .purge, at: 1)
        case .started(_, let time): .started(after: .purge, at: time + 1)
        }
    }

    /// The first comes before every other, and the others by when they
    /// started, and then by why, so that two devices that started one in
    /// the same millisecond agree on which is newer.
    static func < (one: CardsZone, other: CardsZone) -> Bool {
        switch (one, other) {
        case (.first, .first), (.started, .first): false
        case (.first, .started): true
        case (.started(let oneStart, let oneTime), .started(let otherStart, let otherTime)):
            (oneTime, oneStart.rawValue) < (otherTime, otherStart.rawValue)
        }
    }
}

/// iCloud's engine as sync's rules reach it, in the two zones inside the
/// device, `ICloudZone.cards` and `ICloudZone.files`: each change it's given
/// goes to the zone of the same kind the device syncs in now, by its name in
/// iCloud, and what it tells of those zones comes back inside the device, by
/// `insideTheDevice(_:)`; what it tells of any other zone is left out.
struct ICloudInItsZones: ICloudSyncEngine {
    /// iCloud's engine, which speaks in the names in iCloud.
    let base: any ICloudSyncEngine
    /// The cards' zone the device syncs in now, by its name in iCloud.
    let cards: ICloudZone
    /// The files' zone, by its name in iCloud.
    let files: ICloudZone

    /// The zone inside the device `zone` is, by its name in iCloud, or nil
    /// for one the device doesn't sync in now.
    func insideTheDevice(_ zone: ICloudZone) -> ICloudZone? {
        switch zone {
        case cards: .cards
        case files: .files
        default: nil
        }
    }

    /// The name in iCloud of `zone`, inside the device.
    func inICloud(_ zone: ICloudZone) -> ICloudZone {
        switch zone {
        case .cards: cards
        case .files: files
        default: zone
        }
    }

    /// `id`, inside the device, by its name in iCloud.
    func inICloud(_ id: ICloudRecordID) -> ICloudRecordID {
        ICloudRecordID(name: id.name, zone: inICloud(id.zone))
    }

    /// `id`, by its name in iCloud, inside the device, or nil for a record of
    /// a zone the device doesn't sync in now.
    func insideTheDevice(_ id: ICloudRecordID) -> ICloudRecordID? {
        insideTheDevice(id.zone).map { ICloudRecordID(name: id.name, zone: $0) }
    }

    func add(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        base.add(pendingRecordZoneChanges: changes.map { $0.with(id: inICloud($0.id)) })
    }

    func remove(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        base.remove(pendingRecordZoneChanges: changes.map { $0.with(id: inICloud($0.id)) })
    }

    func add(pendingDatabaseChanges changes: [ICloudPendingDatabaseChange]) {
        base.add(
            pendingDatabaseChanges: changes.map { change in
                switch change {
                case .saveZone(let zone): .saveZone(inICloud(zone))
                case .deleteZone(let zone): .deleteZone(inICloud(zone))
                }
            })
    }

    func sendChanges() async throws {
        try await base.sendChanges()
    }

    func fetchChanges() async throws {
        try await base.fetchChanges()
    }

    func fetchRecords(_ records: [(id: ICloudRecordID, type: String)]) {
        base.fetchRecords(records.map { (inICloud($0.id), $0.type) })
    }
}

/// Which cards' zone the device whose database is `db` syncs in.
func cardsZone(in db: Database) throws -> CardsZone {
    guard let device = try Row.fetchOne(db, sql: "SELECT cardsZone FROM syncDevice") else {
        throw unreadable("The database doesn't say which zone the cards sync in")
    }
    guard let nameEnd: String = try device.decode(forColumn: "cardsZone") else {
        return .first
    }
    guard let zone = CardsZone(nameEnd: nameEnd[...]) else {
        throw unreadable("The cards sync in a zone, \(nameEnd), that this version of Ficha doesn't know")
    }
    return zone
}

/// When the device whose database is `db` began syncing in its cards' zone,
/// or nil when it doesn't know: it has since before Ficha kept it, or it
/// hasn't started.
func cardsZoneSince(in db: Database) throws -> Date? {
    guard let device = try Row.fetchOne(db, sql: "SELECT cardsZoneSince FROM syncDevice") else {
        throw unreadable("The database doesn't say which zone the cards sync in")
    }
    return try device.decode(forColumn: "cardsZoneSince")
}

/// Moves the device to the cards' zone `zone`, syncing in it from `time`: it
/// forgets what iCloud said of the records of the zone it leaves, which mean
/// nothing in another, and the records that waited for a row, which came
/// from it.
func moveCards(to zone: CardsZone, at time: Date, in db: Database) throws {
    try db.execute(
        sql: "UPDATE syncDevice SET cardsZone = ?, cardsZoneSince = ?", arguments: [zone.nameEnd, time])
    try db.execute(sql: "DELETE FROM syncRecord WHERE zone = ?", arguments: [ICloudZone.cards.name])
    try db.execute(sql: "DELETE FROM syncIncoming")
}

/// Keeps that the device began syncing in its cards' zone at `time`, unless
/// it knows when it did already: as an engine starts from nothing.
func noteSyncingInTheCardsZone(since time: Date, in db: Database) throws {
    try db.execute(sql: "UPDATE syncDevice SET cardsZoneSince = ? WHERE cardsZoneSince IS NULL", arguments: [time])
}

/// Starts another cards' zone, from `time`, as sync turns on while it's off
/// after a restore or a purge: after a restore, one of the device's own,
/// started now; after a purge, the one past the zone it deleted
/// (`CardsZone.afterItsPurge`). The device sends every card into it, and the
/// other devices move to it, as `Sync` says. Turning sync on after the user
/// turned it off keeps the zone the device synced in.
func startACardsZoneIfOffAfterARestoreOrAPurge(at time: Date, in db: Database) throws {
    let zone: CardsZone
    switch try syncOffReason(in: db) {
    case .restore?: zone = .started(after: .restore, at: time.wholeMilliseconds)
    case .purge?: zone = try cardsZone(in: db).afterItsPurge
    case .user?, nil: return
    }
    try moveCards(to: zone, at: time, in: db)
}

extension ICloudPendingRecordZoneChange {
    /// The record it changes.
    var id: ICloudRecordID {
        switch self {
        case .saveRecord(let id), .deleteRecord(let id): id
        }
    }

    /// The same change, to the record `id`.
    fileprivate func with(id: ICloudRecordID) -> Self {
        switch self {
        case .saveRecord: .saveRecord(id)
        case .deleteRecord: .deleteRecord(id)
        }
    }
}

extension ICloudRecord {
    /// The record with `id` in place of its own, what iCloud said of it
    /// included.
    func with(id: ICloudRecordID) -> ICloudRecord {
        ICloudRecord(id: id, type: type, fields: fields, systemFields: systemFields)
    }

    /// The record inside the device, or nil for one of a zone the device
    /// doesn't sync in now.
    fileprivate func insideTheDevice(_ iCloud: ICloudInItsZones) -> ICloudRecord? {
        iCloud.insideTheDevice(id).map(with(id:))
    }
}

extension ICloudEvent {
    /// The event inside the device: of the records it tells of, those of the
    /// zones the device syncs in now, each by its zone inside the device, and
    /// none of the others. What it tells of zones that changed or left stays
    /// by their names in iCloud, which tell the cards' zones apart
    /// (`Sync.takeZoneChanges(_:with:)`).
    func insideTheDevice(_ iCloud: ICloudInItsZones) -> ICloudEvent {
        switch self {
        case .stateUpdate, .accountChange, .fetchedDatabaseChanges, .didFetchChanges:
            return self
        case .fetchedRecordZoneChanges(let changes):
            return .fetchedRecordZoneChanges(
                FetchedRecordZoneChanges(
                    modifications: changes.modifications.compactMap { $0.insideTheDevice(iCloud) },
                    deletions: changes.deletions.compactMap { deletion in
                        iCloud.insideTheDevice(deletion.id).map { RecordDeletion(id: $0, type: deletion.type) }
                    }))
        case .sentDatabaseChanges(let sent):
            return .sentDatabaseChanges(
                SentDatabaseChanges(
                    failedZoneSaves: sent.failedZoneSaves.compactMap { failure in
                        iCloud.insideTheDevice(failure.zone).map { FailedZoneSave(zone: $0, error: failure.error) }
                    }))
        case .sentRecordZoneChanges(let sent):
            return .sentRecordZoneChanges(
                SentRecordZoneChanges(
                    savedRecords: sent.savedRecords.compactMap { $0.insideTheDevice(iCloud) },
                    failedRecordSaves: sent.failedRecordSaves.compactMap { failure in
                        failure.record.insideTheDevice(iCloud).map { record in
                            FailedRecordSave(record: record, error: failure.error.insideTheDevice(iCloud))
                        }
                    },
                    deletedRecordIDs: sent.deletedRecordIDs.compactMap(iCloud.insideTheDevice),
                    failedRecordDeletes: Dictionary(
                        uniqueKeysWithValues: sent.failedRecordDeletes.compactMap { id, error in
                            iCloud.insideTheDevice(id).map { ($0, error.insideTheDevice(iCloud)) }
                        })))
        }
    }
}

extension ICloudError {
    /// The error inside the device: iCloud's record, when it holds one, by
    /// its zone inside the device, as the record it answers is.
    fileprivate func insideTheDevice(_ iCloud: ICloudInItsZones) -> ICloudError {
        guard case .serverRecordChanged(let record) = self, let inside = record.insideTheDevice(iCloud) else {
            return self
        }
        return .serverRecordChanged(inside)
    }
}
