import FichaCore
import Foundation
internal import GRDB
import os

/// Sync's log, apart from the engine's, for its files.
let syncLogger = Logger(subsystem: "com.lucastkacz.ficha", category: "sync")

/// Sync's rules (ADR 0017): what `CKSyncEngine`'s delegate does for Ficha,
/// on one device's engine. It hands iCloud's engine the changes recorded to
/// send, the CLI's too, builds each record as its row is when the engine
/// sends it, and applies what other devices changed without recording it to
/// send back: of each field of a card, a capture or a tag, the latest change
/// wins and the rest merges, and the review log's entries join, each card's
/// ways worked out again from them all. Each device keeps working without a
/// connection: what waits is sent once iCloud's engine reaches iCloud.
///
/// The app makes one when sync starts, calls `start(with:)`, then
/// `sendWhatChanged(to:)` whenever the database changes, and passes it each
/// event and request of `CKSyncEngine`'s delegate.
public struct Sync: Sendable {
    let engine: Engine

    /// The rules of sync for the device `engine` runs on.
    public init(engine: Engine) {
        self.engine = engine
    }

    /// Starts syncing through `iCloud`: on a device whose engine never saved
    /// a state, it asks iCloud for the cards' zone, and it hands `iCloud`
    /// every change that waits, those made while the app didn't run, by the
    /// CLI or offline, included.
    public func start(with iCloud: some ICloudSyncEngine) throws(EngineError) {
        if try engine.savedSyncEngineState() == nil {
            iCloud.add(pendingDatabaseChanges: [.saveZone(.cards)])
        }
        try sendWhatChanged(to: iCloud)
    }

    /// Hands `iCloud` every change that waits to be sent, as the database
    /// changes, whichever process changed it. One it already holds stays as
    /// one.
    public func sendWhatChanged(to iCloud: some ICloudSyncEngine) throws(EngineError) {
        iCloud.add(pendingRecordZoneChanges: try engine.changesToSend().compactMap(\.pendingRecordZoneChange))
    }

    /// The record iCloud's engine saves for `id`, as its row is now, with
    /// what iCloud said of it last, or nil when the device no longer holds
    /// it, which stops it from waiting: the record provider of
    /// `CKSyncEngine.RecordZoneChangeBatch(pendingChanges:recordProvider:)`.
    public func recordToSave(_ id: ICloudRecordID) throws(EngineError) -> ICloudRecord? {
        try engine.read { db in
            try syncedRow(named: id, in: db).flatMap { try record(of: $0, in: db) }
        }
    }

    /// Handles an event of iCloud's engine, as `CKSyncEngine`'s delegate's
    /// `handleEvent(_:syncEngine:)` does.
    public func handle(_ event: ICloudEvent, from iCloud: some ICloudSyncEngine) throws(EngineError) {
        switch event {
        case .stateUpdate(let state):
            try engine.saveSyncEngineState(state)
        case .fetchedRecordZoneChanges(let changes):
            // What other devices deleted wins in #313.
            try receiveFetched(changes.modifications)
        case .sentRecordZoneChanges(let sent):
            try settle(sent, with: iCloud)
        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                syncLogger.error(
                    "iCloud didn't save the zone \(failure.zone.name, privacy: .public): \(String(describing: failure.error))"
                )
            }
        case .fetchedDatabaseChanges(let changes):
            // A zone deleted or purged, and an account change, are #317's.
            for deletion in changes.deletions {
                syncLogger.notice(
                    "The zone \(deletion.zone.name, privacy: .public) left iCloud: \(String(describing: deletion.reason), privacy: .public)"
                )
            }
        case .accountChange(let change):
            syncLogger.notice("The iCloud account changed: \(String(describing: change), privacy: .public)")
        }
    }

    /// Applies `records`, which other devices saved, or this one, as iCloud
    /// holds them now, in one write that records nothing to send back: tags
    /// and captures first, then cards and the review log, so that what a
    /// record refers to is there first; and then those that waited for one
    /// of them.
    private func receiveFetched(_ records: [ICloudRecord]) throws(EngineError) {
        guard !records.isEmpty else {
            return
        }
        try engine.writeWithoutRecording { db in
            for record in records.sorted(by: { $0.applyingRank < $1.applyingRank }) {
                _ = try receive(record, in: db)
            }
            try applyWaitingRecords(in: db)
        }
    }

    /// Settles what became of the records iCloud's engine sent. A record
    /// iCloud saved keeps what iCloud says of it, and its change stops
    /// waiting, unless its row changed since. A record that changed in
    /// iCloud since this device heard of it takes iCloud's latest changes,
    /// field by field, and goes again with its own, if it still has some. A
    /// record whose zone or whose version iCloud no longer has goes again
    /// from scratch, its zone first. One that didn't fit in a full iCloud
    /// keeps waiting here, for when there's room (#317).
    private func settle(_ sent: ICloudEvent.SentRecordZoneChanges, with iCloud: some ICloudSyncEngine)
        throws(EngineError)
    {
        try engine.writeWithoutTelling { db in
            for record in sent.savedRecords {
                try keep(record.systemFields, of: record.id, in: db)
                try forgetPendingSave(of: try SyncedRow(of: record), whenICloudHolds: record, in: db)
            }
        }
        // What other devices deleted wins in #313.
        guard !sent.failedRecordSaves.isEmpty else {
            return
        }
        let again = try engine.writeWithoutRecording { db in
            try sent.failedRecordSaves.map { failure in try retry(failure, in: db) }
        }
        iCloud.add(pendingDatabaseChanges: again.compactMap(\.zone))
        iCloud.add(pendingRecordZoneChanges: again.compactMap(\.record))
    }

    /// What to send again of a record iCloud didn't save, as `failure` says
    /// why: the record again, its zone first, or nothing.
    private func retry(_ failure: ICloudEvent.FailedRecordSave, in db: Database) throws -> (
        zone: ICloudPendingDatabaseChange?, record: ICloudPendingRecordZoneChange?
    ) {
        let id = failure.record.id
        switch failure.error {
        case .serverRecordChanged(let iCloudsRecord):
            guard try receive(iCloudsRecord, in: db) == .applied,
                try hasPendingSave(SyncedRow(of: iCloudsRecord), in: db)
            else {
                return (nil, nil)
            }
            return (nil, .saveRecord(id))
        case .zoneNotFound:
            try keep(nil, of: id, in: db)
            return (.saveZone(id.zone), .saveRecord(id))
        case .unknownItem:
            // Whether a record gone from iCloud was deleted, which wins, is
            // #313's.
            try keep(nil, of: id, in: db)
            return (nil, .saveRecord(id))
        case .quotaExceeded:
            syncLogger.notice("iCloud is full: a change waits until there's room")
            return (nil, nil)
        case .retriedByTheEngine:
            return (nil, nil)
        case .other(let code):
            syncLogger.error(
                "iCloud didn't save a record of type \(failure.record.type, privacy: .public): \(code, privacy: .public)"
            )
            return (nil, nil)
        }
    }
}

extension ChangeToSend {
    /// The change iCloud's engine sends for it: a row saved is sent as it is
    /// when the engine sends it. A deletion waits for #313.
    fileprivate var pendingRecordZoneChange: ICloudPendingRecordZoneChange? {
        switch kind {
        case .saved: .saveRecord(row.recordID)
        case .deleted: nil
        }
    }
}

extension ICloudRecord {
    /// Its place among the records of a fetch as they're applied: tags and
    /// captures first, then cards, then the review log, so that what a record
    /// refers to comes before it. A type this version doesn't know comes
    /// last, to wait.
    fileprivate var applyingRank: Int {
        switch SyncedRow.RecordType(rawValue: type) {
        case .tag: 0
        case .capture: 1
        case .card: 2
        case .reviewLogEntry: 3
        case nil: 4
        }
    }
}
