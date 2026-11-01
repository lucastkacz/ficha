import FichaCore
import Foundation
internal import GRDB

// What Ficha keeps track of to sync (ADR 0017): the changes that wait to be
// sent to iCloud, when each field last changed, and what this device keeps
// for itself. Triggers in the database record every change, whoever writes
// it, the CLI too (`Schema`'s "v21 changes recorded to sync"); this file
// reads what they recorded, and is the one way to write without recording.
// Three changes are recorded by hand: what a device changes as it takes
// another device's deletion, in such a write (`SyncedDeletions.swift`), or
// another device's change to a tag or a deck (`TagChanges.swift`,
// `DeckChanges.swift`), and the rows that
// start or stop syncing as selective sync decides (`SelectiveSync.swift`).

/// A row that syncs, as iCloud names its record: a card, a capture, an entry
/// of the review log, a user type or a change to a tag or a deck by its ID
/// unique across devices, a tag or a deck by its name, or the settings that decide
/// progress or the choice of what syncs, of each of which there's one. Images and sounds
/// are named by their content, as `ImageName` and `SoundName` say.
enum SyncedRow: Sendable, Hashable {
    case card(UUID)
    case capture(UUID)
    case reviewLogEntry(UUID)
    case tag(String)
    case progressSettings
    /// Whether only the cards in a deck the user chose sync (ADR 0020, ADR
    /// 0024).
    case syncChoice
    /// A card type the user made.
    case userType(UUID)
    /// A rename or a deletion of a tag (`TagChanges.swift`).
    case tagChange(UUID)
    /// A deck, by its whole name, or Default by its own, `Deck.defaultName`
    /// (`SyncedDecks.swift`).
    case deck(String)
    /// A rename or a deletion of a deck (`DeckChanges.swift`).
    case deckChange(UUID)

    /// What kind of row it is, as the database names it.
    enum RecordType: String, Sendable {
        case card
        case capture
        case reviewLogEntry
        case tag
        case progressSettings
        case syncChoice
        case userType
        case tagChange
        case deck
        case deckChange
    }

    var recordType: RecordType {
        switch self {
        case .card: .card
        case .capture: .capture
        case .reviewLogEntry: .reviewLogEntry
        case .tag: .tag
        case .progressSettings: .progressSettings
        case .syncChoice: .syncChoice
        case .userType: .userType
        case .tagChange: .tagChange
        case .deck: .deck
        case .deckChange: .deckChange
        }
    }

    /// Its name, as the database keeps it: its ID, in capitals as Foundation
    /// writes it, the tag's or the deck's name, exactly as cards carry it,
    /// or the type of a row there's one of, which names it.
    var recordName: String {
        switch self {
        case .card(let id), .capture(let id), .reviewLogEntry(let id), .userType(let id), .tagChange(let id),
            .deckChange(let id):
            id.uuidString
        case .tag(let name), .deck(let name): name
        case .progressSettings: RecordType.progressSettings.rawValue
        case .syncChoice: RecordType.syncChoice.rawValue
        }
    }

    /// The row the database names by `recordType` and `recordName`, or an
    /// error when this version of Ficha doesn't know it.
    init(recordType: String, recordName: String) throws {
        guard let type = RecordType(rawValue: recordType) else {
            throw unreadable(
                "A row that syncs, \(recordName), is a \(recordType), which this version of Ficha doesn't know")
        }
        switch type {
        case .card: self = .card(try uuid(named: recordName, of: type))
        case .capture: self = .capture(try uuid(named: recordName, of: type))
        case .reviewLogEntry: self = .reviewLogEntry(try uuid(named: recordName, of: type))
        case .userType: self = .userType(try uuid(named: recordName, of: type))
        case .tagChange: self = .tagChange(try uuid(named: recordName, of: type))
        case .deckChange: self = .deckChange(try uuid(named: recordName, of: type))
        case .tag: self = .tag(recordName)
        case .deck: self = .deck(recordName)
        case .progressSettings:
            guard recordName == SyncedRow.progressSettings.recordName else {
                throw unreadable("The settings that decide progress sync under a name this version doesn't know")
            }
            self = .progressSettings
        case .syncChoice:
            guard recordName == SyncedRow.syncChoice.recordName else {
                throw unreadable("The choice of what syncs syncs under a name this version doesn't know")
            }
            self = .syncChoice
        }
    }
}

/// The ID unique across devices that `name`, the name of a row of `type`,
/// writes, or an error when it isn't one.
private func uuid(named name: String, of type: SyncedRow.RecordType) throws -> UUID {
    guard let id = UUID(uuidString: name) else {
        throw unreadable("The \(type.rawValue) that syncs as \(name) isn't named by a UUID")
    }
    return id
}

/// A field of a row that syncs which changes on its own: of each, the latest
/// change wins (ADR 0017). Its raw value is how the database keeps it, so it
/// never changes.
enum SyncedField: String, Sendable, CaseIterable {
    // A card's parts.
    case front
    case back
    case frontImage
    case backImage
    case frontSound
    case backSound
    case tags
    case type
    /// The deck it lives in.
    case deck
    /// A card's source, or a capture's.
    case source
    case bothWays
    /// The flag with its note.
    case flag
    case burial
    // A capture's fields, besides its source.
    case text
    case note
    /// When it left the inbox, approved or discarded.
    case refined
    /// The card it expands.
    case expandedCard
    /// The card it follows up.
    case followedUpCard
    // A tag's or a deck's: the switch it has on, priority or set aside, since
    // it has one at most, its color and its emoji, which a user type has too.
    case switchedOn
    case color
    case emoji
    /// Whether the user chose the deck to sync, beside its other switch. A
    /// tag's record held it before decks (ADR 0024), and sends it no more.
    case chosenToSync
    /// The tag's place among the pinned tags, while it's pinned.
    case pin
    // The settings that decide progress, each on its own.
    case ladder
    case newCardsPerDay
    case forgottenOftenAfter
    case learningSteps
    case relearningSteps
    case desiredRetention
    case longestIntervalInDays
    case fsrsParameters
    /// Whether only the cards in a deck the user chose sync, named when tags
    /// were chosen, as iCloud's records keep it (ADR 0024).
    case onlyChosenTags
    // A user type's, besides its emoji.
    case name
}

/// A change to a row that syncs, which waits to be sent to iCloud.
struct ChangeToSend: Sendable, Equatable {
    /// What happened to the row.
    enum Kind: Sendable, Equatable {
        /// It came in or changed: it's sent as it is now.
        case saved
        case deleted
    }

    let row: SyncedRow
    let kind: Kind
    /// When each of the row's fields last changed, of those that changed
    /// since it came in, also while sync was off: the others haven't changed
    /// since. Empty for a deletion, and for an entry of the review log, which
    /// never changes.
    let fieldTimes: [SyncedField: Date]
    /// Its place among the changes recorded, which grows with each one. A
    /// change made to the row after this one was read takes a later place,
    /// so forgetting this one, once it's sent, keeps the later one.
    let sequence: Int64
}

extension Engine {
    /// What waits to be sent to iCloud, oldest first: a change to each row
    /// that syncs that changed since its last change was sent. A save is
    /// recorded only while sync is on, and a deletion whether it's on or not,
    /// so that turning it on deletes from iCloud what the device deleted
    /// meanwhile (`Schema`'s "v24 how sync stands").
    func changesToSend() throws(EngineError) -> [ChangeToSend] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM syncPending ORDER BY id").map { pending in
                let row = try SyncedRow(
                    recordType: pending.decode(forColumn: "recordType"),
                    recordName: pending.decode(forColumn: "recordName"))
                let isDeletion: Bool = try pending.decode(forColumn: "isDeletion")
                return ChangeToSend(
                    row: row, kind: isDeletion ? .deleted : .saved, fieldTimes: try fieldTimes(of: row, in: db),
                    sequence: try pending.decode(forColumn: "id"))
            }
        }
    }

    /// Forgets `sent`, changes iCloud took: each stops waiting, unless its
    /// row changed again since it was read, whose later change still waits.
    func forget(_ sent: [ChangeToSend]) throws(EngineError) {
        try writeWithoutTelling { db in
            for change in sent {
                try db.execute(sql: "DELETE FROM syncPending WHERE id = ?", arguments: [change.sequence])
            }
        }
    }

    /// Runs `updates` in one transaction, as `write` does, without recording
    /// their changes to send: for what comes from iCloud, which mustn't go
    /// back. Nor does a row they delete wait to be sent any more, nor keep
    /// when its fields changed. When each field they change last changed is
    /// for them to write. It tells the other engines the database changed,
    /// unless `tellingTheOtherEngines` says not to, for a write that keeps
    /// only what sync keeps for itself, which would wake the app's sync to
    /// send again what waits.
    func writeWithoutRecording<Value>(
        tellingTheOtherEngines: Bool = true, _ updates: (Database) throws -> Value
    ) throws(EngineError) -> Value {
        let value = try writeWithoutTelling { db in
            try db.execute(sql: "UPDATE syncWrite SET recordsChanges = 0")
            let value = try updates(db)
            try db.execute(sql: "UPDATE syncWrite SET recordsChanges = 1")
            return value
        }
        if tellingTheOtherEngines {
            databaseChanges.post()
        }
        return value
    }

    /// Whether sync is on, as Settings' switch says: it is until the user
    /// turns it off, or a purge does.
    func syncIsOn() throws(EngineError) -> Bool {
        try read(isSyncOn(in:))
    }

    /// Turns sync on, as the user does in Settings, and leaves every row that
    /// syncs waiting to be sent, as nothing but deletions was recorded while
    /// it was off. Off after a restore, the device makes a cards' zone of its
    /// own and sends its cards into it, which the other devices take in place
    /// of theirs; off after a purge, it fetches first, and joins the zone
    /// another device made since, or makes one (`ICloudZones.swift`). The
    /// app's sync follows it. When it's on already, nothing changes.
    public func turnSyncOn() throws(EngineError) {
        let now = time.now
        try write { db in
            guard try !isSyncOn(in: db) else { return }
            try CardsZoneStanding.makeAZoneIfOffAfterARestore(at: now, in: db)
            try switchSyncOn(in: db)
            try recordEverythingToSend(in: db)
        }
    }

    /// Turns sync off, as the user does in Settings: nothing more is sent or
    /// fetched, and nothing waits to be sent but the deletions, until it's on
    /// again, which sends everything. A deletion made meanwhile waits too, so
    /// that turning it on deletes from iCloud what the device deleted. The
    /// images and sounds no card uses, which the device kept only because
    /// iCloud holds them, go: once it's on again, the device asks iCloud for
    /// any of them a card comes to use. The app's sync follows it. When it's
    /// off already, nothing changes.
    public func turnSyncOff() throws(EngineError) {
        let inICloud = try write { db in
            try switchSyncOff(because: .user, in: db)
            return try FileNames(heldByICloudIn: db)
        }
        removeFilesNoCardUses(inICloud)
    }

    /// The state CKSyncEngine saved last on this device, or nil before it
    /// saved one.
    func savedSyncEngineState() throws(EngineError) -> Data? {
        try read { db in
            guard let device = try Row.fetchOne(db, sql: "SELECT engineState FROM syncDevice") else {
                throw unreadable("The database doesn't keep what this device keeps to sync")
            }
            return try device.decode(forColumn: "engineState")
        }
    }

    /// Keeps `state` as the state CKSyncEngine saved last on this device, or
    /// forgets it when it's nil.
    func saveSyncEngineState(_ state: Data?) throws(EngineError) {
        try writeWithoutTelling { db in try FichaData.saveSyncEngineState(state, in: db) }
    }
}

/// Keeps `state` as the state CKSyncEngine saved last on this device, or
/// forgets it when it's nil: in the write that applies the changes it covers,
/// so that a power loss can't keep one without the other.
func saveSyncEngineState(_ state: Data?, in db: Database) throws {
    try db.execute(sql: "UPDATE syncDevice SET engineState = ?", arguments: [state])
}

/// Whether sync is on, as Settings' switch says.
func isSyncOn(in db: Database) throws -> Bool {
    guard let isOn = try Bool.fetchOne(db, sql: "SELECT isOn FROM syncDevice") else {
        throw unreadable("The database doesn't say whether sync is on")
    }
    return isOn
}

/// When each field of `row` last changed, of those that changed since it
/// came in.
func fieldTimes(of row: SyncedRow, in db: Database) throws -> [SyncedField: Date] {
    let times = try Row.fetchAll(
        db, sql: "SELECT field, changedAt FROM syncFieldTime WHERE recordType = ? AND recordName = ?",
        arguments: [row.recordType.rawValue, row.recordName])
    return Dictionary(
        uniqueKeysWithValues: try times.map { time in
            let name: String = try time.decode(forColumn: "field")
            guard let field = SyncedField(rawValue: name) else {
                throw unreadable(
                    """
                    The \(row.recordType.rawValue) that syncs as \(row.recordName) changed a field, \(name), \
                    that this version of Ficha doesn't know
                    """)
            }
            return (field, try time.decode(forColumn: "changedAt") as Date)
        })
}

/// Leaves every row that syncs waiting to be sent, as it is now, in place of
/// its change before: as sync is turned on, or meets another iCloud account.
/// A tag that had something of its own, and has nothing now, is sent too, so
/// that the other devices take that it has nothing. Every change to a tag the
/// device made or heard of goes too, so that one made while sync was off
/// reaches the cards the other devices hold that don't sync, and a device
/// that heard of one already never applies it again, and so does every change
/// to a deck. Every deck with a row goes, also one no card lives in. The
/// deletions that wait still do. The
/// user's card types go first: iCloud's engine sends in batches, and a
/// device that fetches a card before its type reads it as one with no type,
/// which an edit there would then keep. The decks go next, so that a deck's
/// cards come with what it has of its own.
func recordEverythingToSend(in db: Database) throws {
    let (card, capture, entry, tag, userType, tagChange, deck, deckChange) = (
        SyncedRow.RecordType.card.rawValue, SyncedRow.RecordType.capture.rawValue,
        SyncedRow.RecordType.reviewLogEntry.rawValue, SyncedRow.RecordType.tag.rawValue,
        SyncedRow.RecordType.userType.rawValue, SyncedRow.RecordType.tagChange.rawValue,
        SyncedRow.RecordType.deck.rawValue, SyncedRow.RecordType.deckChange.rawValue
    )
    try db.execute(
        sql: """
            DELETE FROM syncPending WHERE NOT isDeletion;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT '\(userType)', uuid, 0 FROM userType ORDER BY id;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT '\(deck)', name, 0 FROM deck ORDER BY name;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT '\(card)', uuid, 0 FROM card ORDER BY id;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT '\(capture)', uuid, 0 FROM capture ORDER BY id;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT '\(entry)', uuid, 0 FROM reviewLog ORDER BY id;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT '\(tag)', name, 0 FROM (
                SELECT name FROM tag UNION SELECT recordName FROM syncFieldTime WHERE recordType = '\(tag)')
            ORDER BY name;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT 'progressSettings', 'progressSettings', 0 FROM progressSettings;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT 'syncChoice', 'syncChoice', 0 FROM syncChoice
            WHERE EXISTS (SELECT 1 FROM syncFieldTime WHERE recordType = 'syncChoice');
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT '\(tagChange)', uuid, 0 FROM tagChange ORDER BY id;
            INSERT INTO syncPending (recordType, recordName, isDeletion)
            SELECT '\(deckChange)', uuid, 0 FROM deckChange ORDER BY id;
            """)
}
