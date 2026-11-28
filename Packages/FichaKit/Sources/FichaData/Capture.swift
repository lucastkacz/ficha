import Foundation
internal import GRDB

/// Something Lucas jotted down to turn into cards later, as the database kept
/// it before Ficha took Capture and the inbox out (ADR 0041): the raw text,
/// with an optional note and source. The database keeps every capture,
/// unread, and sync carries them between devices as before, which is all it's
/// read for (`SyncedTable.captures`).
struct Capture: Sendable, Equatable {
    let id: Int64
    let text: String
    let note: String?
    let source: String?
    /// When Lucas captured it.
    let createdAt: Date
    /// The id of the card it expands, if Lucas chose to expand a card with it.
    let expandsCardID: Int64?
    /// The id of the card it follows up, if Lucas asked it about that card in
    /// the review panel. A capture never both expands a card and follows one
    /// up.
    let followsUpCardID: Int64?
}

extension Capture {
    /// A capture read from a row of the `capture` table.
    init(row: Row) throws {
        id = try row.decode(forColumn: "id")
        text = try row.decode(forColumn: "text")
        note = try row.decode(forColumn: "note")
        source = try row.decode(forColumn: "source")
        createdAt = try row.decode(forColumn: "createdAt")
        expandsCardID = try row.decode(forColumn: "expandsCardId")
        followsUpCardID = try row.decode(forColumn: "followsUpCardId")
    }
}

/// Lets the captures that expand the card with this id, or follow it up, go
/// of it, as the schema's references to cards need before the card is
/// deleted: each stays, as a plain capture, unread as every capture is.
func letGoOfCard(_ cardID: Int64, in db: Database) throws {
    try db.execute(sql: "UPDATE capture SET expandsCardId = NULL WHERE expandsCardId = ?", arguments: [cardID])
    try db.execute(sql: "UPDATE capture SET followsUpCardId = NULL WHERE followsUpCardId = ?", arguments: [cardID])
}
