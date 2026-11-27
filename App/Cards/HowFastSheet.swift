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
/// comes in, as the mock draws it: the deck's emoji and name, or the names
/// of the decks an import made, with no emoji, and a line under them, "14
/// cards · imported from Arte.apkg", "40 cards · one of Ficha's decks" or
/// "No cards yet"; the three paces, Chill, Steady and Faster, each a tile
/// with its radio, its new cards a day and, when the deck has new cards,
/// when they're all met at it, the chosen one in the accent; where the deck
/// goes in the queue new cards come from, while a deck with new cards is
/// ahead of it, with Put it first while it would pass one, any but a deck
/// listed first for its priority cards; that one pace is for all the user's
/// decks, while they have others; and Cancel, with esc, and Start, or
/// Create after New Deck…, with ↩. It's never narrower than the mock's, and
/// widens so that a label fits whole. `CardsWindowState` decides all of it
/// (`HowFast.swift`).
struct HowFastSheet: View {
    let howFast: CardsWindowState.HowFast
    /// Chooses a pace among the tiles.
    let choosePace: (Pace) -> Void
    /// Ticks Put it first, or unticks it.
    let putFirst: (Bool) -> Void
    /// Start.
    let start: () -> Void
    /// Cancel.
    let cancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            head
            VStack(alignment: .leading, spacing: 8) {
                Text("How fast?", comment: "The title of How fast?, the Cards window's sheet as a deck comes in.")
                    .font(.headline)
                VStack(spacing: 6) {
                    ForEach(howFast.paces, id: \.pace) { option in
                        paceTile(option)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    Text("Pace", comment: "The name of How fast?'s group of paces, which VoiceOver reads."))
                if howFast.offersPutItFirst {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            whereItGoesText
                            putItFirst
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            whereItGoesText
                            putItFirst
                        }
                    }
                } else if howFast.saysWhereItGoes {
                    whereItGoesText
                }
                if howFast.hasOtherDecks {
                    Text(
                        """
                        One pace for all your decks. A deck waits its turn for new cards, so what Ficha asks a day \
                        stays the same.
                        """,
                        comment: "At the foot of How fast?, while the user has other decks."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button(action: cancel) {
                    KeyLabel(
                        title: Text("Cancel"),
                        key: String(localized: "esc", comment: "The Esc key's name, next to the button it presses."))
                }
                .keyboardShortcut(.cancelAction)
                Button(action: start) {
                    KeyLabel(title: startTitle, key: "↩")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(minWidth: 440, idealWidth: 440, alignment: .leading)
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
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: howFast.line.text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// The main button's title: Create after New Deck…, for the deck it made
    /// with no card, as the mock's sheet makes it, and Start otherwise.
    private var startTitle: Text {
        howFast.line == .noCards
            ? Text("Create", comment: "The button of How fast? after New Deck…: sets the pace for the new deck.")
            : Text("Start", comment: "The button of How fast? that sets the pace, and puts the deck first when ticked.")
    }

    /// A pace as a tile, which a click chooses: its radio, its name, its new
    /// cards a day, and, at the trailing side, when the deck's new cards are
    /// all met at it, when they are, which wraps; the chosen one filled with
    /// the mock's `--selection`, the accent at 16% in light mode and 30% in
    /// dark, and outlined in the accent, as the mock's `.pace-row` is.
    private func paceTile(_ option: CardsWindowState.HowFast.PaceOption) -> some View {
        let isChosen = option.pace == howFast.pace
        return Button {
            choosePace(option.pace)
        } label: {
            HStack(spacing: 8) {
                PaceRadio(isChosen: isChosen)
                    .frame(width: 18)
                Text(verbatim: option.pace.name)
                    .bold()
                    .frame(minWidth: 58, alignment: .leading)
                Text(verbatim: option.pace.newCardsADay)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 8)
                if let wording = option.wording {
                    Text(verbatim: wording.metByText)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background {
                if isChosen {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.tint.opacity(colorScheme == .dark ? 0.3 : 0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.tint, lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.fill.quaternary)
                }
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    /// Where the deck goes in the queue, as `whereItGoes` says it.
    private var whereItGoesText: some View {
        Text(verbatim: whereItGoes)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Put it first, after where the deck goes, as the mock's checkbox is.
    private var putItFirst: some View {
        Toggle(isOn: Binding(get: { howFast.putsFirst }, set: { putFirst($0) })) {
            Text("Put it first", comment: "A checkbox of How fast?: the deck coming in goes first in the queue.")
        }
        .font(.callout)
        .fixedSize()
    }

    /// Where the deck goes in the queue, as Put it first says: after the
    /// decks ahead of it; or first, with the decks it passes waiting; or,
    /// while a deck listed first for its priority cards stays ahead of it,
    /// after that one and ahead of those it passes. How many decks wait, or
    /// are ahead, picks the words, "waits" or "wait", "now" or "first", as
    /// the String Catalog's plural variations say, and doesn't show.
    private var whereItGoes: String {
        guard howFast.putsFirst else {
            let ahead = Self.names(howFast.decksAhead)
            let count = howFast.decksAhead.count
            return String(
                localized: "Goes after \(ahead), which you're meeting \(count).",
                comment: """
                    In How fast?, with the names of the decks ahead of the one coming in, in the queue, and how many \
                    they are, which says “now” for one and “first” for several, and doesn't show.
                    """)
        }
        let passed = Self.names(howFast.decksPassed)
        let count = howFast.decksPassed.count
        guard !howFast.decksStillAhead.isEmpty else {
            return String(
                localized: "Goes first: \(passed) \(count) until you've met it all.",
                comment: """
                    In How fast?, with Put it first ticked, with the names of the decks it goes ahead of, and how \
                    many they are, which says “waits” or “wait” and doesn't show.
                    """)
        }
        let stillAhead = Self.names(howFast.decksStillAhead)
        return String(
            localized: "Goes after \(stillAhead), ahead of \(passed), which \(count) until you've met it all.",
            comment: """
                In How fast?, with Put it first ticked, with the names of the priority decks still ahead of it, \
                then of the decks it goes ahead of, and how many those are, which says “waits” or “wait” and \
                doesn't show.
                """)
    }

    /// `decks`, by their whole names, as a list: "Arte, Historia and
    /// Lenguaje".
    private static func names(_ decks: [String]) -> String {
        decks.map(Deck.shownName).formatted(.list(type: .and))
    }
}

/// A pace's radio, in How fast?'s tiles and in Settings' Pace tab, as the
/// mock draws it: a ring, thick in the accent when the pace is chosen.
struct PaceRadio: View {
    let isChosen: Bool

    var body: some View {
        if isChosen {
            Circle()
                .strokeBorder(.tint, lineWidth: 4.5)
                .frame(width: 14, height: 14)
        } else {
            Circle()
                .strokeBorder(.tertiary, lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
    }
}

extension Pace {
    /// The pace's name, as How fast? and Settings' Pace tab say it.
    var name: String {
        switch self {
        case .chill:
            String(
                localized: "Chill",
                comment: "A pace in How fast? and in Settings' Pace tab, the slowest: 1 new card a day.")
        case .steady:
            String(
                localized: "Steady",
                comment: "A pace in How fast? and in Settings' Pace tab, the one Ficha starts at: 2 new cards a day.")
        case .faster:
            String(
                localized: "Faster",
                comment: "A pace in How fast? and in Settings' Pace tab, the fastest: 4 new cards a day.")
        }
    }

    /// How many new cards a day it brings, as How fast? and Settings' Pace
    /// tab say it: "2 new a day".
    var newCardsADay: String {
        String(
            localized: "\(newCardsPerDay) new a day",
            comment: """
                In How fast?, beside a pace's name, and in Settings' Pace tab, below it: how many new cards a day \
                it brings.
                """)
    }
}

extension CardsWindowState.HowFast.Line {
    /// What How fast? says under the deck's name, and the Cards window under
    /// the name of one of Ficha's decks.
    var text: String {
        switch self {
        case .noCards:
            Deck.noCardsYet
        case .imported(let cardCount, let fileName):
            String(
                localized: "\(cardCount) cards · imported from \(fileName)",
                comment: """
                    In How fast?, under the name of the deck an import made, or the names of the decks: how many \
                    cards they hold, and the name of the file they came from.
                    """)
        case .fichaDeck(let cardCount):
            String(
                localized: "\(cardCount) cards · one of Ficha's decks",
                comment: """
                    In How fast?, and in the Cards window while its sidebar chose one of Ficha's decks, under the \
                    deck's name: how many cards it brings.
                    """)
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
            comment:
                "A finish date of two days in a row, in the Cards window and Settings' Pace tab: “today or tomorrow”.")
    }

    /// Two ends of a finish date, joined by "to": "Wednesday to Saturday",
    /// "early to mid-December", "late November to early December".
    private static func range(_ first: String, _ last: String) -> String {
        String(
            localized: "\(first) to \(last)",
            comment:
                "A finish date from one day or third of a month to another, in the Cards window and Settings' Pace tab."
        )
    }
}

extension FinishDate.Wording.Day {
    /// The day as a finish date says it: "today", "tomorrow", or its
    /// weekday's name, as the system's date format writes it.
    var text: String {
        switch self {
        case .today:
            String(
                localized: "today",
                comment: "A finish date's day, in the Cards window and Settings' Pace tab: “on track for today”.")
        case .tomorrow:
            String(
                localized: "tomorrow",
                comment: "A finish date's day, in the Cards window and Settings' Pace tab: “all met by tomorrow”.")
        case .weekday(let day):
            day.formatted(.dateTime.weekday(.wide))
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
    /// name, as the system's date format writes it: "early December",
    /// "mid-December", "late December".
    var text: String {
        let monthName = day.formatted(.dateTime.month(.wide))
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
