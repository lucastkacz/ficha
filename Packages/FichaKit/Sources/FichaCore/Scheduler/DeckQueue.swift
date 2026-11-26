import Foundation

/// When the user will have met every new card of a deck (ADR 0034): a range
/// of days, each the start of its day, from the pace and the new cards of
/// the decks ahead of it in the queue.
public struct FinishDate: Sendable, Hashable, Codable {
    /// The day, if the user has appearances every day.
    public let soonest: Date
    /// The day, if the user has appearances five days a week.
    public let latest: Date

    public init(soonest: Date, latest: Date) {
        self.soonest = soonest
        self.latest = latest
    }
}

/// A deck in the queue new cards come from (ADR 0034): a deck at the top of
/// the tree, with the decks inside it, which still has new cards.
public struct QueuedDeck: Sendable, Hashable {
    /// The deck's whole name, or `""` for Default.
    public let deck: String
    /// Its new cards still to meet, each way a card goes counting as one, as
    /// the day's new cards count them.
    public let newCards: Int
    /// When the user will have met them all, or nil when the pace brings no
    /// new card.
    public let finish: FinishDate?

    public init(deck: String, newCards: Int, finish: FinishDate?) {
        self.deck = deck
        self.newCards = newCards
        self.finish = finish
    }
}

/// Where a deck goes in the queue when the user moves it.
public enum QueuePosition: Sendable, Hashable {
    /// Ahead of every other deck.
    case first
    /// After every other deck.
    case last
    /// At this index among the other decks of the queue, from 0, the first.
    case at(Int)
}

extension ReviewSettings {
    /// The queue new cards come from at `now`, out of `cards`.
    public func queue(of cards: CardsInReviews, now: Date, calendar: Calendar) throws(SchedulingError)
        -> [QueuedDeck]
    {
        []
    }
}

extension CardsInReviews {
    /// The place that puts `deck` at `position` in the queue.
    public func place(putting deck: String, at position: QueuePosition, now: Date) -> Date {
        now
    }
}
