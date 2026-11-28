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
    /// Chill, Steady and Faster, in that order, each with no finish while
    /// the queue can't be read, so the user can still pick one.
    public private(set) var paces: [PaceOption] = []
    /// The decks with new cards, in the queue's order.
    public private(set) var queue: [QueueRow] = []
    /// Why the queue couldn't be read, while it can't.
    public private(set) var unreadable: EngineError?
    /// When the user will have met every deck in the queue, at their pace,
    /// as How fast? says it under the paces: when the last deck is all met,
    /// or nil while no deck waits, the queue can't be read, or with no new
    /// cards a day.
    public var queueMet: FinishDate.Wording? {
        queue.last?.wording
    }
    /// Why Put it first failed, while the tab says so.
    public private(set) var failure: Failure?
    private let engine: Engine

    init(engine: Engine, settings: ReviewSettings) {
        self.engine = engine
        read(settings)
    }

    /// Reads the queue again, at the pace `settings`' new cards a day are,
    /// with their active hours, which count today's new cards, as the queue
    /// is at the engine's time, by its calendar: or keeps why it couldn't.
    public mutating func read(_ settings: ReviewSettings) {
        let now = engine.now
        let calendar = engine.calendar
        let dayStartsAtHour = settings.dayStartsAtHour
        pace = Pace(newCardsPerDay: settings.newCardsPerDay)
        do throws(EngineError) {
            let (cards, own) = try engine.paceTabCards()
            paces = Pace.allCases.map { pace in
                var paced = settings
                paced.newCardsPerDay = pace.newCardsPerDay
                let finish = paced.queue(of: cards, now: now, calendar: calendar).last?.finish
                let wording = finish?.wording(now: now, dayStartsAtHour: dayStartsAtHour, calendar: calendar)
                return PaceOption(pace: pace, finish: finish, wording: wording)
            }
            let inQueue = settings.queue(of: cards, now: now, calendar: calendar)
            queue = inQueue.enumerated().map { place, queued in
                // The decks ahead of it, and those still ahead once it's
                // first, as FichaCore's queue puts it and How fast? reads
                // them: a deck listed first for its priority cards stays
                // ahead.
                let ahead = inQueue.prefix(place).map(\.deck)
                let withItFirst = cards.decksInQueue(putting: queued.deck, at: .first, now: now)
                let stillAhead = withItFirst.prefix { $0 != queued.deck }
                return QueueRow(
                    deck: own.deck(queued.deck),
                    newCards: queued.newCards, finish: queued.finish,
                    wording: queued.finish?.wording(now: now, dayStartsAtHour: dayStartsAtHour, calendar: calendar),
                    isNow: place == 0,
                    offersPutItFirst: ahead.contains { !stillAhead.contains($0) })
            }
            unreadable = nil
        } catch {
            paces = Pace.allCases.map { PaceOption(pace: $0, finish: nil, wording: nil) }
            queue = []
            unreadable = error
        }
    }

    /// Puts `deck` first in the queue, as `ficha deck queue --first` does,
    /// and reads the queue again with `settings`, or keeps why it couldn't.
    public mutating func putFirst(_ deck: String, with settings: ReviewSettings) {
        do throws(EngineError) {
            try engine.moveInQueue(deck: deck, to: .first)
        } catch {
            failure = Failure(deck: deck, error: error)
        }
        read(settings)
    }

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

    /// What the Pace tab reads, in one read: the cards in the user's
    /// reviews, as the planners take them, and what each deck has of its
    /// own, for its emoji.
    fileprivate func paceTabCards() throws(EngineError) -> (cards: CardsInReviews, own: OwnDecks) {
        try read { db in
            (cards: try cardsThatShowUp(in: db).inReviews, own: try OwnDecks(in: db))
        }
    }
}
