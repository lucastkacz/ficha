import FichaCore
import Foundation
internal import GRDB

// The queue new cards come from (ADR 0034): the decks at the top of the
// tree, each at its place, the first one's new cards first, at the pace. A
// deck takes its place when its first card came in, so a deck that comes in
// goes last; the user can move it, and then it keeps the place it moved to,
// a field of its own that syncs. Which cards come first is decided in
// FichaCore's `CardsInReviews` and `DeckQueue.swift`, whose changes
// `make upload` lists.

extension Engine {
    /// The queue new cards come from now, with `settings`' pace: each deck at
    /// the top of the tree that still has new cards, in the order they come,
    /// with its finish date, by the engine's calendar.
    public func queue(_ settings: ReviewSettings) throws(EngineError) -> [QueuedDeck] {
        let now = time.now
        return try read { db in
            settings.queue(of: try cardsThatShowUp(in: db).inReviews, now: now, calendar: calendar)
        }
    }

    /// Moves `deck` to `position` in the queue new cards come from, among
    /// the other decks that have new cards, from the next appearance, review
    /// now or "See more" on: a deck at the top of the tree, or else the one
    /// at the top it sits inside, which it comes with. It keeps its place
    /// while it's set aside, and the place waits to be sent to the user's
    /// other devices. A deck that isn't there is made, as
    /// `setAside(deck:)` says.
    public func moveInQueue(deck: String, to position: QueuePosition) throws(EngineError) {
        let top = TagPath.top(of: try checkedDeckOrDefault(deck))
        let now = time.now
        try write { db in
            let place = try cardsThatShowUp(in: db).inReviews.place(putting: top, at: position, now: now)
            try changeOwnDecks([top], in: db) { $0.queuePlace = place }
        }
    }
}
