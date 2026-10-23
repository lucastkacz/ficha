import FichaCore
import Foundation
internal import GRDB
internal import ZIPFoundation

// An Anki package, an `.apkg` file, as Anki exports a deck: a zip with the
// deck's collection, a SQLite database, and its media. Which member holds the
// collection, and how, follows Anki's source (`rslib/src/import_export/
// package/`): Anki 2.0 wrote `collection.anki2`, at schema 11; Anki 2.1, and
// current Anki with "Support older Anki versions" ticked, `collection.anki21`,
// also at schema 11, beside a `collection.anki2` that holds only a note asking
// to update Anki; and current Anki by default, `collection.anki21b`,
// compressed with zstd, at schema 18, which Ficha can't read yet. ZIPFoundation
// reads the zip (ADR 0014), and GRDB the database (ADR 0004).

/// The members that hold a package's collection, oldest first.
private let collectionMembers: Set = ["collection.anki2", "collection.anki21", "collection.anki21b"]

/// Whether `data`, a zip, is an Anki package: it holds Anki's `meta`, or a
/// collection.
func isAnkiPackage(_ data: Data) -> Bool {
    guard let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil) else {
        return false
    }
    return archive.contains { $0.path == "meta" || collectionMembers.contains($0.path) }
}

/// The cards of the Anki package `data`, as `AnkiCollection.importReading()`
/// makes them of its collection, or why it can't be read.
func readAnkiPackage(_ data: Data) throws(CardsFileProblem) -> ImportReading {
    let collection: AnkiCollection
    do {
        let archive = try Archive(data: data, accessMode: .read, pathEncoding: nil)
        let entries = Dictionary(archive.map { ($0.path, $0) }) { first, _ in first }
        let member = try collectionMember(of: entries, in: archive)
        collection = try readCollection(try contents(of: member, in: archive))
    } catch let problem as CardsFileProblem {
        throw problem
    } catch {
        logger.error("Couldn't read an Anki package: \(String(describing: error), privacy: .public)")
        throw .unreadableAnkiPackage
    }
    do {
        return try collection.importReading()
    } catch {
        logger.error("An Anki package's collection is damaged: \(error.description, privacy: .public)")
        throw .unreadableAnkiPackage
    }
}

/// The member of a package with `entries`, by their paths, that holds its
/// collection, as Anki picks it (`package/meta.rs`, `from_archive`): the one
/// the version in `meta` names, or without `meta`, `collection.anki21` when
/// it's there, and `collection.anki2` otherwise, which Anki 2.0 wrote. A
/// version Ficha can't read yet, or doesn't know, is a problem of its own.
private func collectionMember(of entries: [String: Entry], in archive: Archive) throws -> Entry {
    let name: String
    if let meta = entries["meta"] {
        switch try packageVersion(inMeta: contents(of: meta, in: archive)) {
        case 1: name = "collection.anki2"
        case 2: name = "collection.anki21"
        case 3: throw CardsFileProblem.ankiPackageNotReadableYet
        default: throw CardsFileProblem.ankiPackageTooNew
        }
    } else {
        name = entries["collection.anki21"] != nil ? "collection.anki21" : "collection.anki2"
    }
    guard let member = entries[name] else {
        throw unreadable("An Anki package has no \(name)")
    }
    return member
}

/// The version that `meta`, Anki's `PackageMetadata` in protobuf, holds in
/// its field 1, a varint, or 0 when it holds none, as an empty one does
/// (`proto/anki/import_export.proto`). Other fields are skipped by their wire
/// type.
private func packageVersion(inMeta meta: Data) throws -> UInt64 {
    var bytes = meta[...]
    var version: UInt64 = 0
    while !bytes.isEmpty {
        let key = try varint(from: &bytes)
        switch key & 7 {
        case 0:
            let value = try varint(from: &bytes)
            if key >> 3 == 1 {
                version = value
            }
        case 1:
            bytes = bytes.dropFirst(8)
        case 2:
            bytes = bytes.dropFirst(Int(clamping: try varint(from: &bytes)))
        case 5:
            bytes = bytes.dropFirst(4)
        default:
            throw unreadable("An Anki package's meta has a field of wire type \(key & 7)")
        }
    }
    return version
}

/// The varint at the start of `bytes`, which it drops.
private func varint(from bytes: inout Data.SubSequence) throws -> UInt64 {
    var value: UInt64 = 0
    var shift: UInt64 = 0
    while let byte = bytes.popFirst() {
        guard shift < 64 else {
            break
        }
        value |= UInt64(byte & 0x7F) << shift
        if byte & 0x80 == 0 {
            return value
        }
        shift += 7
    }
    throw unreadable("An Anki package's meta ends in the middle of a number")
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
    var configuration = Configuration()
    configuration.readonly = true
    let database = try DatabaseQueue(path: file.path(percentEncoded: false), configuration: configuration)
    defer { try? database.close() }
    return try database.read { db in
        let version: Int? = try Int.fetchOne(db, sql: "SELECT ver FROM col")
        guard version == 11 else {
            throw unreadable("An Anki package's collection is at schema \(String(describing: version))")
        }
        return try schema11Collection(in: db)
    }
}

/// The collection in `db`, an Anki database at schema 11: its note types and
/// decks are JSON in its one `col` row (`rslib/src/notetype/schema11.rs`,
/// `rslib/src/decks/schema11.rs`), and its notes and cards are in tables.
private func schema11Collection(in db: Database) throws -> AnkiCollection {
    guard let col = try Row.fetchOne(db, sql: "SELECT crt, models, decks FROM col") else {
        throw unreadable("An Anki package's collection has no col row")
    }
    let models: String = try col.decode(forColumn: "models")
    let noteTypes = try JSONDecoder().decode([String: Schema11NoteType].self, from: Data(models.utf8))
    let decksJSON: String = try col.decode(forColumn: "decks")
    let decks = try JSONDecoder().decode([String: Schema11Deck].self, from: Data(decksJSON.utf8))
    return AnkiCollection(
        creationTime: try col.decode(forColumn: "crt"),
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
        db, sql: "SELECT id, nid, did, odid, ord, type, queue, due, ivl, odue, flags FROM cards"
    ).map { row in
        AnkiCard(
            id: try row.decode(forColumn: "id"), noteID: try row.decode(forColumn: "nid"),
            deckID: try row.decode(forColumn: "did"), originalDeckID: try row.decode(forColumn: "odid"),
            templateIndex: try row.decode(forColumn: "ord"), type: try row.decode(forColumn: "type"),
            queue: try row.decode(forColumn: "queue"), due: try row.decode(forColumn: "due"),
            interval: try row.decode(forColumn: "ivl"), originalDue: try row.decode(forColumn: "odue"),
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
    /// 0 for a standard note type, 1 for a cloze one.
    let type: Int
    let originalStockKind: Int?
    let flds: [Field]
    let tmpls: [Template]

    /// The note type it describes.
    func noteType() throws -> AnkiNoteType {
        let kind: AnkiNoteType.Kind
        switch type {
        case 0: kind = .standard
        case 1: kind = .cloze
        default: throw unreadable("An Anki note type is of the kind \(type)")
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
