import Foundation

// How a card's detail says in words where the card is (#537), as the desktop
// mock's card pane says it: a new card, that it's new; a card the user has
// seen, how many times, "Seen 3 times", and when it's back: now, at a time
// later today, or on a later day, "Back on Tue, Dec 15". FSRS's numbers wait
// under Details. Which words is the window's decision, so FichaData works
// them out here, and the app's views write them from the String Catalog, as
// a finish date's (`FinishDateWording.swift`), with a day or a time as the
// system's date formats write it.

extension CardRow {
    /// How a card's detail says where the card is, in words.
    public enum Wording: Sendable, Hashable {
        /// When a card the user has seen is back, the sooner of its ways when
        /// it goes both ways.
        public enum Back: Sendable, Hashable {
            /// It's due now.
            case now
            /// Later today, at this time.
            case today(at: Date)
            /// On a later day, the start of it in the engine's calendar, which
            /// the app writes with its weekday, month and day: "Back on Tue,
            /// Dec 15".
            case on(Date)
            /// Not while it's out of the user's reviews, flagged or set aside,
            /// which the detail says.
            case outOfReviews
        }

        /// A new card, which waits its turn in the queue.
        case new
        /// A card the user has seen this many times, either way, as
        /// `CardRow.reviews` counts them, back when `back` says.
        case seen(times: Int, back: Back)
    }
}

extension CardsWindowState {
    // Stub for #537: the code round replaces it.
    /// A stub for #537, which says the same of every card: how the detail
    /// says where the card in `row` is, in words, from the engine's time when
    /// the window read the cards, by the engine's calendar.
    public func wording(of row: CardRow) -> CardRow.Wording {
        .seen(times: 0, back: .outOfReviews)
    }
}
