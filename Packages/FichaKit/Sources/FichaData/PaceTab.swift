import FichaCore
import Foundation

// Settings' Pace tab (ADR 0034, #492), as the desktop mock draws it: How
// fast?, the three paces, each with when every deck in the queue is all met
// at it; and Up next, the queue new cards come from.

/// Settings' Pace tab: How fast?, with the pace the user's new cards a day
/// are ticked, and the queue new cards come from, each deck with when it's
/// all met, and Put it first while it would pass a deck.
public struct PaceTabState: Sendable {
    /// A pace, as How fast? offers it in the tab.
    public struct PaceOption: Sendable, Equatable {
        /// The pace.
        public let pace: Pace
        /// When the last deck in the queue is all met at this pace, as
        /// `ReviewSettings.queue(of:now:calendar:)` gives it: nil while no
        /// deck waits for new cards.
        public let finish: FinishDate?
        /// How the tab says `finish`.
        public let wording: FinishDate.Wording?
    }

    /// A deck in the queue new cards come from, as Up next lists it.
    public struct QueueRow: Sendable, Equatable, Identifiable {
        /// The deck at the top of the tree, with its emoji.
        public let deck: Deck
        /// Its new cards still to meet, as `QueuedDeck.newCards` counts them.
        public let newCards: Int
        /// When the user will have met them all, at their pace: nil with no
        /// new cards a day.
        public let finish: FinishDate?
        /// How the tab says `finish`.
        public let wording: FinishDate.Wording?
        /// Whether its new cards come now: the first deck in the queue.
        public let isNow: Bool
        /// Whether the row offers Put it first: while putting the deck first
        /// would pass a deck ahead of it, any but one listed first for its
        /// priority cards, as How fast?'s Put it first does.
        public let offersPutItFirst: Bool

        public var id: String {
            deck.name
        }
    }

    /// Why Put it first failed, while the tab says so.
    public struct Failure: Sendable, Equatable {
        /// The deck it was for.
        public let deck: String
        public let error: EngineError
    }

    /// The pace the user's new cards a day are, ticked in How fast?: nil
    /// while they're no pace, as a number a version of Ficha before the pace
    /// kept.
    public private(set) var pace: Pace?
    /// Chill, Steady and Faster, in that order.
    public private(set) var paces: [PaceOption] = []
    /// The decks with new cards, in the queue's order.
    public private(set) var queue: [QueueRow] = []
    /// Why the queue couldn't be read, while it can't.
    public private(set) var unreadable: EngineError?
    /// Why Put it first failed, while the tab says so.
    public private(set) var failure: Failure?
    private let engine: Engine

    init(engine: Engine, settings: ReviewSettings) {
        self.engine = engine
        read(settings)
    }

    /// Reads the queue again, at the pace `settings`' new cards a day are,
    /// with their active hours, which count today's new cards.
    public mutating func read(_ settings: ReviewSettings) {}

    /// Puts `deck` first in the queue, as `ficha deck queue --first` does,
    /// and reads the queue again with `settings`, or keeps why it couldn't.
    public mutating func putFirst(_ deck: String, with settings: ReviewSettings) {}

    /// Clears why Put it first failed, once the tab said so and the user
    /// closed it.
    public mutating func dismissFailure() {
        failure = nil
    }
}

extension Engine {
    /// Settings' Pace tab, at the pace `settings`' new cards a day are.
    public func openPaceTab(_ settings: ReviewSettings) -> PaceTabState {
        PaceTabState(engine: self, settings: settings)
    }
}
