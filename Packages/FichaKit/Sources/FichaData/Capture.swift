import FichaCore
import Foundation
internal import GRDB

/// Something Lucas jotted down to turn into cards later: the raw text, with an
/// optional note and source. It waits in the inbox until it's refined. The
/// `ficha` CLI prints it as JSON, without the note, source or card it doesn't
/// have.
public struct Capture: Sendable, Equatable, Encodable {
    public let id: Int64
    public let text: String
    public let note: String?
    public let source: String?
    /// When Lucas captured it.
    public let createdAt: Date
    /// The id of the card it expands, if Lucas chose to expand a card with it.
    public let expandsCardID: Int64?
}

/// What capturing did: saved the capture in the inbox, or found that it
/// repeats a card or a capture and left it for Lucas to expand or ignore.
public enum CaptureResult: Sendable, Equatable {
    /// The capture waits in the inbox.
    case saved(Capture)
    /// The capture repeats this card or capture, so it wasn't saved.
    case duplicate(Duplicate)
}

/// What a duplicate repeats: a card, by its front, or a capture in the inbox.
public enum Duplicate: Sendable, Equatable {
    case card(Card)
    case capture(Capture)
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
    }
}

/// Saves `content` as a capture in the inbox, captured at `time`, expanding
/// the card with the id `cardID` if there's one, and returns the capture.
func save(_ content: CaptureContent, expanding cardID: Int64?, at time: Date, in db: Database) throws -> Capture {
    try db.execute(
        sql: "INSERT INTO capture (text, note, source, createdAt, expandsCardId) VALUES (?, ?, ?, ?, ?)",
        arguments: [content.text, content.note, content.source, time, cardID]
    )
    return Capture(
        id: db.lastInsertedRowID,
        text: content.text,
        note: content.note,
        source: content.source,
        createdAt: time,
        expandsCardID: cardID
    )
}

/// What `text` repeats, if anything: the first card whose front it repeats,
/// or else the first capture in the inbox whose text it repeats.
func duplicate(of text: String, in db: Database) throws -> Duplicate? {
    if let card = try allCards(in: db).first(where: { repeats(text, $0.front) }) {
        return .card(card)
    }
    let captures = try capturesInInbox.order(Column("id")).fetchAll(db).map(Capture.init(row:))
    return captures.first { repeats(text, $0.text) }.map(Duplicate.capture)
}
