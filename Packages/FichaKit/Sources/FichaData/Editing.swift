import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Edits a card, as Lucas does in the Cards window: replaces its content
    /// with `content`, and keeps its review log, and so its step and due
    /// time, when he approved it and the capture it came from. Editing a
    /// flagged card fixes it: its flag goes, and it's back in his reviews, on
    /// its step, unless it's buried, since an edited card stays buried.
    /// Returns the card.
    @discardableResult
    public func edit(_ cardID: Int64, with content: CardContent) throws(EngineError) -> Card {
        try write { db in
            try editCard(cardID, with: content, in: db)
        }
    }
}

/// Gives the card with this id `content` and takes its flag away, keeping the
/// rest: an edit in the Cards window, and the fix a refine session makes once
/// it checked the card is flagged and not buried.
func editCard(_ cardID: Int64, with content: CardContent, in db: Database) throws -> Card {
    try replaceContent(of: cardID, with: content, alsoSetting: "flagNote = NULL, flaggedAt = NULL", in: db)
}
