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
    /// The card stays on the step its review log puts it on, and keeps its
    /// images and sounds, as a draft that leaves them out does
    /// (`approveExpansion(_:into:)` with a `CardDraft`); a new front or back
    /// keeps when it changed. Returns the card.
    @discardableResult
    public func approveExpansion(_ captureID: Int64, into content: CardContent) throws(EngineError) -> Card {
        try approveExpansion(captureID) { card, _ in content.keepingFiles(of: card) }.approved
    }

    /// Approves an expansion in the inbox, as `approveExpansion(_:into:)`
    /// does, with the content `newContent` makes of its card as it is, in the
    /// write that saves it, or nothing when it throws: as a refine session's
    /// draft finds or makes the user type it names in that write
    /// (`CardTypesByName`). Returns the card before and after.
    func approveExpansion(
        _ captureID: Int64, changingContentWith newContent: (Card, Database) throws -> CardContent
    ) throws(EngineError) -> (before: Card, approved: Card) {
        let refinedAt = time.now
        return try write { db in
            guard let cardID = try takeOutOfInbox(captureID, at: refinedAt, in: db).expandsCardID else {
                throw EngineError.notAnExpansion(captureID)
            }
            let card = try existingCard(cardID, in: db)
            switch card.standing {
            case .inReviews, .inInbox, .setAside: break
            case .buried: throw EngineError.cardBuried(cardID)
            }
            return (card, try replaceContent(of: cardID, with: newContent(card, db), at: refinedAt, in: db))
        }
    }
}
