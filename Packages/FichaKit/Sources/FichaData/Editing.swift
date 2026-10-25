import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Edits a card, as Lucas does in the Cards window: replaces its content
    /// with `content`, its images and sounds included, which Ficha already
    /// keeps, and keeps its review log, and so its step and due time, when he
    /// approved it and the capture it came from. Editing a flagged card fixes
    /// it: its flag goes, and it's back in his reviews, on its step, unless
    /// it's buried, since an edited card stays buried. An edit that changes
    /// its front or back keeps when. An image or a sound it no longer has
    /// goes, unless another card uses it. Returns the card.
    @discardableResult
    public func edit(_ cardID: Int64, with content: CardContent) throws(EngineError) -> Card {
        let editedAt = time.now
        let (before, edited) = try write { db in
            let before = try existingCard(cardID, in: db)
            _ = try replaceContent(of: cardID, with: content, at: editedAt, in: db)
            return (before, try takeFlagOff(cardID, in: db))
        }
        removeFilesNoCardUses(before: before, after: edited)
        return edited
    }

    /// Edits a capture in the inbox, as Lucas does in the Cards window:
    /// replaces its text, note and source, cleaned up as `CaptureContent`
    /// says, and keeps when he captured it and, for an expansion, the card it
    /// expands. Unlike capturing, it doesn't check whether the text repeats a
    /// card or a capture. A capture without text isn't saved, nor one that
    /// already left the inbox. Returns the capture.
    @discardableResult
    public func editCapture(_ captureID: Int64, text: String, note: String?, source: String?) throws(EngineError)
        -> Capture
    {
        guard let content = CaptureContent(text: text, note: note, source: source) else {
            throw .emptyCapture
        }
        return try write { db in
            _ = try captureInInbox(captureID, in: db)
            try db.execute(
                sql: "UPDATE capture SET text = ?, note = ?, source = ? WHERE id = ?",
                arguments: [content.text, content.note, content.source, captureID]
            )
            return try captureInInbox(captureID, in: db)
        }
    }
}
