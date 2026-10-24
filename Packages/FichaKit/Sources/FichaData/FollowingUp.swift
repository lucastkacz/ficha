import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Saves a follow-up: `text`, which Lucas asked in the review panel about
    /// the card with the id `cardID`, cleaned up as `CaptureContent` says,
    /// waits in the inbox tied to that card, with no note and no source, so
    /// that refining turns it into new cards beside it. Unlike capturing, it
    /// doesn't check whether the text repeats a card or a capture: a refine
    /// session sees every front. A follow-up without text isn't saved, nor one
    /// about a card that doesn't exist. Returns the follow-up's capture.
    @discardableResult
    public func followUp(_ cardID: Int64, text: String) throws(EngineError) -> Capture {
        guard let content = CaptureContent(text: text, note: nil, source: nil) else {
            throw .emptyCapture
        }
        let createdAt = time.now
        return try write { db in
            _ = try existingCard(cardID, in: db)
            return try save(content, expanding: nil, followingUp: cardID, at: createdAt, in: db)
        }
    }

    /// Takes back a follow-up Lucas asked in the review panel about the card
    /// with the id `cardID`, as the panel's ⌘Z does: deletes it outright, as
    /// a follow-up undone never was, the way an answer undone leaves the
    /// review log. Discarding stays what it is for any capture. When it no
    /// longer waits in the inbox tied to that card, approved or discarded
    /// since, nothing is taken back, and ⌘Z can't undo it.
    public func takeBackFollowUp(_ captureID: Int64, of cardID: Int64) throws(EngineError) {
        try write { db in
            _ = try existingCard(cardID, in: db)
            try db.execute(
                sql: "DELETE FROM capture WHERE id = ? AND followsUpCardId = ? AND refinedAt IS NULL",
                arguments: [captureID, cardID]
            )
            guard db.changesCount == 1 else {
                throw EngineError.cannotUndoFollowUp(cardID)
            }
        }
    }
}
