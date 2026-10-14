import Foundation
internal import GRDB

/// Something Lucas jotted down to turn into cards later: the raw text, with an
/// optional note and source. It waits in the inbox until it's refined.
public struct Capture: Sendable {
    public let id: Int64
    public let text: String
    public let note: String?
    public let source: String?
    /// When Lucas captured it.
    public let createdAt: Date
}

extension Capture {
    /// A capture read from a row of the `capture` table.
    init(row: Row) throws {
        id = try row.decode(forColumn: "id")
        text = try row.decode(forColumn: "text")
        note = try row.decode(forColumn: "note")
        source = try row.decode(forColumn: "source")
        createdAt = try row.decode(forColumn: "createdAt")
    }
}
