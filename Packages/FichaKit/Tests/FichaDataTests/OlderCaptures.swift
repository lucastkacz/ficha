import FichaCore
import Foundation
import GRDB

@testable import FichaData

// The captures the database keeps unread since Ficha took Capture and the
// inbox out (ADR 0041, #540), which sync still carries between devices, as
// an older version of Ficha on another device may still capture, approve,
// expand, follow up and discard: the tests write them as that version did,
// and read them back as the database keeps them.

extension Engine {
    /// Saves a capture with this text, note and source, as an older version
    /// of Ficha did, expanding the card with the id `expandedCardID`, or
    /// following up the one with the id `followedUpCardID`, if there's one,
    /// in a write that records its change to sync, and returns it.
    @discardableResult
    func olderCapture(
        _ text: String, note: String? = nil, source: String? = nil, expanding expandedCardID: Int64? = nil,
        followingUp followedUpCardID: Int64? = nil
    ) throws -> Capture {
        let createdAt = now
        return try write { db in
            try db.execute(
                sql: """
                    INSERT INTO capture (text, note, source, createdAt, expandsCardId, followsUpCardId)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [text, note, source, createdAt, expandedCardID, followedUpCardID])
            return Capture(
                id: db.lastInsertedRowID, text: text, note: note, source: source, createdAt: createdAt,
                expandsCardID: expandedCardID, followsUpCardID: followedUpCardID)
        }
    }

    /// Takes the capture with this id out of the inbox an older version of
    /// Ficha had, as discarding it there did, in a write that records its
    /// change to sync.
    func refineOlderCapture(_ captureID: Int64) throws {
        let refinedAt = now
        try write { db in
            try db.execute(sql: "UPDATE capture SET refinedAt = ? WHERE id = ?", arguments: [refinedAt, captureID])
        }
    }

    /// Approves the capture with this id into a card for each of `contents`,
    /// in Default, as an older version of Ficha did: each card remembers the
    /// capture, which leaves that version's inbox, in a write that records
    /// both changes to sync. Returns the cards.
    @discardableResult
    func approveOlderCapture(_ captureID: Int64, into contents: [CardContent]) throws -> [Card] {
        let approvedAt = now
        return try write { db in
            let cardIDs = try contents.map { content in
                let cardID = try insertCard(content, at: approvedAt, in: db)
                try db.execute(sql: "UPDATE card SET captureId = ? WHERE id = ?", arguments: [captureID, cardID])
                return cardID
            }
            try db.execute(sql: "UPDATE capture SET refinedAt = ? WHERE id = ?", arguments: [approvedAt, captureID])
            return try cardIDs.map { try existingCard($0, in: db) }
        }
    }

    /// Deletes the capture with this id, as an older version of Ficha did
    /// when its review panel's ⌘Z took a follow-up back, in a write that
    /// records the deletion to sync.
    func takeBackOlderCapture(_ captureID: Int64) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM capture WHERE id = ?", arguments: [captureID])
        }
    }

    /// Every capture, as the database keeps it, oldest first, with whether
    /// an older version of Ficha took it out of its inbox.
    func olderCaptures() throws -> [(capture: Capture, isRefined: Bool)] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM capture ORDER BY id").map { row in
                let refinedAt: Date? = try row.decode(forColumn: "refinedAt")
                return (try Capture(row: row), refinedAt != nil)
            }
        }
    }

    /// The id of the capture each card came from, as an older version of
    /// Ficha approved it, by card in the order they came in, or nil for a
    /// card that came from none.
    func capturesCardsCameFrom() throws -> [Int64?] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT captureId FROM card ORDER BY id").map { row in
                let captureID: Int64? = try row.decode(forColumn: "captureId")
                return captureID
            }
        }
    }

    /// The captures the database keeps, as an older version of Ficha showed
    /// them in its inbox, for a test to compare two devices'.
    func capturesAsSeen() throws -> CapturesAsSeen {
        let fronts = Dictionary(uniqueKeysWithValues: try cards().map { ($0.id, $0.front) })
        let captures = try olderCaptures()
        func seen(_ capture: Capture) -> String {
            if let cardID = capture.expandsCardID, let front = fronts[cardID] {
                return "\(capture.text), expanding \(front)"
            } else if let cardID = capture.followsUpCardID, let front = fronts[cardID] {
                return "\(capture.text), following up \(front)"
            }
            return capture.text
        }
        return CapturesAsSeen(
            waiting: captures.filter { !$0.isRefined }.map { seen($0.capture) }.sorted(),
            refined: captures.filter(\.isRefined).map { seen($0.capture) }.sorted())
    }
}

/// The captures a device's database keeps, as an older version of Ficha
/// showed them: each one's text, with the front of the card it expands or
/// follows up, since each device numbers its cards as they come to it, those
/// still in that version's inbox apart from those it took out, each sorted.
struct CapturesAsSeen: Equatable {
    let waiting: [String]
    let refined: [String]
}
