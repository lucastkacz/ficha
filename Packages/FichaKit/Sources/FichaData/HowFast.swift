import FichaCore
import Foundation

// How fast? (ADR 0034, #491): a sheet over the Cards window, as a deck comes
// in, that asks how fast new cards come, for every deck together, and where
// the deck goes in the queue new cards come from. It opens after the New Deck
// sheet's OK makes a deck from the sidebar or a deck's menu, with the paces
// alone, and after an import that brought new cards, once its sheet's Done
// closes it. Start saves the pace as `ficha pace` does, and puts the deck
// first as `ficha deck queue --first` does, when Put it first is ticked;
// Cancel changes nothing, so a deck that came in stays last, where it came.

extension CardsWindowState {
    /// How fast?, while the window asks it: the deck it asks about, the three
    /// paces, each with its new cards a day and, when the deck has new cards,
    /// when they're all met, and where the deck goes in the queue.
    public struct HowFast: Sendable, Equatable {
        /// What How fast? asks about.
        public enum Subject: Sendable, Equatable {
            /// The deck at the top of the tree, by its whole name, or Default
            /// by `Deck.defaultName`, that New Deck…'s OK just made, or that
            /// an import's new cards all came into.
            case deck(String)
            /// The decks at the top of the tree an import's new cards came
            /// into, when they're several, in the queue's order: the paces
            /// then say when the last of them is all met.
            case decks([String])
        }

        /// What the line under the deck's name says.
        public enum Line: Sendable, Equatable {
            /// "No cards yet": the deck New Deck…'s OK just made.
            case noCards
            /// "14 cards · imported": the deck an import's new cards came
            /// into, with its cards and those of the decks inside it.
            case imported(cardCount: Int)
        }

        /// A pace, as How fast? offers it, in its radio group.
        public struct PaceOption: Sendable, Equatable {
            /// The pace, whose new cards a day the option says: "2 new a
            /// day".
            public let pace: Pace
            /// When the deck's new cards are all met at this pace, where it
            /// goes in the queue as Put it first says, as
            /// `ReviewSettings.queue(of:now:calendar:)` gives it once the
            /// deck is there: nil when the deck has no new card.
            public let finish: FinishDate?
            /// How the sheet says `finish`: "all met by mid-December".
            public let wording: FinishDate.Wording?
        }

        /// What it asks about.
        public let subject: Subject
        /// What the line under the deck's name says.
        public let line: Line
        /// The pace Start saves, ticked in the radio group: the user's as
        /// the sheet opens, or Steady while their new cards a day are no
        /// pace, until they choose another.
        public internal(set) var pace: Pace
        /// The decks at the top of the tree with new cards ahead of the deck
        /// in the queue, in its order, the first the one the user is meeting
        /// now: "Goes after Arte, which you're meeting now." Put it first is
        /// offered while there are some, for a deck with new cards.
        public let decksAhead: [String]
        /// Whether Put it first is ticked: unticked as the sheet opens.
        public internal(set) var putsFirst: Bool
        /// Whether the user has other decks, so the sheet says one pace is
        /// for all of them, and that a deck waits its turn for new cards.
        public let hasOtherDecks: Bool

        /// Whether the sheet offers Put it first: while other decks with new
        /// cards are ahead of the deck.
        public var offersPutItFirst: Bool {
            !decksAhead.isEmpty
        }

        /// Chill, Steady and Faster, in that order, each with when the deck's
        /// new cards are all met at it, where the deck goes as Put it first
        /// says. Not worked out yet (#491): none.
        public var paces: [PaceOption] {
            []
        }
    }

    /// How fast?, while the window asks it.
    public var howFast: HowFast? {
        guard case .howFast(let howFast) = question else { return nil }
        return howFast
    }

    /// Chooses `pace` in How fast?'s radio group, which Start saves. Not
    /// worked out yet (#491): it chooses none.
    public mutating func chooseHowFastPace(_ pace: Pace) {}

    /// Ticks How fast?'s Put it first, or unticks it when `isFirst` is
    /// false, while it's offered: the paces then say when the deck's new
    /// cards are all met with the deck first in the queue. Not worked out yet
    /// (#491): it ticks nothing.
    public mutating func putHowFastFirst(_ isFirst: Bool) {}

    /// Chooses Start in How fast?: saves the pace chosen, when it changed,
    /// through `Engine.saveProgressSettings(_:changedFrom:)`, as `ficha pace`
    /// does, puts the deck first through `Engine.moveInQueue(deck:to:)`, as
    /// `ficha deck queue --first` does, when Put it first is ticked, and
    /// reads the cards again; or records why it couldn't and goes on asking.
    /// Not worked out yet (#491): it does nothing.
    public mutating func startHowFast() {}
}
