import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Saves a duplicate that Lucas chose to expand, cleaned up as
    /// `CaptureContent` says, and returns it. One that repeats a card waits in
    /// the inbox attached to that card, as an expansion, so that refining adds
    /// it to the card; so does one that repeats an expansion, attached to its
    /// card. One that repeats another capture in the inbox waits next to it,
    /// to be refined with it, and one that repeats nothing is saved as any
    /// capture is. A capture without text isn't saved.
    @discardableResult
    public func expand(text: String, note: String?, source: String?) throws(EngineError) -> Capture {
        guard let content = CaptureContent(text: text, note: note, source: source) else {
            throw .emptyCapture
        }
        let createdAt = time.now
        return try write { db in
            let expandedCardID: Int64? =
                switch try repeated(by: content.text, in: db) {
                case .card(let card): card.id
                case .capture(let capture): capture.expandsCardID
                case nil: nil
                }
            return try save(content, expanding: expandedCardID, at: createdAt, in: db)
        }
    }

    /// Approves an expansion in the inbox: replaces its card's content with
    /// `content`, which a refine session drafted from the card and the
    /// expansion and Lucas approved, and takes the expansion out of the inbox.
    /// The card stays on the step its review log puts it on. Returns the card.
    @discardableResult
    public func approveExpansion(_ captureID: Int64, into content: CardContent) throws(EngineError) -> Card {
        let refinedAt = time.now
        return try write { db in
            guard let cardID = try takeOutOfInbox(captureID, at: refinedAt, in: db).expandsCardID else {
                throw EngineError.notAnExpansion(captureID)
            }
            guard try existingCard(cardID, in: db).buriedAt == nil else {
                throw EngineError.cardBuried(cardID)
            }
            return try replaceContent(of: cardID, with: content, in: db)
        }
    }
}
