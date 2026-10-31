import CloudKit
import FichaData
import Foundation

// The adapter's conversions between sync's types, in FichaData, and
// CloudKit's, which they stand for one to one (`ICloudSyncEngine.swift`).

extension ICloudRecordID {
    init(_ id: CKRecord.ID) {
        self.init(name: id.recordName, zone: ICloudZone(name: id.zoneID.zoneName))
    }
}

extension CKRecord.ID {
    convenience init(_ id: ICloudRecordID) {
        self.init(recordName: id.name, zoneID: CKRecordZone.ID(id.zone))
    }
}

extension CKRecordZone.ID {
    /// The zone in the user's own private database.
    convenience init(_ zone: ICloudZone) {
        self.init(zoneName: zone.name, ownerName: CKCurrentUserDefaultName)
    }
}

extension CKSyncEngine.PendingRecordZoneChange {
    init(_ change: ICloudPendingRecordZoneChange) {
        switch change {
        case .saveRecord(let id): self = .saveRecord(CKRecord.ID(id))
        case .deleteRecord(let id): self = .deleteRecord(CKRecord.ID(id))
        }
    }
}

extension CKSyncEngine.PendingDatabaseChange {
    init(_ change: ICloudPendingDatabaseChange) {
        switch change {
        case .saveZone(let zone): self = .saveZone(CKRecordZone(zoneID: CKRecordZone.ID(zone)))
        case .deleteZone(let zone): self = .deleteZone(CKRecordZone.ID(zone))
        }
    }
}

/// Why the adapter can't read what CloudKit gave it, or build what it sends.
enum CloudKitConversionError: Error, CustomStringConvertible {
    /// A record's field holds a kind of value Ficha never sends.
    case unknownValue(field: String, recordType: String)
    /// A record's file has no place on the device.
    case assetWithoutFile(field: String, recordType: String)
    /// What iCloud said of a record last can't be read back into one.
    case unreadableSystemFields(recordType: String)
    /// A deleted zone's reason is one this version doesn't know.
    case unknownZoneDeletionReason(zone: String)
    /// An account change is one this version doesn't know.
    case unknownAccountChange
    /// The state iCloud's engine saved last can't be read back.
    case unreadableEngineState
    /// The state iCloud's engine gives can't be written down to save.
    case unwritableEngineState

    var description: String {
        switch self {
        case .unknownValue(let field, let type):
            """
            The field \(field) of a record of type \(type) holds a kind of value Ficha never sends, as a later \
            version might: the record stays in iCloud for one that reads it. Update Ficha.
            """
        case .assetWithoutFile(let field, let type):
            """
            The file in the field \(field) of a record of type \(type) has no place on this device, so the record \
            is left out. If it keeps happening, report it.
            """
        case .unreadableSystemFields(let type):
            """
            What iCloud said last of a record of type \(type) can't be read back, so the record isn't sent. If it \
            keeps happening, report it.
            """
        case .unknownZoneDeletionReason(let zone):
            "The zone \(zone) left iCloud for a reason this version of Ficha doesn't know. Update Ficha."
        case .unknownAccountChange:
            "The iCloud account changed in a way this version of Ficha doesn't know. Update Ficha."
        case .unreadableEngineState:
            "The state iCloud's engine saved last on this device can't be read back, so sync stays off. Report it."
        case .unwritableEngineState:
            """
            The state iCloud's engine gave can't be written down, so the device fetches again what came since it \
            saved one. If it keeps happening, report it.
            """
        }
    }
}

extension CKSyncEngine.State.Serialization {
    /// The state `ICloudEvent.stateUpdate` held, as the device saved it.
    init(saved: Data) throws(CloudKitConversionError) {
        do {
            self = try JSONDecoder().decode(Self.self, from: saved)
        } catch {
            throw .unreadableEngineState
        }
    }
}

extension ICloudRecord {
    /// `record` as sync reads it: its fields with a value, each as the kind
    /// CloudKit holds it in, and what iCloud said of it, its system fields.
    /// A number comes back as the kind of number it was sent as, which
    /// `NSNumber` keeps: a whole number, or one with a fraction, even a
    /// whole one, as #316 probed.
    init(_ record: CKRecord) throws(CloudKitConversionError) {
        var fields: [String: ICloudValue?] = [:]
        for key in record.allKeys() {
            let value: (any CKRecordValueProtocol)? = record[key]
            switch value {
            case let asset as CKAsset:
                guard let file = asset.fileURL else {
                    throw .assetWithoutFile(field: key, recordType: record.recordType)
                }
                fields[key] = .asset(file)
            case let text as String:
                fields[key] = .string(text)
            case let number as NSNumber:
                fields[key] = CFNumberIsFloatType(number) ? .double(number.doubleValue) : .int(number.int64Value)
            case let bytes as Data:
                fields[key] = .bytes(bytes)
            default:
                throw .unknownValue(field: key, recordType: record.recordType)
            }
        }
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        self.init(
            id: ICloudRecordID(record.recordID), type: record.recordType, fields: fields,
            systemFields: archiver.encodedData)
    }

    /// Those of `records` sync can read, leaving out, and logging, any that
    /// holds what Ficha never sends: a record from a later Ficha that this
    /// version can't read stays in iCloud for one that can.
    static func all(_ records: [CKRecord]) -> [ICloudRecord] {
        records.compactMap { record in
            do {
                return try ICloudRecord(record)
            } catch {
                iCloudLogger.fault("A record from iCloud can't be read, and is left out: \(error, privacy: .public)")
                return nil
            }
        }
    }
}

extension ICloudRecord {
    /// The record CloudKit saves for it: on what iCloud said of it last, when
    /// it heard of it, so that iCloud knows which version it changes. Every
    /// field it names is set, those with no value to none, so that iCloud
    /// clears them.
    func toSave() throws(CloudKitConversionError) -> CKRecord {
        let record =
            try systemFields.map { systemFields throws(CloudKitConversionError) in
                guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: systemFields) else {
                    throw .unreadableSystemFields(recordType: type)
                }
                unarchiver.requiresSecureCoding = true
                defer { unarchiver.finishDecoding() }
                guard let record = CKRecord(coder: unarchiver), record.recordType == type else {
                    throw .unreadableSystemFields(recordType: type)
                }
                return record
            } ?? CKRecord(recordType: type, recordID: CKRecord.ID(id))
        for (key, value) in fields {
            switch value {
            case .string(let text)?: record[key] = text
            case .int(let number)?: record[key] = number
            case .double(let number)?: record[key] = number
            case .bytes(let bytes)?: record[key] = bytes
            case .asset(let file)?: record[key] = CKAsset(fileURL: file)
            case nil: record[key] = nil as (any CKRecordValueProtocol)?
            }
        }
        return record
    }
}

extension ICloudEvent {
    /// `event` as sync reads it, or nil for an event sync doesn't need: one
    /// that only says a fetch or a send starts or ends, but the end of a
    /// fetch.
    init?(_ event: CKSyncEngine.Event) throws(CloudKitConversionError) {
        switch event {
        case .stateUpdate(let update):
            guard let state = try? JSONEncoder().encode(update.stateSerialization) else {
                throw .unwritableEngineState
            }
            self = .stateUpdate(state)
        case .accountChange(let change):
            self = .accountChange(try AccountChange(change.changeType))
        case .fetchedDatabaseChanges(let changes):
            self = .fetchedDatabaseChanges(
                FetchedDatabaseChanges(
                    modifications: changes.modifications.map { ICloudZone(name: $0.zoneID.zoneName) },
                    deletions: try changes.deletions.map(ZoneDeletion.init)))
        case .fetchedRecordZoneChanges(let changes):
            self = .fetchedRecordZoneChanges(
                FetchedRecordZoneChanges(
                    modifications: ICloudRecord.all(changes.modifications.map(\.record)),
                    deletions: changes.deletions.map {
                        RecordDeletion(id: ICloudRecordID($0.recordID), type: $0.recordType)
                    }))
        case .sentDatabaseChanges(let sent):
            self = .sentDatabaseChanges(
                SentDatabaseChanges(
                    failedZoneSaves: sent.failedZoneSaves.map {
                        FailedZoneSave(zone: ICloudZone(name: $0.zone.zoneID.zoneName), error: ICloudError($0.error))
                    }))
        case .sentRecordZoneChanges(let sent):
            self = .sentRecordZoneChanges(
                SentRecordZoneChanges(
                    savedRecords: ICloudRecord.all(sent.savedRecords),
                    failedRecordSaves: try sent.failedRecordSaves.map { failed throws(CloudKitConversionError) in
                        FailedRecordSave(record: try ICloudRecord(failed.record), error: ICloudError(failed.error))
                    },
                    deletedRecordIDs: sent.deletedRecordIDs.map(ICloudRecordID.init),
                    failedRecordDeletes: Dictionary(
                        uniqueKeysWithValues: sent.failedRecordDeletes.map {
                            (ICloudRecordID($0.key), ICloudError($0.value))
                        })))
        case .didFetchChanges:
            self = .didFetchChanges
        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .willSendChanges,
            .didSendChanges:
            return nil
        @unknown default:
            return nil
        }
    }
}

extension ICloudEvent.AccountChange {
    init(_ change: CKSyncEngine.Event.AccountChange.ChangeType) throws(CloudKitConversionError) {
        switch change {
        case .signIn(let current):
            self = .signIn(currentUser: ICloudUser(current))
        case .signOut(let previous):
            self = .signOut(previousUser: ICloudUser(previous))
        case .switchAccounts(let previous, let current):
            self = .switchAccounts(previousUser: ICloudUser(previous), currentUser: ICloudUser(current))
        @unknown default:
            throw .unknownAccountChange
        }
    }
}

extension ICloudUser {
    /// The user whose user record's ID is `id`.
    init(_ id: CKRecord.ID) {
        self.init(recordName: id.recordName)
    }
}

extension ICloudEvent.ZoneDeletion {
    init(_ deletion: CKDatabase.DatabaseChange.Deletion) throws(CloudKitConversionError) {
        let zone = ICloudZone(name: deletion.zoneID.zoneName)
        switch deletion.reason {
        case .deleted: self.init(zone: zone, reason: .deleted)
        case .purged: self.init(zone: zone, reason: .purged)
        case .encryptedDataReset: self.init(zone: zone, reason: .encryptedDataReset)
        @unknown default: throw .unknownZoneDeletionReason(zone: zone.name)
        }
    }
}

extension ICloudError {
    /// The error sync reads for `error`: a code it handles apart, one the
    /// engine retries on its own, or any other, by its number, for the log.
    init(_ error: CKError) {
        switch error.code {
        case .serverRecordChanged:
            guard let record = error.serverRecord, let iCloudsRecord = try? ICloudRecord(record) else {
                self = .other("serverRecordChanged without iCloud's record")
                return
            }
            self = .serverRecordChanged(iCloudsRecord)
        case .zoneNotFound:
            self = .zoneNotFound
        case .unknownItem:
            self = .unknownItem
        case .quotaExceeded:
            self = .quotaExceeded
        case .userDeletedZone:
            self = .userDeletedZone
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
            .requestRateLimited, .operationCancelled, .accountTemporarilyUnavailable:
            self = .retriedByTheEngine
        default:
            self = .other("CKError \(error.code.rawValue)")
        }
    }
}
