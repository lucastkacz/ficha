import FichaCore
import Foundation
internal import GRDB

// How the images and sounds on cards sync (ADR 0017): each as a record of its
// own in the files' zone, apart from the cards', named by the file's name,
// which is its content's, and holding the file as an asset, so that sending
// one again is harmless. A device sends a file a card of its own uses while
// iCloud lacks it, as far as the device knows, which also sends again one
// that left iCloud. It keeps every file that comes, as a file the user added
// is kept, and removes one that left iCloud once no card uses it. It deletes
// from iCloud the files no card uses only once a fetch ends with the device
// in sync, as Anki does with media. What the device knows iCloud holds is
// what iCloud said last of each file's record (`syncRecord`).

/// An image or a sound on cards, as it syncs: a record of its own in the
/// files' zone.
enum SyncedFile: Sendable, Hashable {
    case image(ImageName)
    case sound(SoundName)

    /// The file the record `id` is of, in the files' zone, or nil for another
    /// name, such as a kind of file a later version of Ficha syncs.
    init?(_ id: ICloudRecordID) {
        guard id.zone == .files else {
            return nil
        }
        if let image = ImageName(rawValue: id.name) {
            self = .image(image)
        } else if let sound = SoundName(rawValue: id.name) {
            self = .sound(sound)
        } else {
            return nil
        }
    }

    /// Its name, as a card's side refers to it.
    var name: String {
        switch self {
        case .image(let name): name.rawValue
        case .sound(let name): name.rawValue
        }
    }

    /// The ID of its record: its name, in the files' zone.
    var recordID: ICloudRecordID {
        ICloudRecordID(name: name, zone: .files)
    }

    /// The type of its record.
    var recordType: String {
        switch self {
        case .image: "image"
        case .sound: "sound"
        }
    }

    /// Whether `engine` keeps it.
    func isKept(by engine: Engine) -> Bool {
        switch self {
        case .image(let name): engine.images.contains(name)
        case .sound(let name): engine.sounds.contains(name)
        }
    }

    /// Where iCloud's engine reads it from to send it, as `FileStore.url(of:)`
    /// says.
    func url(in engine: Engine) throws(EngineError) -> URL {
        switch self {
        case .image(let name): try engine.images.url(of: name)
        case .sound(let name): try engine.sounds.url(of: name)
        }
    }

    /// Keeps a copy of `file`, which came from iCloud, as it, with `engine`,
    /// unless it's kept already.
    func keep(copyOf file: URL, in engine: Engine) throws(EngineError) {
        switch self {
        case .image(let name): try engine.images.keep(copyOf: file, as: name)
        case .sound(let name): try engine.sounds.keep(copyOf: file, as: name)
        }
    }

    /// Whether a card in `db` uses it, on either side.
    func isUsed(in db: Database) throws -> Bool {
        let (front, back) =
            switch self {
            case .image: ImageName.columns
            case .sound: SoundName.columns
            }
        return try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM card WHERE \(front) = ? OR \(back) = ?)", arguments: [name, name])
            == true
    }
}

/// The key of the field of a file's record that holds the file.
private let fileKey = "file"

/// What a device knows of the images and sounds that sync: those its cards
/// use, and those iCloud holds, as far as it knows, which are those whose
/// records it heard of from iCloud, and not deleted since.
private struct FilesKnown {
    let used: Set<SyncedFile>
    let inICloud: Set<SyncedFile>

    init(in db: Database) throws {
        used = Set(try namesReferred(ImageName.self, in: db).map(SyncedFile.image))
            .union(try namesReferred(SoundName.self, in: db).map(SyncedFile.sound))
        inICloud = Set(
            try String.fetchAll(
                db, sql: "SELECT name FROM syncRecord WHERE zone = ?", arguments: [ICloudZone.files.name]
            )
            .compactMap { SyncedFile(ICloudRecordID(name: $0, zone: .files)) })
    }
}

extension Sync {
    /// Hands `iCloud` the images and sounds to send: each one a card on the
    /// device uses, which the device keeps and iCloud lacks, as far as the
    /// device knows. The same file on two cards is sent once.
    func sendFiles(to iCloud: some ICloudSyncEngine) throws(EngineError) {
        let known = try engine.read(FilesKnown.init(in:))
        let lacking = known.used.subtracting(known.inICloud).filter { $0.isKept(by: engine) }
        iCloud.add(pendingRecordZoneChanges: lacking.sorted { $0.name < $1.name }.map { .saveRecord($0.recordID) })
    }

    /// The record iCloud's engine saves for the file `id` names, as it sends
    /// it: the file, while a card on the device uses it, the device keeps it
    /// and iCloud lacks it, as far as the device knows; otherwise nil, which
    /// stops it from waiting.
    func fileRecordToSave(_ id: ICloudRecordID) throws(EngineError) -> ICloudRecord? {
        guard let file = SyncedFile(id) else {
            return nil
        }
        let isLacking = try engine.read { db in
            try file.isUsed(in: db) && systemFields(of: id, in: db) == nil
        }
        guard isLacking, file.isKept(by: engine) else {
            return nil
        }
        return ICloudRecord(
            id: id, type: file.recordType, fields: [fileKey: .asset(try file.url(in: engine))], systemFields: nil)
    }

    /// Handles the part of `event` about images and sounds, and returns the
    /// rest of it, about the cards' zone, for `handle(_:from:)` to go on
    /// with.
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

    /// Deletes from iCloud the images and sounds no card on the device uses,
    /// once a fetch ended with the device in sync: nothing waits to go up,
    /// neither a row's change nor a file a card uses that iCloud lacks, and
    /// nothing waits to come down, neither a record waiting for the row it
    /// refers to nor a file a card uses that iCloud holds and the device
    /// lacks. Another device whose card uses one of them, in a change it
    /// hadn't sent, sends it again once it hears it left.
    func deleteFilesNoCardUses(from iCloud: some ICloudSyncEngine) throws(EngineError) {
        let (known, isWaiting) = try engine.read { db in
            (
                try FilesKnown(in: db),
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS (SELECT 1 FROM syncPending) OR EXISTS (SELECT 1 FROM syncIncoming)") == true
            )
        }
        guard !isWaiting, known.used.allSatisfy({ $0.isKept(by: engine) == known.inICloud.contains($0) })
        else {
            return
        }
        iCloud.add(
            pendingRecordZoneChanges: known.inICloud.subtracting(known.used).sorted { $0.name < $1.name }
                .map { .deleteRecord($0.recordID) })
    }

    /// Takes the images and sounds iCloud holds now, saved by another device
    /// or by this one, and those that left it, `left`: the device keeps a
    /// copy of each file that came, unless it keeps it already, and knows
    /// iCloud holds it. Of those that left, it removes those no card uses,
    /// and sends again those one does.
    private func receiveFiles(
        _ records: [ICloudRecord], leaving left: [ICloudRecordID], with iCloud: some ICloudSyncEngine
    ) throws(EngineError) {
        guard !records.isEmpty || !left.isEmpty else {
            return
        }
        var came: [ICloudRecord] = []
        for record in records {
            guard let file = SyncedFile(record.id), record.type == file.recordType,
                case .asset(let copy)? = record.value(of: fileKey)
            else {
                syncLogger.error(
                    "A file of type \(record.type, privacy: .public) from iCloud can't be read, and is left out")
                continue
            }
            try file.keep(copyOf: copy, in: engine)
            came.append(record)
        }
        // A file that left and came again since the last fetch is in iCloud.
        try engine.writeWithoutRecording { db in
            for id in left {
                try keep(nil, of: id, in: db)
            }
            for record in came {
                try keep(record.systemFields, of: record.id, in: db)
            }
        }
        try letGo(of: left.filter { id in !came.contains { $0.id == id } }, with: iCloud)
    }

    /// Settles what became of the images and sounds iCloud's engine sent,
    /// `sent`, and of their deletions. A file iCloud saved, or held already,
    /// being named by its content, is one iCloud holds. One whose zone or
    /// whose record iCloud lacks goes again, its zone first. One that didn't
    /// fit in a full iCloud is sent again with the next changes (#317). A
    /// file deleted from iCloud is let go of, as one another device deleted.
    private func settleFiles(_ sent: ICloudEvent.SentRecordZoneChanges, with iCloud: some ICloudSyncEngine)
        throws(EngineError)
    {
        let saved = sent.savedRecords
        let failed = sent.failedRecordSaves
        guard !saved.isEmpty || !failed.isEmpty || !sent.deletedRecordIDs.isEmpty || !sent.failedRecordDeletes.isEmpty
        else {
            return
        }
        // A deletion whose zone or record iCloud lacks left all the same.
        var gone = sent.deletedRecordIDs
        for (id, error) in sent.failedRecordDeletes {
            switch error {
            case .zoneNotFound, .unknownItem:
                gone.append(id)
            case .retriedByTheEngine:
                break
            case .serverRecordChanged, .quotaExceeded, .other:
                syncLogger.error("iCloud didn't delete a file: \(String(describing: error), privacy: .public)")
            }
        }
        var again: [ICloudRecordID] = []
        try engine.writeWithoutTelling { db in
            for record in saved {
                try keep(record.systemFields, of: record.id, in: db)
            }
            for failure in failed {
                let id = failure.record.id
                switch failure.error {
                case .serverRecordChanged(let iCloudsRecord):
                    try keep(iCloudsRecord.systemFields, of: id, in: db)
                case .zoneNotFound, .unknownItem:
                    try keep(nil, of: id, in: db)
                    again.append(id)
                case .quotaExceeded:
                    syncLogger.notice("iCloud is full: a file waits until there's room")
                case .retriedByTheEngine:
                    break
                case .other(let code):
                    syncLogger.error("iCloud didn't save a file: \(code, privacy: .public)")
                }
            }
            for id in gone {
                try keep(nil, of: id, in: db)
            }
        }
        if failed.contains(where: { $0.error == .zoneNotFound }) {
            iCloud.add(pendingDatabaseChanges: [.saveZone(.files)])
        }
        iCloud.add(pendingRecordZoneChanges: again.map { .saveRecord($0) })
        try letGo(of: gone, with: iCloud)
    }

    /// Lets go of the files whose records left iCloud, `left`: removes from
    /// the device those no card uses, as a change that lets go of a file
    /// does, and sends again those one uses.
    private func letGo(of left: [ICloudRecordID], with iCloud: some ICloudSyncEngine) throws(EngineError) {
        guard !left.isEmpty else {
            return
        }
        var images: Set<ImageName> = []
        var sounds: Set<SoundName> = []
        for file in left.compactMap(SyncedFile.init) {
            switch file {
            case .image(let name): images.insert(name)
            case .sound(let name): sounds.insert(name)
            }
        }
        engine.removeFilesNoCardUses(images: images, sounds: sounds)
        try sendFiles(to: iCloud)
    }
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
    /// Whether `file`, which a card's side refers to, is still on its way
    /// from another device: this device doesn't keep it, and it syncs, and
    /// reached iCloud, from where the card came. The side shows without it,
    /// with no error, until it comes.
    func awaits(_ file: SyncedFile) throws(EngineError) -> Bool {
        guard !file.isKept(by: self) else {
            return false
        }
        return try read { db in
            try Bool.fetchOne(db, sql: "SELECT isOn AND engineState IS NOT NULL FROM syncDevice") == true
        }
    }
}
