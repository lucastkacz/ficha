import FichaCore
import Foundation
internal import GRDB

// The zones a device syncs in, by their names in iCloud (ADR 0017, #317).
// Inside the device there are two, the cards' and the files', which the rest
// of sync names `ICloudZone.cards` and `ICloudZone.files`, and keeps what it
// knows of iCloud under. In iCloud each has a name of its own:
//
// - Ficha's own zones are "Files" and a cards' zone. An agent's scratch run
//   of Ficha Dev syncs in zones named after its scratch folder, such as
//   "Files-agent-317" and "Cards-agent-317.1761650000000.new", in the same
//   database, so that its cards never reach Ficha Dev's: each device leaves
//   alone the zones that aren't its own.
// - The cards have more than one zone over time, and no name is ever used
//   twice: each cards' zone a device makes is named after when it made it
//   and why, such as "Cards.1761650000000.restore" (`CardsZone`), since a
//   zone deleted and saved again under its own name reaches the other
//   devices as changed, with no deletion (P16, #316), and a device that
//   sends into it what iCloud said of its records before would take each
//   refusal as a deletion. "Cards", the zone of the versions of Ficha before
//   these names, stays the oldest. The files' zone keeps its name.
//
// Which cards' zone a device syncs in is the newest iCloud holds, which it
// learns by fetching before it sends anything, on its first sync, after an
// account change and after a purge (`CardsZoneStanding.chooses`); it makes
// one only when iCloud holds none, or as it turns sync on after a restore.
// It moves to a newer one as it hears of it, as `Sync` says.
//
// `Sync` speaks to iCloud's engine through `ICloudInItsZones`, which turns
// one set of names into the other, and leaves out what iCloud tells of any
// other zone. The device keeps where it stands among the cards' zones in its
// database, which never syncs it (`Schema`'s "v25 the cards' zone in
// iCloud"). Naming and choosing the zones this way is our own.

/// The name of an agent's scratch run of Ficha Dev, as `FICHA_DEV_SCRATCH`
/// gives it, which names its scratch folder and its zones in iCloud: only
/// letters, digits, `-` and `_`, so that no scratch run's zones can be
/// another's or Ficha's own.
public struct ScratchName: Sendable, Hashable {
    public let rawValue: String

    /// The scratch run `name` names, or nil for a name that can't name one.
    public init?(_ name: String) {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) })
        else {
            return nil
        }
        rawValue = name
    }
}

/// The zones a device syncs in, by their names in iCloud: Ficha's own, or a
/// scratch run's.
public struct ICloudZones: Sendable, Equatable {
    /// What follows "Cards" and "Files" in the zones' names.
    private let suffix: String

    /// Ficha's own zones, "Files" and the cards' zones, "Cards" and those
    /// after it, which Ficha Dev and the real Ficha sync in, each in its own
    /// environment of the container.
    public static let ficha = ICloudZones(suffix: "")

    /// The zones of the scratch run `name` of Ficha Dev: "Files-<name>" and
    /// the cards' zones, "Cards-<name>" and those after it.
    public static func scratch(_ name: ScratchName) -> ICloudZones {
        ICloudZones(suffix: "-\(name.rawValue)")
    }

    /// The files' zone.
    var files: ICloudZone {
        ICloudZone(name: "Files\(suffix)")
    }

    /// The name of the cards' zone `zone` in iCloud: "Cards" and the suffix
    /// for the first, and after them, for another, when a device made it and
    /// why.
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

/// One of the zones the cards have had in iCloud, apart from the files'. The
/// newest, by when a device made it, is the one every device moves to: the
/// other devices take a restore's cards in place of theirs, when they synced
/// in an older one, and join any other's, as `Sync` says.
enum CardsZone: Sendable, Hashable, Comparable {
    /// The zone of the versions of Ficha before these names, "Cards", older
    /// than every other.
    case first
    /// A zone a device made, `millisecondsSince1970` after 1970 by its
    /// clock, because of `reason`.
    case made(millisecondsSince1970: Int64, because: Reason)

    /// Why a device made a cards' zone. Its raw value is how the zone's name
    /// says it, so it never changes.
    enum Reason: String, Sendable {
        /// The device turned sync on after a restore: the devices that synced
        /// in an older zone take its cards in place of theirs.
        case restore
        /// iCloud held no cards' zone as the device started syncing, on its
        /// first sync, in another account or after a purge: the other
        /// devices join it.
        case new
    }

    /// The zone a device makes at `time`, because of `reason`, which sorts
    /// newer than `newest`, the newest it knows, if any: named after `time`,
    /// or a millisecond after `newest` when the device's clock is behind the
    /// time in its name, so that the other devices move to it, as they move
    /// only to a newer zone.
    static func made(at time: Date, after newest: CardsZone?, because reason: Reason) -> CardsZone {
        let afterTheNewest = newest?.millisecondsSince1970.map { $0 + 1 } ?? .min
        return .made(millisecondsSince1970: max(time.wholeMilliseconds, afterTheNewest), because: reason)
    }

    /// When a device made it, in milliseconds since 1970 by its clock, or
    /// nil for the first, which no device made.
    private var millisecondsSince1970: Int64? {
        switch self {
        case .first: nil
        case .made(let milliseconds, _): milliseconds
        }
    }

    /// Whether a device made it as it turned sync on after a restore.
    var isMadeByARestore: Bool {
        if case .made(_, .restore) = self { true } else { false }
    }

    /// What follows the zone's first part in its name: nothing for the
    /// first, and otherwise when and why a device made it, as
    /// "1761650000000.restore".
    var nameEnd: String? {
        switch self {
        case .first: nil
        case .made(let milliseconds, let reason): "\(milliseconds).\(reason.rawValue)"
        }
    }

    /// The zone whose name ends as `nameEnd` says, or nil when it says none.
    init?(nameEnd: Substring) {
        let parts = nameEnd.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let milliseconds = Int64(parts[0]), String(milliseconds) == parts[0],
            let reason = Reason(rawValue: String(parts[1]))
        else {
            return nil
        }
        self = .made(millisecondsSince1970: milliseconds, because: reason)
    }

    /// The first comes before every other, and the others by when they were
    /// made, and then by why, so that two devices that made one in the same
    /// millisecond agree on which is newer.
    static func < (one: CardsZone, other: CardsZone) -> Bool {
        switch (one, other) {
        case (.first, .first), (.made, .first): false
        case (.first, .made): true
        case (.made(let oneTime, let oneReason), .made(let otherTime, let otherReason)):
            (oneTime, oneReason.rawValue) < (otherTime, otherReason.rawValue)
        }
    }
}

/// Where a device stands among the cards' zones, as its database keeps it,
/// which never syncs it (`Schema`'s "v25 the cards' zone in iCloud"): read
/// whole and written whole.
struct CardsZoneStanding: Equatable {
    /// The cards' zone the device syncs in, or, while it chooses one, the
    /// one it last synced in, in this account; nil when it never synced in
    /// one in this account.
    var zone: CardsZone?
    /// Whether the device waits for a fetch to tell it the newest cards'
    /// zone iCloud holds before it sends anything: on its first sync, after
    /// an account change and after a purge. It then moves to that zone, or
    /// makes one when the fetch ends with none (`Sync`).
    var chooses: Bool
    /// The zone the device left as it turned sync on after a restore, which
    /// the engine that runs next deletes from iCloud, or nil.
    var left: CardsZone?
    /// The user the device last synced as, whose account the zones above
    /// are in, as its engine told of an account change, or nil before it
    /// told of one, as on a device that synced before Ficha kept it.
    var user: ICloudUser?

    /// Where the device whose database is `db` stands.
    init(in db: Database) throws {
        guard
            let device = try Row.fetchOne(
                db, sql: "SELECT cardsZone, choosesCardsZone, cardsZoneLeft, iCloudUser FROM syncDevice")
        else {
            throw unreadable("The database doesn't say which zone the cards sync in")
        }
        zone = try Self.zone(named: device.decode(forColumn: "cardsZone"))
        chooses = try device.decode(forColumn: "choosesCardsZone")
        left = try Self.zone(named: device.decode(forColumn: "cardsZoneLeft"))
        user = try (device.decode(forColumn: "iCloudUser") as String?).map(ICloudUser.init(recordName:))
        guard chooses || zone != nil else {
            throw unreadable("The database says the cards sync in no zone, and that the device doesn't choose one")
        }
    }

    /// Keeps it as where the device whose database is `db` stands.
    func keep(in db: Database) throws {
        try db.execute(
            sql: "UPDATE syncDevice SET cardsZone = ?, choosesCardsZone = ?, cardsZoneLeft = ?, iCloudUser = ?",
            arguments: [zone.map(Self.name(of:)), chooses, left.map(Self.name(of:)), user?.recordName])
    }

    /// The user `change` signs the device into when it's another than the
    /// one it last synced as, whose account's zones the device never synced
    /// in, or nil: a switch's, or a sign-in's as another user than the one
    /// the device knows. A sign-in while it knows none is taken as the same
    /// user's: the device keeps its zone, and learns the user.
    func anotherUser(after change: ICloudEvent.AccountChange) -> ICloudUser? {
        switch change {
        case .switchAccounts(_, let current):
            current
        case .signIn(let current):
            user.flatMap { $0 == current ? nil : current }
        case .signOut:
            nil
        }
    }

    /// The cards' zone the database names `name`, by its name among Ficha's
    /// own, or nil for none.
    private static func zone(named name: String?) throws -> CardsZone? {
        guard let name else {
            return nil
        }
        guard let zone = ICloudZones.ficha.cardsZone(ICloudZone(name: name)) else {
            throw unreadable("The cards sync in a zone, \(name), that this version of Ficha doesn't know")
        }
        return zone
    }

    /// How the database names `zone`: by its name among Ficha's own.
    private static func name(of zone: CardsZone) -> String {
        ICloudZones.ficha.cards(zone).name
    }
}

extension CardsZoneStanding {
    /// Moves the device whose database is `db` into the cards' zone `zone`,
    /// done choosing: it forgets what iCloud said of the records of the zone
    /// it leaves, which mean nothing in another, and the records that waited
    /// for a row, which came from it.
    static func move(to zone: CardsZone, in db: Database) throws {
        try change(in: db) { $0.move(to: zone) }
        try forgetTheRecordsOfTheZoneLeft(in: db)
    }

    /// Makes a cards' zone of its own, which iCloud holds none of, as the
    /// device whose database is `db` chose and the fetch it waited for ended
    /// with none, at `time`, and moves into it, as `move(to:in:)` says.
    /// Returns it.
    static func makeAZoneWhereICloudHoldsNone(at time: Date, in db: Database) throws -> CardsZone {
        let zone = try change(in: db) { standing in
            let zone = CardsZone.made(at: time, after: standing.zone, because: .new)
            standing.move(to: zone)
            return zone
        }
        try forgetTheRecordsOfTheZoneLeft(in: db)
        return zone
    }

    /// Makes a cards' zone of its own, at `time`, as sync turns on on the
    /// device whose database is `db` while it's off after a restore, and
    /// moves into it, as `move(to:in:)` says: the device sends every card
    /// into it, and deletes the zone it leaves as its engine starts; the
    /// other devices move to it, as `Sync` says. Turning sync on after a
    /// purge has the device choose, as the purge left it, and after the user
    /// turned it off, keeps its zone.
    static func makeAZoneIfOffAfterARestore(at time: Date, in db: Database) throws {
        guard try syncOffReason(in: db) == .restore else { return }
        try change(in: db) { standing in
            standing.left = standing.zone
            standing.move(to: .made(at: time, after: standing.zone, because: .restore))
        }
        try forgetTheRecordsOfTheZoneLeft(in: db)
    }

    /// The zone the device whose database is `db` left as it turned sync on
    /// after a restore, which it forgets, as its engine deletes it from
    /// iCloud, or nil.
    static func takeTheZoneLeft(in db: Database) throws -> CardsZone? {
        try change(in: db) { standing in
            defer { standing.left = nil }
            return standing.left
        }
    }

    /// Has the device whose database is `db` choose its cards' zone again, at
    /// its next fetch, as its engine starts over in the account it last
    /// synced in: after a purge, a sign-out or a sign-in as the user it last
    /// synced as. It keeps the zone it last synced in, so that it takes the
    /// copy of a restore made meanwhile.
    static func chooseAgain(in db: Database) throws {
        try change(in: db) { $0.chooses = true }
    }

    /// Has the device whose database is `db` choose its cards' zone again, at
    /// its next fetch, as its engine starts over in the account of `user`,
    /// another than the one it last synced in: it forgets the zone it last
    /// synced in and the one it left, whose names mean nothing in this
    /// account, and joins as on a first sync, as `user` from now on.
    static func chooseAgain(inTheAccountOf user: ICloudUser, in db: Database) throws {
        try change(in: db) { standing in
            standing.zone = nil
            standing.left = nil
            standing.chooses = true
            standing.user = user
        }
    }

    /// Keeps `user` as the one the device whose database is `db` last synced
    /// as, when it didn't know: one that synced before Ficha kept it learns
    /// it as its engine tells of an account change.
    static func learn(_ user: ICloudUser, in db: Database) throws {
        try change(in: db) { standing in
            standing.user = standing.user ?? user
        }
    }

    /// Reads where the device whose database is `db` stands, changes it as
    /// `change` does, keeps it, and returns what `change` returns.
    private static func change<Result>(in db: Database, _ change: (inout Self) throws -> Result) throws -> Result {
        var standing = try Self(in: db)
        let result = try change(&standing)
        try standing.keep(in: db)
        return result
    }

    /// Moves into the cards' zone `zone`, done choosing.
    private mutating func move(to zone: CardsZone) {
        self.zone = zone
        chooses = false
    }

    /// Forgets, in `db`, what iCloud said of the records of the cards' zone a
    /// device left, and the records that waited for a row, which came from it.
    private static func forgetTheRecordsOfTheZoneLeft(in db: Database) throws {
        try db.execute(sql: "DELETE FROM syncRecord WHERE zone = ?", arguments: [ICloudZone.cards.name])
        try db.execute(sql: "DELETE FROM syncIncoming")
    }
}

/// iCloud's engine as sync's rules reach it, in the two zones inside the
/// device, `ICloudZone.cards` and `ICloudZone.files`: each change it's given
/// goes to the zone of the same kind the device syncs in now, by its name in
/// iCloud, and what it tells of those zones comes back inside the device, by
/// `insideTheDevice(_:)`; what it tells of any other zone is left out. While
/// the device chooses its cards' zone, it syncs in none: a change to the
/// cards' zone is left out too.
struct ICloudInItsZones: ICloudSyncEngine {
    /// iCloud's engine, which speaks in the names in iCloud.
    private let base: any ICloudSyncEngine
    /// The zones the device syncs in, by their names in iCloud.
    private let zones: ICloudZones
    /// The cards' zone the device syncs in now, or nil while it chooses one.
    let cardsZone: CardsZone?

    /// `base` in `zones`, with `cardsZone` the cards' zone the device syncs
    /// in now, or nil while it chooses one.
    init(_ base: some ICloudSyncEngine, in zones: ICloudZones, cardsZone: CardsZone?) {
        self.base = base
        self.zones = zones
        self.cardsZone = cardsZone
    }

    /// The same engine, once the device moved to the cards' zone `zone`.
    func movedTo(_ zone: CardsZone) -> ICloudInItsZones {
        ICloudInItsZones(base, in: zones, cardsZone: zone)
    }

    /// The cards' zone the device syncs in now, by its name in iCloud.
    private var cards: ICloudZone? {
        cardsZone.map(zones.cards)
    }

    /// The zone inside the device `zone` is, by its name in iCloud, or nil
    /// for one the device doesn't sync in now.
    func insideTheDevice(_ zone: ICloudZone) -> ICloudZone? {
        switch zone {
        case cards: .cards
        case zones.files: .files
        default: nil
        }
    }

    /// The name in iCloud of `zone`, inside the device, or nil for the cards'
    /// zone while the device chooses one.
    private func inICloud(_ zone: ICloudZone) -> ICloudZone? {
        switch zone {
        case .cards: cards
        case .files: zones.files
        default: zone
        }
    }

    /// `id`, by its name in iCloud, inside the device, or nil for a record of
    /// a zone the device doesn't sync in now.
    func insideTheDevice(_ id: ICloudRecordID) -> ICloudRecordID? {
        insideTheDevice(id.zone).map { ICloudRecordID(name: id.name, zone: $0) }
    }

    /// `change`, inside the device, by its record's name in iCloud.
    private func inICloud(_ change: ICloudPendingRecordZoneChange) -> ICloudPendingRecordZoneChange? {
        inICloud(change.id.zone).map { change.with(id: ICloudRecordID(name: change.id.name, zone: $0)) }
    }

    func add(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        base.add(pendingRecordZoneChanges: changes.compactMap(inICloud))
    }

    func remove(pendingRecordZoneChanges changes: [ICloudPendingRecordZoneChange]) {
        base.remove(pendingRecordZoneChanges: changes.compactMap(inICloud))
    }

    func add(pendingDatabaseChanges changes: [ICloudPendingDatabaseChange]) {
        base.add(
            pendingDatabaseChanges: changes.compactMap { change in
                switch change {
                case .saveZone(let zone): inICloud(zone).map { .saveZone($0) }
                case .deleteZone(let zone): inICloud(zone).map { .deleteZone($0) }
                }
            })
    }

    /// Stops the save of the record `id`, by its name in iCloud, from
    /// waiting: one of a zone the device no longer syncs in, whose save
    /// waited as it moved.
    func stopSaving(_ id: ICloudRecordID) {
        base.remove(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    /// Deletes the cards' zones `left` from iCloud, those the device and the
    /// others left behind.
    func delete(_ left: [CardsZone]) {
        base.add(pendingDatabaseChanges: left.map { .deleteZone(zones.cards($0)) })
    }

    func sendChanges() async throws {
        try await base.sendChanges()
    }

    func fetchChanges() async throws {
        try await base.fetchChanges()
    }

    func fetchRecords(_ records: [(id: ICloudRecordID, type: String)]) {
        base.fetchRecords(
            records.compactMap { record in
                inICloud(record.id.zone).map { (ICloudRecordID(name: record.id.name, zone: $0), record.type) }
            })
    }
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
    /// (`Sync.takeZoneChanges(_:in:)`).
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
