import Foundation

// The one interface sync's rules reach iCloud through (ADR 0017): in the app,
// a thin adapter over CloudKit's `CKSyncEngine`, in a module only the app
// links, so that neither the CLI, `swift test` nor `make render` loads
// CloudKit; in tests, a fake iCloud that two or more devices share. Each type
// here stands for the one of `CKSyncEngine` it's named after, with what Ficha
// needs of it, so the adapter only converts: a record to a `CKRecord` and
// back, an event from the engine's delegate to `ICloudEvent`, and `Sync`'s
// answers back to the engine.

/// iCloud as sync reaches it: what `CKSyncEngine` does for the app. It
/// sends the changes it's given, asking `Sync` for each record to save as it
/// sends it, fetches what the other devices changed, and tells `Sync` of
/// every event, as `CKSyncEngine` tells its delegate.
public protocol ICloudSyncEngine: Sendable {
    /// Adds changes to the records it sends, as
    /// `CKSyncEngine.State.add(pendingRecordZoneChanges:)` does: each
    /// replaces the one before it for its record.
    func add(pendingRecordZoneChanges: [ICloudPendingRecordZoneChange])

    /// Stops sending changes to records, as
    /// `CKSyncEngine.State.remove(pendingRecordZoneChanges:)` does: one the
    /// engine can't get a record for keeps waiting until it's removed.
    func remove(pendingRecordZoneChanges: [ICloudPendingRecordZoneChange])

    /// Adds zones to save or delete, as
    /// `CKSyncEngine.State.add(pendingDatabaseChanges:)` does.
    func add(pendingDatabaseChanges: [ICloudPendingDatabaseChange])

    /// Sends what waits now, as `CKSyncEngine.sendChanges()` does, instead
    /// of when the engine would on its own.
    func sendChanges() async throws

    /// Fetches what the other devices changed now, as
    /// `CKSyncEngine.fetchChanges()` does, instead of when the engine would
    /// on its own.
    func fetchChanges() async throws
}

/// A zone of the user's private database in iCloud, as `CKRecordZone.ID`
/// names it in the default owner's database.
public struct ICloudZone: Sendable, Hashable, Codable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    /// The zone of the cards and everything else that syncs but images and
    /// sounds: captures, the review log and tags.
    public static let cards = ICloudZone(name: "Cards")
}

/// A record's ID in iCloud, as `CKRecord.ID`: its name, unique in its zone,
/// ASCII and up to 255 characters, and its zone.
public struct ICloudRecordID: Sendable, Hashable, Codable {
    public let name: String
    public let zone: ICloudZone

    public init(name: String, zone: ICloudZone) {
        self.name = name
        self.zone = zone
    }
}

/// A value a record's field holds, as `CKRecordValue`: text, a whole number,
/// or a number with a fraction. Times travel as whole milliseconds since
/// 1970, as the database keeps them, so iCloud never rounds them and every
/// device holds the same.
public enum ICloudValue: Sendable, Hashable, Codable {
    case string(String)
    case int(Int64)
    case double(Double)
}

/// A record in iCloud, as `CKRecord`: its ID, its type, its fields and what
/// iCloud said of it last.
public struct ICloudRecord: Sendable, Equatable, Codable {
    public let id: ICloudRecordID
    /// Its type, as `CKRecord.recordType`.
    public let type: String
    /// Its fields, by key, each with its value or nil for none. A record
    /// sync builds names every field of its type, so that saving it clears
    /// in iCloud each one it holds nil for; a record iCloud gives back names
    /// only those with a value.
    public let fields: [String: ICloudValue?]
    /// What iCloud said of it last, as `CKRecord.encodeSystemFields(with:)`
    /// writes it, which a save sends back so that iCloud knows which version
    /// it changes, or nil for a record this device never heard of from
    /// iCloud.
    public let systemFields: Data?

    public init(id: ICloudRecordID, type: String, fields: [String: ICloudValue?], systemFields: Data?) {
        self.id = id
        self.type = type
        self.fields = fields
        self.systemFields = systemFields
    }

    /// The value of the field `key`, or nil when it has none.
    public func value(of key: String) -> ICloudValue? {
        fields[key] ?? nil
    }

    /// The record with `systemFields` in place of its own.
    func with(systemFields: Data?) -> ICloudRecord {
        ICloudRecord(id: id, type: type, fields: fields, systemFields: systemFields)
    }

    /// Whether it holds the same values as `other`: its fields with a value,
    /// whatever iCloud said of either.
    func holdsTheSame(as other: ICloudRecord) -> Bool {
        (id, type) == (other.id, other.type) && fields.compactMapValues(\.self) == other.fields.compactMapValues(\.self)
    }
}

/// A change to a record that waits to be sent, as
/// `CKSyncEngine.PendingRecordZoneChange`.
public enum ICloudPendingRecordZoneChange: Sendable, Hashable, Codable {
    case saveRecord(ICloudRecordID)
    case deleteRecord(ICloudRecordID)
}

/// A change to a zone that waits to be sent, as
/// `CKSyncEngine.PendingDatabaseChange`.
public enum ICloudPendingDatabaseChange: Sendable, Hashable, Codable {
    case saveZone(ICloudZone)
    case deleteZone(ICloudZone)
}

/// Why iCloud didn't take a change, as the `CKError` codes sync handles
/// apart; the adapter turns every other code into `other`.
public enum ICloudError: Error, Sendable, Equatable {
    /// The record changed in iCloud since this device heard of it last
    /// (`serverRecordChanged`), with iCloud's record as it is now.
    case serverRecordChanged(ICloudRecord)
    /// Its zone isn't in iCloud (`zoneNotFound`).
    case zoneNotFound
    /// The record this device heard of isn't in iCloud any more
    /// (`unknownItem`).
    case unknownItem
    /// The user's iCloud is full (`quotaExceeded`).
    case quotaExceeded
    /// An error `CKSyncEngine` retries on its own, such as a missing
    /// network, keeping the change waiting: `networkFailure`,
    /// `networkUnavailable`, `zoneBusy`, `serviceUnavailable`,
    /// `notAuthenticated`, `requestRateLimited` and `operationCancelled`.
    case retriedByTheEngine
    /// Any other, by its code's name, for the log.
    case other(String)
}

/// What `CKSyncEngine` tells its delegate, as `CKSyncEngine.Event`, but the
/// events sync doesn't need: those that only say a fetch or a send starts
/// or ends.
public enum ICloudEvent: Sendable {
    /// The engine's state changed: what it starts from at the next launch,
    /// as its `State.Serialization` encodes it.
    case stateUpdate(Data)
    /// The user signed into iCloud, out of it, or into another account.
    case accountChange(AccountChange)
    /// Zones came into iCloud or left it.
    case fetchedDatabaseChanges(FetchedDatabaseChanges)
    /// Records other devices saved or deleted, or this one's, as iCloud
    /// holds them now.
    case fetchedRecordZoneChanges(FetchedRecordZoneChanges)
    /// What became of the zones the engine sent.
    case sentDatabaseChanges(SentDatabaseChanges)
    /// What became of the records the engine sent.
    case sentRecordZoneChanges(SentRecordZoneChanges)

    /// A change of the iCloud account, as
    /// `CKSyncEngine.Event.AccountChange.ChangeType`.
    public enum AccountChange: Sendable, Equatable {
        case signIn
        case signOut
        case switchAccounts
    }

    /// As `CKSyncEngine.Event.FetchedDatabaseChanges`.
    public struct FetchedDatabaseChanges: Sendable {
        public let modifications: [ICloudZone]
        public let deletions: [ZoneDeletion]

        public init(modifications: [ICloudZone], deletions: [ZoneDeletion]) {
            self.modifications = modifications
            self.deletions = deletions
        }
    }

    /// A zone that left iCloud, and why, as
    /// `CKSyncEngine.Event.FetchedDatabaseChanges.Deletion`.
    public struct ZoneDeletion: Sendable, Equatable {
        public let zone: ICloudZone
        public let reason: Reason

        public init(zone: ICloudZone, reason: Reason) {
            self.zone = zone
            self.reason = reason
        }

        /// As `CKDatabase.DatabaseChange.Deletion.Reason`.
        public enum Reason: Sendable, Equatable {
            /// Another device deleted it.
            case deleted
            /// The user deleted Ficha's data in iCloud's settings.
            case purged
            /// The user reset their iCloud's encrypted data.
            case encryptedDataReset
        }
    }

    /// As `CKSyncEngine.Event.FetchedRecordZoneChanges`.
    public struct FetchedRecordZoneChanges: Sendable {
        public let modifications: [ICloudRecord]
        public let deletions: [RecordDeletion]

        public init(modifications: [ICloudRecord], deletions: [RecordDeletion]) {
            self.modifications = modifications
            self.deletions = deletions
        }
    }

    /// A record that left iCloud, with its type, as
    /// `CKSyncEngine.Event.FetchedRecordZoneChanges.Deletion`.
    public struct RecordDeletion: Sendable, Equatable {
        public let id: ICloudRecordID
        public let type: String

        public init(id: ICloudRecordID, type: String) {
            self.id = id
            self.type = type
        }
    }

    /// As `CKSyncEngine.Event.SentDatabaseChanges`.
    public struct SentDatabaseChanges: Sendable {
        public let savedZones: [ICloudZone]
        public let failedZoneSaves: [FailedZoneSave]
        public let deletedZones: [ICloudZone]
        public let failedZoneDeletes: [ICloudZone: ICloudError]

        public init(
            savedZones: [ICloudZone], failedZoneSaves: [FailedZoneSave], deletedZones: [ICloudZone],
            failedZoneDeletes: [ICloudZone: ICloudError]
        ) {
            self.savedZones = savedZones
            self.failedZoneSaves = failedZoneSaves
            self.deletedZones = deletedZones
            self.failedZoneDeletes = failedZoneDeletes
        }
    }

    /// A zone iCloud didn't save, and why.
    public struct FailedZoneSave: Sendable {
        public let zone: ICloudZone
        public let error: ICloudError

        public init(zone: ICloudZone, error: ICloudError) {
            self.zone = zone
            self.error = error
        }
    }

    /// As `CKSyncEngine.Event.SentRecordZoneChanges`. A change that failed
    /// no longer waits in the engine, as in `CKSyncEngine`, unless its error
    /// is one the engine retries.
    public struct SentRecordZoneChanges: Sendable {
        /// The records iCloud saved, as it holds them now.
        public let savedRecords: [ICloudRecord]
        public let failedRecordSaves: [FailedRecordSave]
        public let deletedRecordIDs: [ICloudRecordID]
        public let failedRecordDeletes: [ICloudRecordID: ICloudError]

        public init(
            savedRecords: [ICloudRecord], failedRecordSaves: [FailedRecordSave], deletedRecordIDs: [ICloudRecordID],
            failedRecordDeletes: [ICloudRecordID: ICloudError]
        ) {
            self.savedRecords = savedRecords
            self.failedRecordSaves = failedRecordSaves
            self.deletedRecordIDs = deletedRecordIDs
            self.failedRecordDeletes = failedRecordDeletes
        }
    }

    /// A record iCloud didn't save, as this device sent it, and why.
    public struct FailedRecordSave: Sendable {
        public let record: ICloudRecord
        public let error: ICloudError

        public init(record: ICloudRecord, error: ICloudError) {
            self.record = record
            self.error = error
        }
    }
}
