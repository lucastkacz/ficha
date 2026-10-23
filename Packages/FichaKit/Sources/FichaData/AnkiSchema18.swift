import FichaCore
import Foundation
internal import GRDB

// An Anki collection at schema 18, as current Anki exports a deck by
// default: its note types, with their fields and templates, and its decks
// are in tables of their own, with protobuf blobs (`rslib/src/storage/
// notetype/`, `rslib/src/storage/deck/`, `proto/anki/notetypes.proto`),
// where schema 11 kept them as JSON in its one `col` row. Its notes and
// cards are in schema 11's tables. Their `name` columns are declared with
// Anki's own collation, `COLLATE unicase`, so SQL here never filters or
// sorts on them: the collation registered under that name only stands in
// for Anki's.

/// Anki's `unicase` collation, which it registers on each connection to a
/// collection (`rslib/src/storage/sqlite.rs`), as a comparison that ignores
/// case: SQLite needs one by that name to use the indexes on schema 18's
/// names.
let unicase = DatabaseCollation("unicase") { $0.compare($1, options: .caseInsensitive) }

/// The collection in `db`, an Anki database at schema 18.
func schema18Collection(in db: Database) throws -> AnkiCollection {
    guard let creationTime = try Int64.fetchOne(db, sql: "SELECT crt FROM col") else {
        throw unreadable("An Anki package's collection has no col row")
    }
    let fields = Dictionary(
        grouping: try Row.fetchAll(db, sql: "SELECT ntid, ord, name FROM fields").map { row in
            (
                noteType: try row.decode(forColumn: "ntid") as Int64, ordinal: try row.decode(forColumn: "ord") as Int,
                part: try row.decode(forColumn: "name") as String
            )
        }, by: \.noteType)
    let templates = Dictionary(
        grouping: try Row.fetchAll(db, sql: "SELECT ntid, ord, name, config FROM templates").map { row in
            // Template.Config: q_format = 1, a_format = 2.
            let config = try ProtobufFields(try row.decode(forColumn: "config") as Data)
            return (
                noteType: try row.decode(forColumn: "ntid") as Int64, ordinal: try row.decode(forColumn: "ord") as Int,
                part: AnkiCardTemplate(
                    name: try row.decode(forColumn: "name"), question: try config.string(1),
                    answer: try config.string(2))
            )
        }, by: \.noteType)
    let noteTypes = try Row.fetchAll(db, sql: "SELECT id, name, config FROM notetypes").map { row in
        let id: Int64 = try row.decode(forColumn: "id")
        // Notetype.Config: kind = 1, 0 normal or 1 cloze; and
        // original_stock_kind = 9, 6 for Image Occlusion.
        let config = try ProtobufFields(try row.decode(forColumn: "config") as Data)
        let kind: AnkiNoteType.Kind
        switch config.varint(1) {
        case 0: kind = .standard
        case 1: kind = .cloze
        case let other: throw unreadable("Anki note type \(id) is of the kind \(other)")
        }
        return (
            id,
            AnkiNoteType(
                name: try row.decode(forColumn: "name"), kind: kind, originalStockKind: Int(clamping: config.varint(9)),
                fields: try inOrder(fields[id] ?? [], of: id), templates: try inOrder(templates[id] ?? [], of: id))
        )
    }
    let decks = try Row.fetchAll(db, sql: "SELECT id, name FROM decks").map { row in
        // A name with U+001F between its levels, where schema 11 has `::`
        // (`rslib/src/decks/name.rs`).
        let name: String = try row.decode(forColumn: "name")
        return (try row.decode(forColumn: "id") as Int64, AnkiDeck(name: name.components(separatedBy: "\u{1F}")))
    }
    return AnkiCollection(
        creationTime: creationTime, daySettings: try ankiDaySettings(inConfigTableOf: db),
        noteTypes: Dictionary(noteTypes) { first, _ in first },
        decks: Dictionary(decks) { first, _ in first }, notes: try ankiNotes(in: db), cards: try ankiCards(in: db))
}

/// The parts of the note type `noteType`, its fields or its templates, each
/// with its `ord`, in that order, which counts from 0 without a gap, as
/// Anki writes it: a note's fields, and a card's template index, point into
/// it by position.
private func inOrder<Part>(_ parts: [(noteType: Int64, ordinal: Int, part: Part)], of noteType: Int64) throws -> [Part]
{
    let sorted = parts.sorted { $0.ordinal < $1.ordinal }
    guard sorted.map(\.ordinal) == Array(sorted.indices) else {
        throw unreadable("Anki note type \(noteType) has fields or templates numbered \(sorted.map(\.ordinal))")
    }
    return sorted.map(\.part)
}
