import FichaCore
import FichaData
import SwiftUI

extension View {
    /// How fast? over the view while the window `state` runs asks it, as a
    /// deck comes in, with `failure` as the alert over it.
    func howFastSheet(_ state: Binding<CardsWindowState>, failure: Binding<Failure?>) -> some View {
        sheet(
            isPresented: Binding(
                get: { state.wrappedValue.howFast != nil },
                set: { if !$0 { state.wrappedValue.cancelQuestion() } })
        ) {
            if let howFast = state.wrappedValue.howFast {
                HowFastSheet(howFast: howFast) { pace in
                    state.wrappedValue.chooseHowFastPace(pace)
                } putFirst: { isFirst in
                    state.wrappedValue.putHowFastFirst(isFirst)
                } start: {
                    state.wrappedValue.startHowFast()
                } cancel: {
                    state.wrappedValue.cancelQuestion()
                }
                .failureAlert(failure)
            }
        }
    }
}

/// How fast? (ADR 0034, #491), the sheet over the Cards window as a deck
/// comes in, as the mock draws it: the deck's emoji and name, and a line
/// under them, "14 cards · imported" or "No cards yet"; the three paces,
/// Chill, Steady and Faster, as a radio group, each with its new cards a day
/// and, when the deck has new cards, when they're all met at it; where the
/// deck goes in the queue new cards come from, with Put it first, while
/// other decks with new cards are ahead of it; that one pace is for all the
/// user's decks, while they have others; and Cancel, or Escape, and Start,
/// or Return. `CardsWindowState` decides all of it (`HowFast.swift`).
struct HowFastSheet: View {
    let howFast: CardsWindowState.HowFast
    /// Chooses a pace in the radio group.
    let choosePace: (Pace) -> Void
    /// Ticks Put it first, or unticks it.
    let putFirst: (Bool) -> Void
    /// Start.
    let start: () -> Void
    /// Cancel.
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            head
            VStack(alignment: .leading, spacing: 8) {
                Text("How fast?", comment: "The title of How fast?, the Cards window's sheet as a deck comes in.")
                    .font(.headline)
                Picker(selection: Binding(get: { howFast.pace }, set: choosePace)) {
                    ForEach(howFast.paces, id: \.pace) { option in
                        paceRow(option)
                            .tag(option.pace)
                    }
                } label: {
                    Text("Pace", comment: "The name of How fast?'s radio group of paces, which VoiceOver reads.")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            if howFast.offersPutItFirst {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: whereItGoes)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(isOn: Binding(get: { howFast.putsFirst }, set: putFirst)) {
                        Text(
                            "Put it first",
                            comment: "A checkbox of How fast?: the deck coming in goes first in the queue.")
                    }
                }
            }
            if howFast.hasOtherDecks {
                Text(
                    """
                    One pace for all your decks. A deck waits its turn for new cards, so what Ficha asks a day \
                    stays the same.
                    """,
                    comment: "At the foot of How fast?, while the user has other decks."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(
                    String(
                        localized: "Start",
                        comment: "The button of How fast? that sets the pace, and puts the deck first when ticked."),
                    action: start
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// The deck's emoji, or its symbol while it has none, and its name, with
    /// the line under it.
    private var head: some View {
        HStack(spacing: 12) {
            if let emoji {
                Text(verbatim: emoji)
                    .font(.system(size: 32))
            } else {
                Image(systemName: CardGroup.deck(Deck.defaultName).symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.title3)
                    .bold()
                Text(verbatim: howFast.line.text)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The emoji of the deck it asks about, or nil while it shows none, as
    /// for several decks.
    private var emoji: String? {
        switch howFast.subject {
        case .deck: howFast.decks.first?.shownEmoji
        case .decks: nil
        case .fichaDeck(let deck): deck.emoji
        }
    }

    /// The name of the deck it asks about, or of the decks, as a list.
    private var name: String {
        switch howFast.subject {
        case .deck(let deck): Deck.shownName(deck)
        case .decks(let decks): decks.map(Deck.shownName).formatted(.list(type: .and))
        case .fichaDeck(let deck): deck.name
        }
    }

    /// A pace in the radio group: its name, its new cards a day, and when
    /// the deck's new cards are all met at it, when they are.
    private func paceRow(_ option: CardsWindowState.HowFast.PaceOption) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: option.pace.name)
                .bold()
                .frame(minWidth: 56, alignment: .leading)
            Text(verbatim: option.pace.newCardsADay)
                .foregroundStyle(.secondary)
            if let wording = option.wording {
                Text(verbatim: wording.metByText)
            }
        }
    }

    /// Where the deck goes in the queue, as Put it first says: after the
    /// decks ahead of it, or first, with them waiting.
    private var whereItGoes: String {
        let names = howFast.decksAhead.map(Deck.shownName).formatted(.list(type: .and))
        let isOne = howFast.decksAhead.count == 1
        if howFast.putsFirst {
            return isOne
                ? String(
                    localized: "Goes first: \(names) waits until you've met it all.",
                    comment: "In How fast?, with Put it first ticked, with the name of the one deck it goes ahead of.")
                : String(
                    localized: "Goes first: \(names) wait until you've met it all.",
                    comment: "In How fast?, with Put it first ticked, with the names of the decks it goes ahead of.")
        }
        return isOne
            ? String(
                localized: "Goes after \(names), which you're meeting now.",
                comment: "In How fast?, with the name of the deck ahead of the one coming in, in the queue.")
            : String(
                localized: "Goes after \(names), which you're meeting first.",
                comment: "In How fast?, with the names of the decks ahead of the one coming in, in the queue.")
    }
}

extension Pace {
    /// The pace's name, as How fast? says it.
    var name: String {
        switch self {
        case .chill:
            String(localized: "Chill", comment: "A pace in How fast?, the slowest: 1 new card a day.")
        case .steady:
            String(localized: "Steady", comment: "A pace in How fast?, the one Ficha starts at: 2 new cards a day.")
        case .faster:
            String(localized: "Faster", comment: "A pace in How fast?, the fastest: 4 new cards a day.")
        }
    }

    /// How many new cards a day it brings, as How fast? says it: "2 new a
    /// day".
    var newCardsADay: String {
        String(
            localized: "\(newCardsPerDay) new a day",
            comment: "In How fast?, beside a pace's name: how many new cards a day it brings.")
    }
}

extension CardsWindowState.HowFast.Line {
    /// What How fast? says under the deck's name.
    var text: String {
        switch self {
        case .noCards:
            Deck.noCardsYet
        case .imported(let cardCount):
            String(
                localized: "\(cardCount) cards · imported",
                comment: "In How fast?, under the name of the deck an import brought: how many cards it holds.")
        case .fichaDeck(let cardCount):
            String(
                localized: "\(cardCount) cards · one of Ficha's decks",
                comment: "In How fast?, under the name of one of Ficha's decks: how many cards it brings.")
        }
    }
}

extension Deck {
    /// "No cards yet": what a deck with no card says under its name, in its
    /// row in the Cards window's sidebar and in How fast?.
    static var noCardsYet: String {
        String(
            localized: "No cards yet",
            comment: "Under a deck's name in the Cards window's sidebar, or in How fast?: the deck has no card.")
    }
}

extension FinishDate.Wording {
    /// How a finish date reads, as the mock's `formatFinish` writes it:
    /// "today", "Wednesday or Thursday", "Wednesday to Saturday",
    /// "mid-December", "early to mid-December", "late November to early
    /// December".
    var text: String {
        switch self {
        case .day(let day): day.text
        case .dayOrNext(let day, let next): Self.either(day.text, next.text)
        case .days(let first, let last): Self.range(first.text, last.text)
        case .third(let third): third.text
        case .thirds(let first, let last): Self.range(first.text, last.text)
        case .months(let first, let last): Self.range(first.text, last.text)
        }
    }

    /// How How fast? says it, as the mock's `metBy` does: "all met today",
    /// or "all met today or tomorrow", when it starts with today, and else
    /// "all met by mid-December".
    var metByText: String {
        startsToday
            ? String(
                localized: "all met \(text)",
                comment: "In How fast?, beside a pace: when the deck's new cards are all met, starting with today.")
            : String(
                localized: "all met by \(text)",
                comment: "In How fast?, beside a pace: when the deck's new cards are all met, as a day or a month.")
    }

    /// Two days in a row, joined by "or": "Wednesday or Thursday".
    private static func either(_ day: String, _ next: String) -> String {
        String(
            localized: "\(day) or \(next)",
            comment: "A finish date of two days in a row, in the Cards window: “today or tomorrow”.")
    }

    /// Two ends of a finish date, joined by "to": "Wednesday to Saturday",
    /// "early to mid-December", "late November to early December".
    private static func range(_ first: String, _ last: String) -> String {
        String(
            localized: "\(first) to \(last)",
            comment: "A finish date from one day or third of a month to another, in the Cards window.")
    }
}

extension FinishDate.Wording.Day {
    /// The day as a finish date says it: "today", "tomorrow", or its
    /// weekday's name, as the system's formatters write it.
    var text: String {
        switch self {
        case .today:
            String(localized: "today", comment: "A finish date's day, in the Cards window: “on track for today”.")
        case .tomorrow:
            String(localized: "tomorrow", comment: "A finish date's day, in the Cards window: “all met by tomorrow”.")
        case .weekday(let weekday):
            Calendar.current.weekdaySymbols.name(at: weekday - 1)
        }
    }
}

extension FinishDate.Wording.Third {
    /// The third alone, as a finish date's start says it before "to", in
    /// "early to mid-December".
    var text: String {
        switch self {
        case .early:
            String(localized: "early", comment: "A finish date's start, as in “early to mid-December”.")
        case .mid:
            String(localized: "mid", comment: "A finish date's start, as in “mid to late December”.")
        case .late:
            String(localized: "late", comment: "A finish date's start, a month's last third, before “to”.")
        }
    }
}

extension FinishDate.Wording.MonthThird {
    /// The third of its month as a finish date says it, with the month's
    /// name, as the system's formatters write it: "early December",
    /// "mid-December", "late December".
    var text: String {
        let monthName = Calendar.current.monthSymbols.name(at: month - 1)
        return switch third {
        case .early:
            String(localized: "early \(monthName)", comment: "A finish date in the first ten days of a month.")
        case .mid:
            String(localized: "mid-\(monthName)", comment: "A finish date in the days 11 to 20 of a month.")
        case .late:
            String(localized: "late \(monthName)", comment: "A finish date from the day 21 of a month on.")
        }
    }
}

extension [String] {
    /// The name at `index` among a calendar's names, as its weekdays' or its
    /// months', or none for an index it doesn't have.
    fileprivate func name(at index: Int) -> String {
        indices.contains(index) ? self[index] : ""
    }
}
