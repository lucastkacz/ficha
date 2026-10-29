import FichaCore
import Foundation
internal import GRDB

/// Flagging, unflagging, burying and unburying, taking a flag off as editing
/// does (`takeFlagOff(_:in:)`, below), and taking a flag and a burial as
/// another device left them, as sync does (`takeFlag(_:of:in:)` and
/// `takeBurial(_:of:in:)`, below): this file is the one place that sets
/// and clears a card's flag and its burial, as `CODING_STANDARDS.md` says.
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
    /// of its tags is set aside. It keeps its images and sounds, as a draft
    /// that leaves them out does (`fix(_:with:)` with a `CardDraft`); a new
    /// front or back keeps when it changed. Returns the card.
    @discardableResult
    public func fix(_ cardID: Int64, with content: CardContent) throws(EngineError) -> Card {
        try fix(cardID) { card, _ in content.keepingFiles(of: card) }.fixed
    }

    /// Fixes a flagged card in the inbox, as `fix(_:with:)` does, with the
    /// content `newContent` makes of the card as it is, in the write that
    /// saves it, or nothing when it throws: as a refine session's draft finds
    /// or makes the user type it names in that write (`CardTypesByName`).
    /// `bothWays` turns Both ways on or off, as `setBothWays(_:of:)` does,
    /// and nil leaves it as it was. Returns the card before and after.
    func fix(
        _ cardID: Int64, bothWays: Bool? = nil, changingContentWith newContent: (Card, Database) throws -> CardContent
    ) throws(EngineError) -> (before: Card, fixed: Card) {
        let fixedAt = time.now
        return try write { db in
            let card = try unflag(cardID, in: db)
            let fixed = try replaceContent(of: cardID, with: newContent(card, db), at: fixedAt, in: db)
            guard let bothWays else {
                return (card, fixed)
            }
            return (card, try setBothWays(bothWays, of: cardID, in: db))
        }
    }

    /// Unflags a flagged card in the inbox: its flag goes and its content
    /// stays, and it goes back to Lucas's reviews, on the step its review log
    /// puts it on, unless one of its tags, or a tag one of them sits inside,
    /// is set aside. The review panel's ⌘Z unflags a card Lucas flagged
    /// there. Returns the card.
    @discardableResult
    public func unflag(_ cardID: Int64) throws(EngineError) -> Card {
        try write { db in
            try unflag(cardID, in: db)
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

    /// Unflags the card with this id, and returns it, or throws when it isn't
    /// flagged in the inbox, as a buried card isn't, or doesn't exist.
    private func unflag(_ cardID: Int64, in db: Database) throws -> Card {
        switch try existingCard(cardID, in: db).standing {
        case .inInbox: break
        case .inReviews, .setAside: throw EngineError.cardNotFlagged(cardID)
        case .buried: throw EngineError.cardBuried(cardID)
        }
        return try takeFlagOff(cardID, in: db)
    }

    /// Buries the card with this id, as buried at `buriedAt`, and returns it,
    /// or throws when it's already buried or doesn't exist. An import buries
    /// here a card that was suspended in the app it comes from.
    func bury(_ cardID: Int64, at buriedAt: Date, in db: Database) throws -> Card {
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

/// Takes the flag off the card with this id, if it has one, buried or not,
/// and returns the card, or throws when it doesn't exist: unflagging it, and
/// editing it, which fixes a flagged card, buried too.
func takeFlagOff(_ cardID: Int64, in db: Database) throws -> Card {
    try updateCard(cardID, setting: "flagNote = NULL, flaggedAt = NULL", in: db)
}

/// Leaves the card with this id flagged with `flag`, or without a flag when
/// it's nil, as another device left it, whatever the card stands as here,
/// and returns the card, or throws when it doesn't exist: how sync takes a
/// flag that changed later on another device (ADR 0017).
func takeFlag(_ flag: Flag?, of cardID: Int64, in db: Database) throws -> Card {
    try updateCard(cardID, setting: "flagNote = ?, flaggedAt = ?", to: [flag?.note, flag?.flaggedAt], in: db)
}

/// Leaves the card with this id buried since `buriedAt`, or not buried when
/// it's nil, as another device left it, whatever the card stands as here,
/// and returns the card, or throws when it doesn't exist: how sync takes a
/// burial that changed later on another device (ADR 0017).
func takeBurial(_ buriedAt: Date?, of cardID: Int64, in db: Database) throws -> Card {
    try updateCard(cardID, setting: "buriedAt = ?", to: [buriedAt], in: db)
}
