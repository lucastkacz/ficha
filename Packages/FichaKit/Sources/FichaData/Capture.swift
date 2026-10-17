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

/// What capturing did: saved the capture in the inbox, or found that it's a
/// duplicate and left it for Lucas to expand or ignore.
public enum CaptureResult: Sendable, Equatable {
    /// The capture waits in the inbox.
    case saved(Capture)
    /// The capture is a duplicate of this card or capture, so it wasn't saved.
    case duplicate(of: Repeated)
}

/// What a duplicate repeats: a card, by its front or by the capture it was
/// approved from, or a capture in the inbox.
public enum Repeated: Sendable, Equatable {
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

/// What a capture with this text would repeat, if anything: the first card
/// whose front it repeats, or whose capture it repeats, or else the first
/// capture in the inbox it repeats. A capture that was discarded is left
/// out: it's in neither.
func repeated(by text: String, in db: Database) throws -> Repeated? {
    let capturedAs = Dictionary(
        uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, text FROM capture")
            .map { row in (try row.decode(forColumn: "id") as Int64, try row.decode(forColumn: "text") as String) }
    )
    let card = try allCards(in: db).first { card in
        repeats(text, card.front) || capturedAs[card.captureID].map { repeats(text, $0) } == true
    }
    if let card {
        return .card(card)
    }
    return try capturesWaiting(in: db).first { repeats(text, $0.text) }.map(Repeated.capture)
}

/// The captures that wait in the inbox, expansions included, oldest first.
func capturesWaiting(in db: Database) throws -> [Capture] {
    try capturesInInbox.order(Column("id")).fetchAll(db).map(Capture.init(row:))
}
