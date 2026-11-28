import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Edits a card with its whole content: replaces it with `content`, its
    /// type and its tags included, and its images and sounds, which Ficha
    /// already keeps, and keeps its review log, and so its interval and due
    /// time, and when it came in. Editing a
    /// flagged card fixes it: its flag goes, and it's back in his reviews,
    /// where it stood, unless it's buried, since an edited card stays buried.
    /// An edit that changes its front or back keeps when. An image or a sound
    /// it no longer has goes, unless another card uses it. `deck` moves it to
    /// that deck, as `changeDeck(of:to:)` does, and nil, or the deck it lives
    /// in, leaves it there, which makes no deck on this device. `bothWays`
    /// turns Both ways on or off, as `setBothWays(_:of:)` does, and nil leaves
    /// it as it was. Returns the card. Only the engine's tests edit a card
    /// so: the Cards window saves through
    /// `editFromTheCardsWindow(_:with:deck:bothWays:)`, which leaves the
    /// card's type and tags as they are.
    @discardableResult
    func edit(_ cardID: Int64, with content: CardContent, deck: String? = nil, bothWays: Bool? = nil)
        throws(EngineError) -> Card
    {
        try edit(cardID) { card, editedAt, db in
            try change(card, to: content, deck: deck, bothWays: bothWays, at: editedAt, in: db)
        }
    }

    /// Edits a card as the Cards window saves it, as
    /// `edit(_:with:deck:bothWays:)` does, but with `content`'s sides and
    /// source alone: the write leaves out the card's type and tags columns,
    /// whatever `content` holds, since the window shows neither, and the
    /// database keeps both as they are (#538), a user type this device
    /// doesn't hold yet included, which the card reads as no type.
    @discardableResult
    func editFromTheCardsWindow(_ cardID: Int64, with content: CardContent, deck: String, bothWays: Bool)
        throws(EngineError) -> Card
    {
        try edit(cardID) { card, editedAt, db in
            _ = try replaceSidesAndSource(of: card.id, with: content, at: editedAt, in: db)
            return try setDeckAndBothWays(of: card, deck: deck, bothWays: bothWays, in: db)
        }
    }

    /// Edits a card, as `edit(_:with:deck:bothWays:)` does, with `changing`,
    /// which changes the card as it is, at the edit's time, in the write that
    /// saves it.
    private func edit(_ cardID: Int64, changing: (Card, Date, Database) throws -> Card) throws(EngineError) -> Card {
        let editedAt = time.now
        let (before, edited) = try write { db in
            let before = try existingCard(cardID, in: db)
            _ = try changing(before, editedAt, db)
            return (before, try takeFlagOff(cardID, in: db))
        }
        removeFilesNoCardUses(before: before, after: edited)
        return edited
    }

    /// Turns Both ways on for the cards with these ids when `bothWays` is
    /// true, or off when it's false, in one write, or for none of them when
    /// one doesn't exist. It's an edit that keeps each card's content, review
    /// log and standing, and so when its front or back last changed. Returns
    /// the cards, in the order they came in.
    @discardableResult
    public func setBothWays(_ bothWays: Bool, of cardIDs: Set<Int64>) throws(EngineError) -> [Card] {
        try write { db in
            try cardIDs.sorted().map { try setBothWays(bothWays, of: $0, in: db) }
        }
    }

    /// Turns Both ways on for the card with this id when `bothWays` is true,
    /// or off when it's false, and returns the card as it is then.
    func setBothWays(_ bothWays: Bool, of cardID: Int64, in db: Database) throws -> Card {
        try updateCard(cardID, setting: "bothWays = ?", to: [bothWays], in: db)
    }

    /// Changes `card`, as it is in the write `db`, in that write: replaces
    /// its content with `content` at `now`, as `replaceContent(of:with:at:in:)`
    /// does, moves it to `deck`, as `move(_:to:in:)` does, nil leaving it
    /// where it lives, and turns Both ways on or off as `bothWays` says, nil
    /// leaving it as it was. Returns the card as it is then: how an edit with
    /// a card's whole content and a fix change a card.
    func change(
        _ card: Card, to content: CardContent, deck: String?, bothWays: Bool?, at now: Date, in db: Database
    ) throws -> Card {
        _ = try replaceContent(of: card.id, with: content, at: now, in: db)
        return try setDeckAndBothWays(of: card, deck: deck, bothWays: bothWays, in: db)
    }

    /// Moves `card`, as it is in the write `db`, to `deck`, as
    /// `move(_:to:in:)` does, nil leaving it where it lives, and turns Both
    /// ways on or off as `bothWays` says, nil leaving it as it was, in that
    /// write. Returns the card as it is then.
    private func setDeckAndBothWays(of card: Card, deck: String?, bothWays: Bool?, in db: Database) throws -> Card {
        try move(card, to: deck, in: db)
        if let bothWays {
            _ = try setBothWays(bothWays, of: card.id, in: db)
        }
        return try existingCard(card.id, in: db)
    }
}
