import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Flags a card in Lucas's reviews with his note on what to fix: it
    /// leaves his reviews and waits in the inbox until a refine session fixes
    /// it. Returns the card.
    @discardableResult
    public func flag(_ cardID: Int64, note: FlagNote) throws(EngineError) -> Card {
        let flaggedAt = time.now
        return try write { db in
            _ = try cardInReviews(cardID, in: db)
            return try updateCard(cardID, setting: "flagNote = ?, flaggedAt = ?", to: [note.text, flaggedAt], in: db)
        }
    }

    /// Fixes a flagged card in the inbox with `content`, as a refine session
    /// drafted it and Lucas approved it: the card leaves the inbox and goes
    /// back to his reviews, on the step its review log puts it on. Returns the
    /// card.
    @discardableResult
    public func fix(_ cardID: Int64, with content: CardContent) throws(EngineError) -> Card {
        try write { db in
            let card = try existingCard(cardID, in: db)
            guard card.buriedAt == nil else {
                throw EngineError.cardBuried(cardID)
            }
            guard card.flag != nil else {
                throw EngineError.cardNotFlagged(cardID)
            }
            return try replaceContent(
                of: cardID, with: content, alsoSetting: "flagNote = NULL, flaggedAt = NULL", in: db)
        }
    }

    /// Buries a card: it leaves Lucas's reviews for good, and the inbox if
    /// it's flagged, without deleting it or its review log. Returns the card.
    @discardableResult
    public func bury(_ cardID: Int64) throws(EngineError) -> Card {
        let buriedAt = time.now
        return try write { db in
            guard try existingCard(cardID, in: db).buriedAt == nil else {
                throw EngineError.cardBuried(cardID)
            }
            return try updateCard(cardID, setting: "buriedAt = ?", to: [buriedAt], in: db)
        }
    }

    /// Unburies a card: it goes back to where it was before Lucas buried it,
    /// his reviews or the inbox, on the step its review log puts it on.
    /// Returns the card.
    @discardableResult
    public func unbury(_ cardID: Int64) throws(EngineError) -> Card {
        try write { db in
            guard try existingCard(cardID, in: db).buriedAt != nil else {
                throw EngineError.cardNotBuried(cardID)
            }
            return try updateCard(cardID, setting: "buriedAt = NULL", in: db)
        }
    }
}
