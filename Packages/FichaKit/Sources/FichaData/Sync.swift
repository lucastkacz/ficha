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
/// send back: of each field of a card, a capture, a tag or the settings that
/// decide progress, the latest change wins and the rest merges, and the
/// review log's entries join, each card's ways worked out again from them
/// all. A deletion wins over what other devices changed of its row, and what
/// it changes on a device goes back as that device's own change
/// (`SyncedDeletions.swift`). The images and sounds on cards travel apart, in
/// a zone of their own, as `SyncedFiles.swift` says. Each device keeps
/// working without a connection: what waits is sent once iCloud's engine
/// reaches iCloud.
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
    /// a state, it asks iCloud for the cards' zone and the files', and it
    /// hands `iCloud` every change that waits, those made while the app
    /// didn't run, by the CLI or offline, included.
    public func start(with iCloud: some ICloudSyncEngine) throws(EngineError) {
        if try engine.savedSyncEngineState() == nil {
            iCloud.add(pendingDatabaseChanges: [.saveZone(.cards), .saveZone(.files)])
        }
        try sendWhatChanged(to: iCloud)
    }

    /// Hands `iCloud` every change that waits to be sent, as the database
    /// changes, whichever process changed it, and then the images and sounds
    /// its cards use that iCloud lacks. One it already holds stays as one.
    public func sendWhatChanged(to iCloud: some ICloudSyncEngine) throws(EngineError) {
        iCloud.add(pendingRecordZoneChanges: try engine.changesToSend().map(\.pendingRecordZoneChange))
        try sendFiles(to: iCloud)
    }

    /// The record `iCloud` saves for `id`, as its row is now, with what
    /// iCloud said of it last, or nil when the device no longer holds it,
    /// whose save then stops waiting in `iCloud`, as Apple's sample does: the
    /// record provider of
    /// `CKSyncEngine.RecordZoneChangeBatch(pendingChanges:recordProvider:)`.
    /// A file's record is as `fileRecordToSave(_:)` says.
    public func recordToSave(_ id: ICloudRecordID, from iCloud: some ICloudSyncEngine) throws(EngineError)
        -> ICloudRecord?
    {
        let record: ICloudRecord?
        if id.zone == .files {
            record = try fileRecordToSave(id)
        } else {
            record = try engine.read { db in
                try syncedRow(named: id, in: db).flatMap { try FichaData.record(of: $0, in: db) }
            }
        }
        if record == nil {
            iCloud.remove(pendingRecordZoneChanges: [.saveRecord(id)])
        }
        return record
    }

    /// Handles an event of iCloud's engine, as `CKSyncEngine`'s delegate's
    /// `handleEvent(_:syncEngine:)` does.
    public func handle(_ event: ICloudEvent, from iCloud: some ICloudSyncEngine) throws(EngineError) {
        // Images and sounds first, in `SyncedFiles.swift`; the rest is the
        // cards' zone's.
        let event = try handleFiles(in: event, from: iCloud)
        switch event {
        case .stateUpdate(let state):
            try engine.saveSyncEngineState(state)
        case .fetchedRecordZoneChanges(let changes):
            try receiveFetched(changes.modifications)
            try takeDeletions(changes.deletions)
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
            try forgetWhatICloudSaid()
        case .didFetchChanges:
            try finishFetchingFiles(with: iCloud)
        }
    }

    /// Forgets what iCloud said of every record, as the account changes:
    /// what one account said means nothing to another, and a record sent
    /// with it to an account that lacks it would be refused as one another
    /// device deleted, whose row goes (`takeDeletionsBehind`). Sent without
    /// it, a record the account holds merges with it, and one it lacks is
    /// saved: an account change never deletes a card. The images and sounds
    /// iCloud held are forgotten too, so the device sends each one its cards
    /// use, which the account turns down when it holds it.
    private func forgetWhatICloudSaid() throws(EngineError) {
        try engine.writeWithoutTelling { db in try db.execute(sql: "DELETE FROM syncRecord") }
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
    /// field by field, and goes again with its own, if it still has some. The
    /// deletions sent stop waiting, as `settleSentDeletions` says, and a
    /// record iCloud no longer has because another device deleted it takes
    /// that deletion (`takeDeletionsBehind`). Any other record whose zone or
    /// whose version iCloud no longer has goes again from scratch, its zone
    /// first. One that didn't fit in a full iCloud keeps waiting here, for
    /// when there's room (#317).
    private func settle(_ sent: ICloudEvent.SentRecordZoneChanges, with iCloud: some ICloudSyncEngine)
        throws(EngineError)
    {
        try engine.writeWithoutTelling { db in
            for record in sent.savedRecords {
                try keep(record.systemFields, of: record.id, in: db)
                try forgetPendingSave(of: try SyncedRow(of: record), whenICloudHolds: record, in: db)
            }
        }
        try settleSentDeletions(sent)
        let toRetry = try takeDeletionsBehind(sent.failedRecordSaves)
        guard !toRetry.isEmpty else {
            return
        }
        let retries = try engine.writeWithoutRecording { db in
            try toRetry.map { failure in try retry(failure, in: db) }
        }
        iCloud.add(pendingDatabaseChanges: retries.compactMap(\.zone))
        iCloud.add(pendingRecordZoneChanges: retries.compactMap(\.record))
    }

    /// What to send again of a record iCloud didn't save, as `failure` says
    /// why: the record again, its zone first, or nothing.
    func retry(_ failure: ICloudEvent.FailedRecordSave, in db: Database) throws -> (
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
            // A record of a row that's deleted for good never comes here:
            // its row went with it, as `takeDeletionsBehind` says. Any other,
            // such as a tag's, goes again from scratch.
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
    /// when the engine sends it, and a row deleted is deleted from iCloud.
    fileprivate var pendingRecordZoneChange: ICloudPendingRecordZoneChange {
        switch kind {
        case .saved: .saveRecord(row.recordID)
        case .deleted: .deleteRecord(row.recordID)
        }
    }
}

extension ICloudRecord {
    /// Its place among the records of a fetch as they're applied: tags, the
    /// settings that decide progress and captures first, then cards, then
    /// the review log, so that what a record refers to comes before it. A
    /// type this version doesn't know comes last, to wait.
    fileprivate var applyingRank: Int {
        switch SyncedRow.RecordType(rawValue: type) {
        case .tag, .progressSettings: 0
        case .capture: 1
        case .card: 2
        case .reviewLogEntry: 3
        case nil: 4
        }
    }
}
