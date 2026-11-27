import FichaCore
import Foundation

// How a card's detail says in words where the card is (#537), as the desktop
// mock's card pane says it: a new card, that it's new; a card the user has
// seen, how many times, "Seen 3 times", and when it's back: now, at a time
// later today, or on a later day, "Back on Tue, Dec 15", or not while it's
// out of the reviews. FSRS's numbers and the review log wait under Details,
// closed until the user opens it. Which words is the window's decision, so
// FichaData works them out here, and the app's views write them from the
// String Catalog, as a finish date's (`FinishDateWording.swift`), with a day
// or a time as the system's date formats write it. Today and a later day are
// Ficha's days, which start at 4:00 (ADR 0045), not the calendar's.

extension CardRow {
    /// How a card's detail says where the card is, in words.
    public enum Wording: Sendable, Hashable {
        /// When a card the user has seen is back, the sooner of its ways when
        /// it goes both ways.
        public enum Back: Sendable, Hashable {
            /// It's due now.
            case now
            /// Later in today's Ficha day, at this time, which can be after
            /// midnight, before the next Ficha day starts at 4:00.
            case today(at: Date)
            /// On a later Ficha day, the start of its date in the engine's
            /// calendar, which the app writes with its weekday, month and
            /// day: "Back on Tue, Dec 15".
            case on(Date)
            /// Not while it's out of the user's reviews, flagged, buried or
            /// set aside, which the detail says above the card.
            case outOfReviews
        }

        /// A new card, which waits its turn in the queue, as its tile in the
        /// grid says.
        case new
        /// A card the user has seen this many times, either way, as
        /// `CardRow.reviews` counts them, back when `back` says. None for a
        /// card an import placed with its progress, which nobody reviewed
        /// in Ficha since.
        case seen(times: Int, back: Back)
    }
}

extension CardsWindowState {
    /// How the detail says where the card in `row` is, in words, from the
    /// engine's time when the window read the cards, by Ficha's days in the
    /// engine's calendar: new while its front-first way is, as its tile
    /// says (`Tile.Mark.new`), since its back-first way comes only after;
    /// and otherwise seen as many times as `CardRow.reviews` counts, and back
    /// now while a way of it is due, as its tile's dot says, later in
    /// today's Ficha day at its sooner way's due time, or on that time's
    /// Ficha day when it's a later one; or not while it's out of the user's
    /// reviews.
    public func wording(of row: CardRow) -> CardRow.Wording {
        if case .new = row.frontFirst.standing {
            return .new
        }
        return .seen(times: row.reviews, back: back(of: row))
    }

    /// When the card in `row`, which the user has seen, is back, as
    /// `wording(of:)` says it.
    private func back(of row: CardRow) -> CardRow.Wording.Back {
        guard case .inReviews = row.cardStanding,
            let due = [row.frontFirst.due, row.backFirst?.due].compactMap(\.self).min()
        else {
            return .outOfReviews
        }
        if row.isDue(at: now) {
            return .now
        }
        let day = engine.calendar.dateOfFichaDay(of: due)
        return day == engine.calendar.dateOfFichaDay(of: now) ? .today(at: due) : .on(day)
    }

    /// Opens Details in the detail of a card, with FSRS's numbers and the
    /// review log, or closes it when `isOpen` is false. It starts closed, and
    /// the window keeps it as it is from card to card while it's open.
    public mutating func setDetailsOpen(_ isOpen: Bool) {
        isDetailsOpen = isOpen
    }
}

/// The hour Ficha's day starts at (ADR 0045), by the device's clock. Until
/// #562 gives FichaCore its one way to tell a time's Ficha day, with this
/// hour from the settings that decide progress, the card's detail counts its
/// days here.
private let fichaDayStartsAtHour = 4

extension Calendar {
    /// The start of the date that names the Ficha day `time` falls in, by
    /// this calendar (ADR 0045): `time`'s own date from 4:00 on, and the
    /// date before until then, so that a night that crosses midnight is one
    /// day. It counts the hour on the clock, so it holds on a day a time
    /// zone moves its clock.
    fileprivate func dateOfFichaDay(of time: Date) -> Date {
        let start = startOfDay(for: time)
        guard component(.hour, from: time) < fichaDayStartsAtHour else {
            return start
        }
        // A moment before the start of `time`'s date is on the date before.
        return startOfDay(for: start.addingTimeInterval(-1))
    }
}
