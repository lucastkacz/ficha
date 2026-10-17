import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Saves a capture that Lucas chose to expand, cleaned up as
    /// `CaptureContent` says, and returns it. One that repeats a card's front
    /// waits in the inbox attached to that card, so that refining adds it to
    /// the card. One that repeats a capture in the inbox waits next to it, to
    /// be refined with it, and one that repeats nothing is saved as any
    /// capture is. A capture without text isn't saved.
    @discardableResult
    public func expand(text: String, note: String?, source: String?) throws(EngineError) -> Capture {
        guard let content = CaptureContent(text: text, note: note, source: source) else {
            throw .emptyCapture
        }
        let createdAt = time.now
        return try write { db in
            let expandedCard: Int64? =
                switch try duplicate(of: content.text, in: db) {
                case .card(let card): card.id
                case .capture, nil: nil
                }
            return try save(content, expanding: expandedCard, at: createdAt, in: db)
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
