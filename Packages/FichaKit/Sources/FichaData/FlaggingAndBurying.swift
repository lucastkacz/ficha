import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Flags a card in Lucas's reviews, or set aside, with his note on what
    /// to fix: it waits in the inbox until it's fixed, in a refine session or
    /// in the Cards window. Returns the card.
    @discardableResult
    public func flag(_ cardID: Int64, note: FlagNote) throws(EngineError) -> Card {
        let flaggedAt = time.now
        return try write { db in
            switch try existingCard(cardID, in: db).standing {
            case .inReviews, .setAside: break
            case .inInbox: throw EngineError.cardFlagged(cardID)
            case .buried: throw EngineError.cardBuried(cardID)
            }
            return try updateCard(cardID, setting: "flagNote = ?, flaggedAt = ?", to: [note.text, flaggedAt], in: db)
        }
    }

    /// Fixes a flagged card in the inbox with `content`, as a refine session
    /// drafted it and Lucas approved it: the card leaves the inbox and goes
    /// back to his reviews, on the step its review log puts it on, unless one
    /// of its tags is set aside. Returns the card.
    @discardableResult
    public func fix(_ cardID: Int64, with content: CardContent) throws(EngineError) -> Card {
        try write { db in
            switch try existingCard(cardID, in: db).standing {
            case .inInbox: break
            case .inReviews, .setAside: throw EngineError.cardNotFlagged(cardID)
            case .buried: throw EngineError.cardBuried(cardID)
            }
            return try editCard(cardID, with: content, in: db)
        }
    }

    /// Buries a card: it leaves Lucas's reviews for good, and the inbox if
    /// it's flagged, without deleting it or its review log. Returns the card.
    @discardableResult
    public func bury(_ cardID: Int64) throws(EngineError) -> Card {
        let buriedAt = time.now
        return try write { db in
            try bury(cardID, at: buriedAt, in: db)
        }
    }

    /// Buries the cards with these ids in one write, each as burying one card
    /// does, or none of them when one is already buried or doesn't exist.
    /// Returns the cards, in the order Lucas approved them.
    @discardableResult
    public func bury(_ cardIDs: Set<Int64>) throws(EngineError) -> [Card] {
        let buriedAt = time.now
        return try write { db in
            try cardIDs.sorted().map { try bury($0, at: buriedAt, in: db) }
        }
    }

    /// Unburies a card: it goes back to where it was before Lucas buried it,
    /// his reviews or the inbox, on the step its review log puts it on, or
    /// it's set aside when one of its tags is. Returns the card.
    @discardableResult
    public func unbury(_ cardID: Int64) throws(EngineError) -> Card {
        try write { db in
            try unbury(cardID, in: db)
        }
    }

    /// Unburies the cards with these ids in one write, each as unburying one
    /// card does, or none of them when one isn't buried or doesn't exist.
    /// Returns the cards, in the order Lucas approved them.
    @discardableResult
    public func unbury(_ cardIDs: Set<Int64>) throws(EngineError) -> [Card] {
        try write { db in
            try cardIDs.sorted().map { try unbury($0, in: db) }
        }
    }

    /// Buries the card with this id, as buried at `buriedAt`, and returns it,
    /// or throws when it's already buried or doesn't exist.
    private func bury(_ cardID: Int64, at buriedAt: Date, in db: Database) throws -> Card {
        switch try existingCard(cardID, in: db).standing {
        case .inReviews, .inInbox, .setAside: break
        case .buried: throw EngineError.cardBuried(cardID)
        }
        return try updateCard(cardID, setting: "buriedAt = ?", to: [buriedAt], in: db)
    }

    /// Unburies the card with this id, and returns it, or throws when it isn't
    /// buried or doesn't exist.
    private func unbury(_ cardID: Int64, in db: Database) throws -> Card {
        switch try existingCard(cardID, in: db).standing {
        case .buried: break
        case .inReviews, .inInbox, .setAside: throw EngineError.cardNotBuried(cardID)
        }
        return try updateCard(cardID, setting: "buriedAt = NULL", in: db)
    }
}
