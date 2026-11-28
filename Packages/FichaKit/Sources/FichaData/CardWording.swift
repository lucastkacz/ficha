import FichaCore
import Foundation

// How a card's detail says in words where the card is (#537), as the desktop
// mock's card pane says it: a new card in the reviews, that it's new; a card
// the user has seen, how many times, "Seen 3 times", and when it's back: now,
// at a time later today, or on a later day, "Back on Tue, Dec 15", with its
// year when it isn't this year's; or not while it's out of the reviews, new
// or not. Its days are Ficha's (ADR 0045). FSRS's numbers and the review log
// wait under Details, closed until the user opens it. Which words is the
// window's decision, so FichaData works them out here, and the app's views
// write them from the String Catalog, as a finish date's
// (`FinishDateWording.swift`), with a day or a time as the system's date
// formats write it.

extension CardRow {
    /// How a card's detail says where the card is, in words.
    public enum Wording: Sendable, Hashable {
        /// When a card is back, the sooner of its ways when it goes both
        /// ways.
        public enum Back: Sendable, Hashable {
            /// It's due now.
            case now
            /// Later in today's Ficha's day, at this time.
            case today(at: Date)
            /// On a later Ficha's day, as the start of the calendar day it
            /// starts on, in the engine's calendar, which the app writes with
            /// its weekday, month and day, "Back on Tue, Dec 15", and its
            /// year too unless `inThisYear`: whether that day is in the year
            /// of today's Ficha's day.
            case on(Date, inThisYear: Bool)
            /// Not while it's out of the user's reviews, flagged or set aside,
            /// which the detail says above the card.
            case outOfReviews
        }

        /// A new card in the user's reviews, which waits its turn in the
        /// queue, as its tile in the grid says.
        case new
        /// A card the user has seen this many times, either way, as
        /// `CardRow.reviews` counts them, back when `back` says. None for a
        /// card an import placed with its progress, which nobody reviewed in
        /// Ficha since, and for a new card out of the user's reviews, which
        /// waits no turn while it's out.
        case seen(times: Int, back: Back)
    }
}

extension CardsWindowState {
    /// How the detail says where the card in `row` is, in words, from the
    /// engine's time when the window read the cards, by Ficha's days, which
    /// start at the hour `dayStartsAtHour` the window read with them: new
    /// while its front-first way is, as its tile says (`Tile.Mark.new`),
    /// since its back-first way comes only after, and it's in the user's
    /// reviews; and otherwise seen as many times as `CardRow.reviews` counts,
    /// and back now while a way of it is due, as its tile's dot says, later
    /// today at its sooner way's due time, while that time falls in today's
    /// Ficha's day, or else on the calendar day that time's Ficha's day
    /// starts on; or not while it's out of the user's reviews.
    public func wording(of row: CardRow) -> CardRow.Wording {
        if case .new = row.frontFirst.standing, case .inReviews = row.cardStanding {
            return .new
        }
        return .seen(times: row.reviews, back: back(of: row))
    }

    /// When the card in `row` is back, as `wording(of:)` says it.
    private func back(of row: CardRow) -> CardRow.Wording.Back {
        guard case .inReviews = row.cardStanding,
            let due = [row.frontFirst.due, row.backFirst?.due].compactMap(\.self).min()
        else {
            return .outOfReviews
        }
        if row.isDue(at: now) {
            return .now
        }
        let calendar = engine.calendar
        let today = calendar.calendarDay(ofFichasDayOf: now, startingAt: dayStartsAtHour)
        let day = calendar.calendarDay(ofFichasDayOf: due, startingAt: dayStartsAtHour)
        guard day != today else {
            return .today(at: due)
        }
        return .on(day, inThisYear: calendar.isDate(day, equalTo: today, toGranularity: .year))
    }

    /// Opens Details in the detail of a card, with FSRS's numbers and the
    /// review log, or closes it when `isOpen` is false. It starts closed, and
    /// the window keeps it as it is from card to card while it's open.
    public mutating func setDetailsOpen(_ isOpen: Bool) {
        isDetailsOpen = isOpen
    }
}
