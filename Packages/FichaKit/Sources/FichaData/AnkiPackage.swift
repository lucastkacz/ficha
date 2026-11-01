import CryptoKit
import FichaCore
import FichaSVG
import Foundation
internal import GRDB
internal import ZIPFoundation

// An Anki package, an `.apkg` file, as Anki exports a deck: a zip with the
// deck's collection, a SQLite database, and its media. Which member holds the
// collection, and how, follows Anki's source (`rslib/src/import_export/
// package/`): Anki 2.0 wrote `collection.anki2`, at schema 11; Anki 2.1, and
// current Anki with "Support older Anki versions" ticked, `collection.anki21`,
// also at schema 11, beside a `collection.anki2` that holds only a note asking
// to update Anki; and current Anki by default, `collection.anki21b`, at
// schema 18, compressed with zstd (ADR 0015), as its media list and media
// files are. ZIPFoundation reads the zip (ADR 0014), and GRDB the database
// (ADR 0004).

/// The members that hold a package's collection, oldest first.
private let collectionMembers: Set = ["collection.anki2", "collection.anki21", "collection.anki21b"]

/// Whether `archive`, a zip, is an Anki package: it holds Anki's `meta`, or a
/// collection.
func isAnkiPackage(_ archive: Archive) -> Bool {
    archive.contains { $0.path == "meta" || collectionMembers.contains($0.path) }
}

/// The cards of the Anki package `archive`, as `AnkiCollection.
/// importReading(in:images:sounds:sha1:)` makes them of its collection, with
/// their due days as dates in `calendar`, and the images they show and the
/// sounds they play, by the names Ficha keeps them by, as they come in, from
/// the package's media, each read on its own, its SVGs drawn by `drawer`; or
/// why it can't be read. An image or a sound the package lacks, or holds
/// damaged, keeps out only the cards that hold nothing else on a side.
func readAnkiPackage(_ archive: Archive, in calendar: Calendar, drawingSVGsWith drawer: (any SVGDrawer)?)
    async throws(CardsFileProblem) -> (
        reading: ImportReading, images: [ImageName: CardImage], sounds: [SoundName: CardSound]
    )
{
    let collection: AnkiCollection
    let media: AnkiMedia
    do {
        let entries = Dictionary(archive.map { ($0.path, $0) }) { first, _ in first }
        let format = try PackageFormat(of: entries, in: archive)
        guard let member = entries[format.collectionMember] else {
            throw unreadable("An Anki package has no \(format.collectionMember)")
        }
        collection = try readCollection(try format.uncompressed(member, in: archive))
        // Read now, so that a package whose media list is damaged can't be
        // read, as in Anki.
        media = try AnkiMedia(of: entries, in: archive, format: format)
    } catch let problem as CardsFileProblem {
        throw problem
    } catch {
        logger.error("Couldn't read an Anki package: \(String(describing: error), privacy: .public)")
        throw .unreadableAnkiPackage
    }
    var images = FilesInZip<CardImage>(contents: media.contents(ofFileNamed:))
    var sounds = FilesInZip<CardSound>(contents: media.contents(ofFileNamed:))
    let reading: ImportReading
    do {
        reading = try await collection.importReading(in: calendar) { name in
            // Shrunk, as every image that comes in, or drawn, when its name
            // ends in `.svg`, which is how Anki tells an SVG.
            images.lookUp(name) { data throws(EngineError) in
                try pathExtension(of: name) == "svg"
                    ? CardImage(drawing: data, with: drawer) : CardImage(shrinking: data)
            }
        } sounds: { names in
            // Converted, as every sound that comes in, a video's included,
            // together: one at a time, a deck of long sounds took minutes.
            await sounds.lookUp(names) { name, data async throws(EngineError) in
                try await CardSound(converting: data, named: name)
            }
        } sha1: { text in
            // Anki names a formula's picture after it, not to keep it safe.
            Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    } catch {
        logger.error("An Anki package's collection is damaged: \(error.description, privacy: .public)")
        throw .unreadableAnkiPackage
    }
    return (reading, images.found, sounds.found)
}

/// How a package holds its collection and its media, as Anki tells (`package/
/// meta.rs`, `from_archive`): by the version in `meta`, or without `meta`,
/// by the members it has.
struct PackageFormat {
    /// The member that holds the collection.
    let collectionMember: String
    /// Whether it's the format current Anki exports by default, `meta`'s
    /// version 3: its collection, its media list and each media file are
    /// compressed with zstd, and its media list is protobuf rather than
    /// JSON.
    let isLatest: Bool

    /// The format of a package with `entries`, by their paths: the one the
    /// version in `meta` names, or without `meta`, the one whose collection
    /// is `collection.anki21` when it's there, and `collection.anki2`
    /// otherwise, which Anki 2.0 wrote. A version Ficha doesn't know is a
    /// problem of its own.
    init(of entries: [String: Entry], in archive: Archive) throws {
        guard let meta = entries["meta"] else {
            collectionMember = entries["collection.anki21"] != nil ? "collection.anki21" : "collection.anki2"
            isLatest = false
            return
        }
        // PackageMetadata { Version version = 1; }, never compressed
        // (`proto/anki/import_export.proto`): empty, it says 0.
        switch try ProtobufFields(contents(of: meta, in: archive)).varint(1) {
        case 1: (collectionMember, isLatest) = ("collection.anki2", false)
        case 2: (collectionMember, isLatest) = ("collection.anki21", false)
        case 3: (collectionMember, isLatest) = ("collection.anki21b", true)
        default: throw CardsFileProblem.ankiPackageTooNew
        }
    }

    /// What `entry` of `archive` holds, decompressed when the format
    /// compresses its members with zstd.
    func uncompressed(_ entry: Entry, in archive: Archive) throws -> Data {
        let data = try contents(of: entry, in: archive)
        return isLatest ? try zstdDecompressed(data) : data
    }
}

/// A package's media files, by the names the cards' fields refer to them
/// by: its `media` list says which member holds each (`package/media.rs`).
/// A package without the list, as an older AnkiDroid wrote, has none.
struct AnkiMedia {
    private let archive: Archive
    private let format: PackageFormat
    private let entries: [String: Entry]
    /// The member that holds each file, by the file's name.
    private let members: [String: String]

    /// The media of the package `archive`, with `entries` by their paths, in
    /// `format`.
    init(of entries: [String: Entry], in archive: Archive, format: PackageFormat) throws {
        self.archive = archive
        self.format = format
        self.entries = entries
        guard let list = entries["media"] else {
            members = [:]
            return
        }
        let data = try format.uncompressed(list, in: archive)
        let files: [(name: String, member: String)]
        if format.isLatest {
            // MediaEntries { repeated MediaEntry entries = 1; }, each with
            // its name in field 1: the file at position i is in member "i".
            files = try ProtobufFields(data).repeated(1).enumerated().map { position, entry in
                (try ProtobufFields(entry).string(1), "\(position)")
            }
        } else {
            // A JSON object that maps each member to its file's name.
            files = try JSONDecoder().decode([String: String].self, from: data).map { ($1, $0) }
        }
        members = Dictionary(files) { first, _ in first }
    }

    /// What the media file named `name` holds, decompressed, or nil when
    /// the package has no file by that name, as when its list names a
    /// member it lacks, which the engine logs. A member it can't read whole,
    /// as a damaged one, is an error.
    func contents(ofFileNamed name: String) throws -> Data? {
        guard let member = members[name] else {
            return nil
        }
        guard let entry = entries[member] else {
            logger.error("An Anki package's media list names the member \(member, privacy: .public), which it lacks")
            return nil
        }
        return try format.uncompressed(entry, in: archive)
    }
}

/// The collection `data` holds, a database Anki wrote, read from a copy in
/// a folder of its own, which goes once it's read. A schema this version
/// can't read is an error.
private func readCollection(_ data: Data) throws -> AnkiCollection {
    let folder = URL.temporaryDirectory.appending(
        path: "Ficha Anki package \(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "collection.anki2")
    try data.write(to: file)
    // Opened for writing, though Ficha only reads it: Anki leaves a
    // collection at schema 18 in WAL mode, where SQLite makes its `-shm`
    // file beside it even to read, which a read-only connection can't. And
    // with Anki's collation, which schema 18 declares its names with.
    var configuration = Configuration()
    configuration.prepareDatabase { db in
        db.add(collation: unicase)
    }
    let database = try DatabaseQueue(path: file.path(percentEncoded: false), configuration: configuration)
    defer { try? database.close() }
    return try database.read { db in
        switch try Int.fetchOne(db, sql: "SELECT ver FROM col") {
        case 11: try schema11Collection(in: db)
        case 18: try schema18Collection(in: db)
        case let version:
            throw unreadable("An Anki package's collection is at schema \(String(describing: version))")
        }
    }
}

/// The collection in `db`, an Anki database at schema 11: its note types and
/// decks are JSON in its one `col` row (`rslib/src/notetype/schema11.rs`,
/// `rslib/src/decks/schema11.rs`), and its notes and cards are in tables.
private func schema11Collection(in db: Database) throws -> AnkiCollection {
    guard let col = try Row.fetchOne(db, sql: "SELECT crt, conf, models, decks FROM col") else {
        throw unreadable("An Anki package's collection has no col row")
    }
    let conf: String = try col.decode(forColumn: "conf")
    let models: String = try col.decode(forColumn: "models")
    let noteTypes = try JSONDecoder().decode([String: Schema11NoteType].self, from: Data(models.utf8))
    let decksJSON: String = try col.decode(forColumn: "decks")
    let decks = try JSONDecoder().decode([String: Schema11Deck].self, from: Data(decksJSON.utf8))
    return AnkiCollection(
        creationTime: try col.decode(forColumn: "crt"),
        daySettings: try ankiDaySettings(inConf: conf),
        noteTypes: try Dictionary(
            uniqueKeysWithValues: noteTypes.map { id, noteType in (try ankiID(id), try noteType.noteType()) }),
        decks: try Dictionary(
            uniqueKeysWithValues: decks.map { id, deck in
                (try ankiID(id), AnkiDeck(name: deck.name.components(separatedBy: "::")))
            }),
        notes: try ankiNotes(in: db),
        cards: try ankiCards(in: db))
}

/// The id `key`, a key of schema 11's JSON, holds.
private func ankiID(_ key: String) throws -> Int64 {
    guard let id = Int64(key) else {
        throw unreadable("An Anki package's collection has the id \(key)")
    }
    return id
}

/// The notes of an Anki database, by their ids, from its `notes` table, which
/// schema 11 and schema 18 share: their fields separated by U+001F, and
/// their tags by spaces (`rslib/src/storage/note/mod.rs`, `rslib/src/tags/`).
func ankiNotes(in db: Database) throws -> [Int64: AnkiNote] {
    let rows = try Row.fetchAll(db, sql: "SELECT id, mid, tags, flds FROM notes")
    return try Dictionary(
        rows.map { row in
            let tags: String = try row.decode(forColumn: "tags")
            let fields: String = try row.decode(forColumn: "flds")
            return (
                try row.decode(forColumn: "id") as Int64,
                AnkiNote(
                    noteTypeID: try row.decode(forColumn: "mid"),
                    fields: fields.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init),
                    tags: tags.split { $0 == " " || $0 == "\u{3000}" }.map(String.init))
            )
        }
    ) { first, _ in first }
}

/// The cards of an Anki database, from its `cards` table, which schema 11
/// and schema 18 share.
func ankiCards(in db: Database) throws -> [AnkiCard] {
    try Row.fetchAll(
        db, sql: "SELECT id, nid, did, odid, ord, type, queue, due, ivl, factor, odue, flags FROM cards"
    ).map { row in
        AnkiCard(
            id: try row.decode(forColumn: "id"), noteID: try row.decode(forColumn: "nid"),
            deckID: try row.decode(forColumn: "did"), originalDeckID: try row.decode(forColumn: "odid"),
            templateIndex: try row.decode(forColumn: "ord"), type: try row.decode(forColumn: "type"),
            queue: try row.decode(forColumn: "queue"), due: try row.decode(forColumn: "due"),
            interval: try row.decode(forColumn: "ivl"), factor: try row.decode(forColumn: "factor"),
            originalDue: try row.decode(forColumn: "odue"),
            flags: try row.decode(forColumn: "flags"))
    }
}

/// A note type in schema 11's JSON, with what Ficha reads of it.
private struct Schema11NoteType: Decodable {
    struct Field: Decodable {
        let name: String
    }

    struct Template: Decodable {
        let name: String
        let qfmt: String
        let afmt: String
    }

    let name: String
    /// Its kind's number, as `AnkiNoteType.Kind` reads it.
    let type: Int
    let originalStockKind: Int?
    let flds: [Field]
    let tmpls: [Template]

    /// The note type it describes.
    func noteType() throws -> AnkiNoteType {
        guard let kind = AnkiNoteType.Kind(rawValue: type) else {
            throw unreadable("An Anki note type is of the kind \(type)")
        }
        return AnkiNoteType(
            name: name, kind: kind, originalStockKind: originalStockKind ?? 0, fields: flds.map(\.name),
            templates: tmpls.map { AnkiCardTemplate(name: $0.name, question: $0.qfmt, answer: $0.afmt) })
    }
}

/// A deck in schema 11's JSON, with what Ficha reads of it.
private struct Schema11Deck: Decodable {
    /// Its name, with `::` between its levels.
    let name: String
}
