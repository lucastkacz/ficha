import FichaCore
import Foundation
internal import GRDB
import Synchronization

// The files on cards' sides, images and sounds, each kept once in a folder of
// its kind beside the database, by a name that's its content's: one store
// keeps them all, so a kind never keeps its files its own way.

/// The name of a kind of file a card's side refers to, an image's or a
/// sound's: named by its content, so the same file coming in twice is kept
/// once.
protocol NameOfFileOnCard: RawRepresentable, Sendable, Hashable where RawValue == String {
    /// What the name names, for the engine's log, such as "image".
    static var kind: String { get }
    /// The folder beside the database where the files of its kind are kept.
    static var folderName: String { get }
    /// The `card` table's columns that refer to a file of its kind, on the
    /// front and on the back.
    static var columns: (front: String, back: String) { get }
    /// The error when the folder of its kind fails: its files couldn't be
    /// read, saved or removed, or one isn't there.
    static var folderError: EngineError { get }
    /// The error when data that comes in isn't a file of its kind Ficha can
    /// read.
    static var notOfItsKind: EngineError { get }
}

extension ImageName: NameOfFileOnCard {
    static let kind = "image"
    static let folderName = "Images"
    static let columns = (front: "frontImage", back: "backImage")
    static let folderError = EngineError.imagesFolder
    static let notOfItsKind = EngineError.notAnImage
}

extension SoundName: NameOfFileOnCard {
    static let kind = "sound"
    static let folderName = "Sounds"
    static let columns = (front: "frontSound", back: "backSound")
    static let folderError = EngineError.soundsFolder
    static let notOfItsKind = EngineError.notASound
}

/// A file on its way to a side of a card, an image or a sound, as it came
/// in, with the name it's kept by.
protocol CardFile: Sendable {
    associatedtype Name: NameOfFileOnCard
    var name: Name { get }
    /// The file as Ficha keeps it.
    var data: Data { get }
}

extension CardImage: CardFile {}

extension CardSound: CardFile {}

/// The folder in the data folder `folder` where the engine keeps the files
/// named by `Name`, beside the database and the Backups folder.
func folder<Name: NameOfFileOnCard>(of _: Name.Type, in folder: URL) -> URL {
    folder.appending(path: Name.folderName, directoryHint: .isDirectory)
}

/// Every file named by `Name` the cards in `db` refer to, on either side:
/// none for a database from before such files on cards, such as an old
/// backup, or from before cards. A name that isn't one of `Name` fails, as a
/// card the engine never saved.
func namesReferred<Name: NameOfFileOnCard>(_: Name.Type, in db: Database) throws -> Set<Name> {
    guard try db.tableExists("card") else {
        return []
    }
    let (front, back) = Name.columns
    let columns = try db.columns(in: "card").map(\.name)
    guard columns.contains(front), columns.contains(back) else {
        return []
    }
    let names = try String.fetchAll(
        db,
        sql: """
            SELECT \(front) FROM card WHERE \(front) IS NOT NULL
            UNION SELECT \(back) FROM card WHERE \(back) IS NOT NULL
            """)
    return try Set(
        names.map { rawName in
            guard let name = Name(rawValue: rawName) else {
                throw unreadable("A card refers to a file that isn't named as Ficha names its \(Name.kind)s")
            }
            return name
        })
}

/// Where the engine keeps the files named by `Name` on cards, each once, by
/// its name: a folder beside the database, with a file for each, or memory,
/// for an engine in memory.
enum FileStore<Name: NameOfFileOnCard>: Sendable {
    case folder(URL)
    case memory(FilesInMemory<Name>)

    /// Keeps `data` as the file `name`, unless a file with that name is kept
    /// already: being named by its content, it's the same file.
    func keep(_ data: Data, as name: Name) throws(EngineError) {
        switch self {
        case .folder(let folder):
            let file = folder.appending(path: name.rawValue)
            guard !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }
            try reportingErrors {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            }
        case .memory(let memory):
            memory.files.withLock { $0[name] = data }
        }
    }

    /// Keeps a copy of `file`, such as one that came from iCloud, as the file
    /// `name`, as `keep(_:as:)` does, unless a file with that name is kept
    /// already.
    func keep(copyOf file: URL, as name: Name) throws(EngineError) {
        guard !contains(name) else { return }
        try keep(try reportingErrors { try Data(contentsOf: file) }, as: name)
    }

    /// Where the file named `name` can be read from, as iCloud's engine reads
    /// a file it sends: the file itself, in the folder, or for an engine in
    /// memory a copy of it, in a temporary folder that goes with the engine.
    /// An error when it isn't kept.
    func url(of name: Name) throws(EngineError) -> URL {
        switch self {
        case .folder(let folder):
            let file = folder.appending(path: name.rawValue)
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
                logger.error("No \(Name.kind) named \(name.rawValue, privacy: .public) is kept to send")
                throw Name.folderError
            }
            return file
        case .memory(let memory):
            let copy = memory.copies.appending(path: name.rawValue)
            let data = try data(of: name)
            try reportingErrors {
                try FileManager.default.createDirectory(at: memory.copies, withIntermediateDirectories: true)
                try data.write(to: copy, options: .atomic)
            }
            return copy
        }
    }

    /// The file named `name`, or an error when it isn't kept.
    func data(of name: Name) throws(EngineError) -> Data {
        switch self {
        case .folder(let folder):
            try reportingErrors { try Data(contentsOf: folder.appending(path: name.rawValue)) }
        case .memory(let memory):
            try memory.files.withLock { files throws(EngineError) in
                guard let data = files[name] else {
                    logger.error("No \(Name.kind) named \(name.rawValue, privacy: .public) is kept in memory")
                    throw Name.folderError
                }
                return data
            }
        }
    }

    /// What the file named `name` weighs, in bytes, as it's kept, or an
    /// error when it isn't kept.
    func size(of name: Name) throws(EngineError) -> Int64 {
        switch self {
        case .folder(let folder):
            let file = folder.appending(path: name.rawValue)
            return try reportingErrors {
                guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: file])
                }
                return Int64(size)
            }
        case .memory:
            return Int64(try data(of: name).count)
        }
    }

    /// Whether the file named `name` is kept.
    func contains(_ name: Name) -> Bool {
        switch self {
        case .folder(let folder):
            FileManager.default.fileExists(atPath: folder.appending(path: name.rawValue).path(percentEncoded: false))
        case .memory(let memory):
            memory.files.withLock { $0[name] != nil }
        }
    }

    /// Every file kept, by name.
    func names() throws(EngineError) -> Set<Name> {
        switch self {
        case .folder(let folder):
            guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
            let files = try reportingErrors {
                try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            }
            return Set(files.compactMap(Name.init(rawValue:)))
        case .memory(let memory):
            return memory.files.withLock { Set($0.keys) }
        }
    }

    /// Removes the files named `names`, those kept: one that isn't is
    /// already gone.
    func remove(_ names: Set<Name>) throws(EngineError) {
        switch self {
        case .folder(let folder):
            for name in names {
                let file = folder.appending(path: name.rawValue)
                guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
                try reportingErrors { try FileManager.default.removeItem(at: file) }
            }
        case .memory(let memory):
            memory.files.withLock { files in
                for name in names {
                    files[name] = nil
                }
            }
        }
    }

    /// Runs `work` on the folder, and when it fails, logs why and throws the
    /// engine's error for it, whose message the user can read.
    private func reportingErrors<Value>(_ work: () throws -> Value) throws(EngineError) -> Value {
        do {
            return try work()
        } catch {
            logger.error(
                "The \(Name.folderName, privacy: .public) folder failed: \(String(describing: error), privacy: .public)"
            )
            throw Name.folderError
        }
    }
}

/// The files of an engine in memory, gone with it.
final class FilesInMemory<Name: NameOfFileOnCard>: Sendable {
    let files = Mutex<[Name: Data]>([:])
    /// A temporary folder for copies of its files that iCloud's engine reads
    /// as it sends them, gone with it too.
    let copies = URL.temporaryDirectory.appending(
        path: "Ficha-\(Name.folderName)-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: copies)
    }
}

extension Engine {
    /// Removes the files among `images` and `sounds` that no card refers to
    /// any more, now that a change let go of them, such as deleting a card
    /// or replacing a side's image or sound. While sync is on, one iCloud
    /// holds stays until it leaves iCloud, as `namesInICloud(_:in:)` says.
    /// One that couldn't be
    /// removed stays, and the engine logs why: the change is saved all the
    /// same.
    func removeFilesNoCardUses(images: Set<ImageName> = [], sounds: Set<SoundName> = []) {
        removeFilesNoCardUses(among: images, from: self.images)
        removeFilesNoCardUses(among: sounds, from: self.sounds)
    }

    /// Removes the images and sounds a card had `before` a change and no
    /// longer has `after` it, which no card refers to any more.
    func removeFilesNoCardUses(before: Card, after: Card) {
        removeFilesNoCardUses(
            images: before.images.subtracting(after.images), sounds: before.sounds.subtracting(after.sounds))
    }

    /// Removes from `store` the files among `names` that no card refers to,
    /// and iCloud doesn't hold while sync is on.
    private func removeFilesNoCardUses<Name>(among names: Set<Name>, from store: FileStore<Name>) {
        guard !names.isEmpty else { return }
        do throws(EngineError) {
            let unused = try read { db in
                try names.subtracting(namesReferred(Name.self, in: db))
                    .subtracting(isSyncOn(in: db) ? namesInICloud(Name.self, in: db) : [])
            }
            try store.remove(unused)
        } catch {
            logger.error(
                "Couldn't remove the \(Name.kind, privacy: .public)s no card uses: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
