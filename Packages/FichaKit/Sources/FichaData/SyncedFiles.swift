import FichaCore
import Foundation
internal import GRDB

// How the images and sounds on cards sync (ADR 0017): each as a record of its
// own in the files' zone, apart from the cards', named by the file's name,
// which is its content's, and holding the file as an asset, so that sending
// one again is harmless. A device sends a file a card of its own uses while
// iCloud lacks it, as far as the device knows, which also sends again one
// that left iCloud. It keeps every file that comes, as a file the user added
// is kept, and keeps a file iCloud holds even once no card uses it, removing
// it only once it left iCloud, so a card that comes later finds it. When a
// card uses a file iCloud holds and the device lacks anyway, the device asks
// iCloud for it again. It deletes from iCloud the files no card uses only
// once a fetch ends with the device in sync, as Anki does with media. What
// the device knows iCloud holds is what iCloud said last of each file's
// record (`syncRecord`).

/// The name of a kind of file on cards that syncs: where an engine keeps
/// the files of its kind, and the type of their records.
protocol NameOfSyncedFile: NameOfFileOnCard {
    /// The type of the records of the files of its kind.
    static var recordType: SyncedFile.RecordType { get }

    /// Where `engine` keeps the files of its kind.
    static func files(of engine: Engine) -> FileStore<Self>
}

extension ImageName: NameOfSyncedFile {
    static let recordType = SyncedFile.RecordType.image

    static func files(of engine: Engine) -> FileStore<ImageName> {
        engine.images
    }
}

extension SoundName: NameOfSyncedFile {
    static let recordType = SyncedFile.RecordType.sound

    static func files(of engine: Engine) -> FileStore<SoundName> {
        engine.sounds
    }
}

extension NameOfSyncedFile {
    /// Whether `engine` keeps the file.
    func isKept(by engine: Engine) -> Bool {
        Self.files(of: engine).contains(self)
    }

    /// What the file weighs, in bytes, as `engine` keeps it.
    func size(in engine: Engine) throws(EngineError) -> Int64 {
        try Self.files(of: engine).size(of: self)
    }

    /// Where iCloud's engine reads the file from to send it, as
    /// `FileStore.url(of:)` says.
    func url(in engine: Engine) throws(EngineError) -> URL {
        try Self.files(of: engine).url(of: self)
    }

    /// Keeps a copy of `file`, which came from iCloud, as the file, with
    /// `engine`, unless it's kept already.
    func keep(copyOf file: URL, in engine: Engine) throws(EngineError) {
        try Self.files(of: engine).keep(copyOf: file, as: self)
    }

    /// Whether a card in `db` uses the file, on either side.
    func isUsed(in db: Database) throws -> Bool {
        try namesReferred(Self.self, in: db).contains(self)
    }
}

/// An image or a sound on cards, as it syncs: a record of its own in the
/// files' zone, named by the file's name.
struct SyncedFile: Sendable, Hashable {
    let name: any NameOfSyncedFile

    /// The types of the files' records, as iCloud keeps them.
    enum RecordType: String, Sendable {
        case image
        case sound
    }

    init(_ name: some NameOfSyncedFile) {
        self.name = name
    }

    /// The file the record `id` is of, in the files' zone, or nil for a name
    /// of a kind this version of Ficha doesn't know, such as one a later
    /// version syncs.
    init?(_ id: ICloudRecordID) {
        let kinds: [any NameOfSyncedFile.Type] = [ImageName.self, SoundName.self]
        guard id.zone == .files, let name = kinds.lazy.compactMap({ $0.init(rawValue: id.name) }).first else {
            return nil
        }
        self.name = name
    }

    /// The ID of its record: its name, in the files' zone.
    var recordID: ICloudRecordID {
        ICloudRecordID(name: name.rawValue, zone: .files)
    }

    /// The type of its record.
    var recordType: RecordType {
        type(of: name).recordType
    }

    static func == (one: SyncedFile, other: SyncedFile) -> Bool {
        one.recordID == other.recordID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(recordID)
    }
}

/// The key of the field of a file's record that holds the file.
private let fileKey = "file"

/// The names of the files of `Name`'s kind that iCloud holds, as far as the
/// device knows: those whose records it heard of from iCloud, and not
/// deleted since. The device keeps each of them, whether a card uses it or
/// not, until it leaves iCloud, since no fetch would bring again a file
/// whose record didn't change, and a card another device sends may use it.
func namesInICloud<Name: NameOfFileOnCard>(_: Name.Type, in db: Database) throws -> Set<Name> {
    Set(
        try String.fetchAll(db, sql: "SELECT name FROM syncRecord WHERE zone = ?", arguments: [ICloudZone.files.name])
            .compactMap(Name.init(rawValue:)))
}

/// The images and sounds iCloud holds, as far as the device knows
/// (`namesInICloud(_:in:)`), for the device to remove those no card uses
/// once it no longer keeps them for iCloud: as sync turns off, or as it
/// forgets what iCloud holds.
struct FilesInICloud: Sendable {
    var images: Set<ImageName> = []
    var sounds: Set<SoundName> = []

    /// No file.
    init() {}

    /// The files iCloud holds, as far as the device whose database is `db`
    /// knows.
    init(in db: Database) throws {
        images = try namesInICloud(ImageName.self, in: db)
        sounds = try namesInICloud(SoundName.self, in: db)
    }
}

extension Engine {
    /// Removes the files among `files` that no card uses, and iCloud doesn't
    /// hold while sync is on, as `removeFilesNoCardUses(images:sounds:)`
    /// says.
    func removeFilesNoCardUses(_ files: FilesInICloud) {
        removeFilesNoCardUses(images: files.images, sounds: files.sounds)
    }
}

/// What a device knows of the images and sounds that sync: those its cards
/// use, and those iCloud holds, as far as it knows. A file of a kind this
/// version of Ficha doesn't know is neither: it never sends, fetches or
/// deletes one.
private struct FilesKnown {
    let used: Set<SyncedFile>
    let inICloud: Set<SyncedFile>

    init(in db: Database) throws {
        used = Set(try namesReferred(ImageName.self, in: db).map(SyncedFile.init))
            .union(try namesReferred(SoundName.self, in: db).map(SyncedFile.init))
        inICloud = Set(try namesInICloud(ImageName.self, in: db).map(SyncedFile.init))
            .union(try namesInICloud(SoundName.self, in: db).map(SyncedFile.init))
    }
}

extension Engine {
    /// The images and sounds sync sends: each one a card on the device uses,
    /// which the device keeps and iCloud lacks, as far as the device knows.
    /// The same file on two cards is one.
    func filesICloudLacks() throws(EngineError) -> Set<SyncedFile> {
        let known = try read(FilesKnown.init(in:))
        return known.used.subtracting(known.inICloud).filter { $0.name.isKept(by: self) }
    }

    /// What the images and sounds sync sends weigh, in bytes, as the device
    /// keeps them: those `filesICloudLacks()` says.
    func weightICloudLacks() throws(EngineError) -> Int64 {
        var weight: Int64 = 0
        for file in try filesICloudLacks() {
            weight += try file.name.size(in: self)
        }
        return weight
    }
}

extension Sync {
    /// Hands `iCloud` the images and sounds to send: each one a card on the
    /// device uses, which the device keeps and iCloud lacks, as far as the
    /// device knows. The same file on two cards is sent once.
    func sendFiles(to iCloud: some ICloudSyncEngine) throws(EngineError) {
        let lacking = try engine.filesICloudLacks()
        iCloud.add(pendingRecordZoneChanges: lacking.map(\.recordID).sorted(by: byName).map { .saveRecord($0) })
    }

    /// The record iCloud's engine saves for the file `id` names, as it sends
    /// it: the file, while a card on the device uses it, the device keeps it
    /// and iCloud lacks it, as far as the device knows; otherwise nil, which
    /// stops it from waiting, as for a kind of file this version of Ficha
    /// doesn't know, which it never sends.
    func fileRecordToSave(_ id: ICloudRecordID) throws(EngineError) -> ICloudRecord? {
        guard let file = SyncedFile(id) else {
            return nil
        }
        let isLacking = try engine.read { db in
            try file.name.isUsed(in: db) && systemFields(of: id, in: db) == nil
        }
        guard isLacking, file.name.isKept(by: engine) else {
            return nil
        }
        return ICloudRecord(
            id: id, type: file.recordType.rawValue, fields: [fileKey: .asset(try file.name.url(in: engine))],
            systemFields: nil)
    }

    /// Handles the part of `event` about images and sounds, and returns the
    /// rest of it, about the cards' zone, for `handle(_:from:startedIn:)` to
    /// go on with.
    func handleFiles(in event: ICloudEvent, from iCloud: some ICloudSyncEngine) throws(EngineError) -> ICloudEvent {
        switch event {
        case .fetchedRecordZoneChanges(let changes):
            let files = changes.only { $0 == .files }
            try receiveFiles(files.modifications, leaving: files.deletions.map(\.id), with: iCloud)
            return .fetchedRecordZoneChanges(changes.only { $0 != .files })
        case .sentRecordZoneChanges(let sent):
            try settleFiles(sent.only { $0 == .files }, with: iCloud)
            return .sentRecordZoneChanges(sent.only { $0 != .files })
        case .stateUpdate, .accountChange, .fetchedDatabaseChanges, .sentDatabaseChanges, .didFetchChanges:
            return event
        }
    }

    /// Once a fetch ended, asks iCloud again for the images and sounds a card
    /// uses that iCloud holds and the device lacks, which no fetch would
    /// bring again: one the device couldn't keep as it came, or let go of
    /// before it heard iCloud held it. With the device in sync, it deletes
    /// from iCloud the files no card uses: nothing waits to go up, neither a
    /// row's change nor a file a card uses that iCloud lacks, and nothing
    /// waits to come down, neither a record waiting for the row it refers to
    /// nor a file asked for again. Another device whose card uses one of
    /// them, in a change it hadn't sent, sends it again once it hears it left.
    func finishFetchingFiles(with iCloud: some ICloudSyncEngine) throws(EngineError) {
        let (known, isWaiting) = try engine.read { db in
            (
                try FilesKnown(in: db),
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS (SELECT 1 FROM syncPending) OR EXISTS (SELECT 1 FROM syncIncoming)") == true
            )
        }
        let askedAgain = known.used.intersection(known.inICloud).filter { !$0.name.isKept(by: engine) }
        guard askedAgain.isEmpty else {
            return iCloud.fetchRecords(
                askedAgain.sorted { byName($0.recordID, $1.recordID) }.map { ($0.recordID, $0.recordType.rawValue) })
        }
        guard !isWaiting, known.used.allSatisfy({ $0.name.isKept(by: engine) == known.inICloud.contains($0) })
        else {
            return
        }
        iCloud.add(
            pendingRecordZoneChanges: known.inICloud.subtracting(known.used).map(\.recordID).sorted(by: byName)
                .map { .deleteRecord($0) })
    }

    /// Takes the images and sounds iCloud holds now, saved by another device
    /// or by this one, and those that left it, `left`: the device keeps a
    /// copy of each file that came, unless it keeps it already, and knows
    /// iCloud holds each one, whether it could keep it or not. Of those that
    /// left, it removes those no card uses, and sends again those one does.
    private func receiveFiles(
        _ records: [ICloudRecord], leaving left: [ICloudRecordID], with iCloud: some ICloudSyncEngine
    ) throws(EngineError) {
        guard !records.isEmpty || !left.isEmpty else {
            return
        }
        for record in records {
            keepCopy(of: record)
        }
        // A file that left and came again since the last fetch is in iCloud.
        try engine.writeWithoutRecording { db in
            for id in left {
                try keep(nil, of: id, in: db)
            }
            for record in records {
                try keep(record.systemFields, of: record.id, in: db)
            }
        }
        try letGo(of: left.filter { id in !records.contains { $0.id == id } }, with: iCloud)
    }

    /// Keeps a copy of the file `record` holds, unless the device keeps it
    /// already. One the device can't read or keep is logged, and asked for
    /// again while a card uses it (`finishFetchingFiles(with:)`). One of a
    /// kind of file this version of Ficha doesn't know is left in iCloud, for
    /// a version that does, which asks for it once a card uses it.
    private func keepCopy(of record: ICloudRecord) {
        guard let file = SyncedFile(record.id) else {
            syncLogger.notice(
                "A file of type \(record.type, privacy: .public) from iCloud is of a kind this version of Ficha doesn't know, and is left there"
            )
            return
        }
        guard record.type == file.recordType.rawValue, case .asset(let copy)? = record.value(of: fileKey) else {
            syncLogger.error(
                "A file of type \(record.type, privacy: .public) from iCloud can't be read, and is asked for again while a card uses it"
            )
            return
        }
        do throws(EngineError) {
            try file.name.keep(copyOf: copy, in: engine)
        } catch {
            syncLogger.error(
                "A file from iCloud couldn't be kept, and is asked for again while a card uses it: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Settles what became of the images and sounds iCloud's engine sent,
    /// `sent`, and of their deletions. A file iCloud saved, or held already,
    /// being named by its content, is one iCloud holds. Any other that iCloud
    /// didn't save goes as `retry(_:in:)` says for any record. A file deleted
    /// from iCloud is let go of, as one another device deleted.
    private func settleFiles(_ sent: ICloudEvent.SentRecordZoneChanges, with iCloud: some ICloudSyncEngine)
        throws(EngineError)
    {
        guard
            !sent.savedRecords.isEmpty || !sent.failedRecordSaves.isEmpty || !sent.deletedRecordIDs.isEmpty
                || !sent.failedRecordDeletes.isEmpty
        else {
            return
        }
        let gone = sent.deletionsThatWent()
        let again = try engine.writeWithoutTelling { db in
            for record in sent.savedRecords {
                try keep(record.systemFields, of: record.id, in: db)
            }
            for id in gone {
                try keep(nil, of: id, in: db)
            }
            return try sent.failedRecordSaves.map {
                failure -> (zone: ICloudPendingDatabaseChange?, record: ICloudPendingRecordZoneChange?) in
                guard case .serverRecordChanged(let iCloudsRecord) = failure.error else {
                    return try retry(failure, in: db)
                }
                try keep(iCloudsRecord.systemFields, of: failure.record.id, in: db)
                return (nil, nil)
            }
        }
        iCloud.add(pendingDatabaseChanges: again.compactMap(\.zone))
        iCloud.add(pendingRecordZoneChanges: again.compactMap(\.record))
        try letGo(of: gone, with: iCloud)
    }

    /// Lets go of the files whose records left iCloud, `left`: removes from
    /// the device those no card uses, as a change that lets go of a file
    /// does, and sends again those one uses.
    private func letGo(of left: [ICloudRecordID], with iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard !left.isEmpty else {
            return
        }
        let names = left.compactMap(SyncedFile.init).map(\.name)
        engine.removeFilesNoCardUses(
            images: Set(names.compactMap { $0 as? ImageName }), sounds: Set(names.compactMap { $0 as? SoundName }))
        try sendFiles(to: iCloud)
    }
}

/// Whether `one` comes before `other` by name, so that what a device hands
/// iCloud's engine comes in the same order each time.
private func byName(_ one: ICloudRecordID, _ other: ICloudRecordID) -> Bool {
    one.name < other.name
}

extension ICloudEvent.FetchedRecordZoneChanges {
    /// Its changes to the records of the zones `isIncluded` picks.
    fileprivate func only(_ isIncluded: (ICloudZone) -> Bool) -> Self {
        Self(
            modifications: modifications.filter { isIncluded($0.id.zone) },
            deletions: deletions.filter { isIncluded($0.id.zone) })
    }
}

extension ICloudEvent.SentRecordZoneChanges {
    /// What became of its records in the zones `isIncluded` picks.
    fileprivate func only(_ isIncluded: (ICloudZone) -> Bool) -> Self {
        Self(
            savedRecords: savedRecords.filter { isIncluded($0.id.zone) },
            failedRecordSaves: failedRecordSaves.filter { isIncluded($0.record.id.zone) },
            deletedRecordIDs: deletedRecordIDs.filter { isIncluded($0.zone) },
            failedRecordDeletes: failedRecordDeletes.filter { isIncluded($0.key.zone) })
    }
}

extension Engine {
    /// Whether the file `name`, which a card's side refers to, may yet come
    /// from another device, so that the side shows without it, with no error:
    /// this device doesn't keep it, and it syncs and has reached iCloud,
    /// which holds the file, or may yet. A device can't tell a file still
    /// waiting to go up on another device from one that never will, such as
    /// one iCloud refused, so both show as on their way.
    func isOnItsWay(_ name: some NameOfSyncedFile) throws(EngineError) -> Bool {
        guard !name.isKept(by: self), try syncIsOn() else {
            return false
        }
        return try savedSyncEngineState() != nil
    }
}
