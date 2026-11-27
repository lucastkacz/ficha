import FichaCore
import Foundation
internal import GRDB

// The queue new cards come from (ADR 0034): the decks at the top of the
// tree, each at its place, the first one's new cards first, at the pace. A
// deck takes its place when its first card came in, so a deck that comes in
// goes last; the user can move it, and then it keeps the place it moved to,
// and the decks it passed theirs, or those it parted from a deck that came in
// at once, a field of each that syncs. Which cards come first is decided in
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

    /// The decks at the top of the tree the user has met in full now, out of
    /// the queue new cards come from, as `CardsInReviews.decksMetInFull`
    /// says, by their whole names, or Default by `Deck.defaultName`.
    public func decksMetInFull() throws(EngineError) -> Set<String> {
        try read { db in try cardsThatShowUp(in: db).inReviews.decksMetInFull }
    }

    /// Moves `deck` to `position` in the queue new cards come from, among
    /// the other decks that have new cards, as `queue(_:)` lists them, from
    /// the next appearance, review now or "See more" on: a deck at the top
    /// of the tree, or else the one at the top it sits inside, which it
    /// comes with. The decks it passes take each other's places, and those
    /// it parts from a deck that came in at once take new ones, as
    /// `CardsInReviews.places(putting:at:now:)` shares them out. Each keeps
    /// its place while it's set aside, and the places wait to be sent to the
    /// user's other devices. A deck that isn't there is made, as
    /// `setAside(deck:)` says.
    public func moveInQueue(deck: String, to position: QueuePosition) throws(EngineError) {
        let top = TagPath.top(of: try checkedDeckOrDefault(deck))
        let now = time.now
        try write { db in
            let places = try cardsThatShowUp(in: db).inReviews.places(putting: top, at: position, now: now)
            for (name, place) in places.sorted(by: { $0.key < $1.key }) {
                try changeOwnDecks([name], in: db) { $0.queuePlace = place }
            }
        }
    }
}
