import FichaCore
import Foundation

// How fast? (ADR 0034, #491): a sheet over the Cards window, as a deck comes
// in, that asks how fast new cards come, for every deck together, and where
// the deck goes in the queue new cards come from. It opens after the New Deck
// sheet's OK makes a deck from the sidebar or a deck's menu, with the paces
// alone, when the sidebar didn't list the deck at the top of the tree it
// made, the deck or one it sits inside: so "Arte::Barroco" asks about Arte
// while Arte wasn't listed, and nothing while it was
// (`CardsWindowDecks.swift`); after an import that made decks, those its new
// cards came into that the user didn't have, once its sheet's Done closes
// it; after Add Deck… on one of Ficha's decks, before it comes in
// (`CardsWindowFichaDecks.swift`); and after Open Deck… or Finder opened a
// deck's `.ficha`, before it comes in (`CardsWindowOpenDeck.swift`). Each
// pace's finish date, where the deck is and with the deck first, is
// FichaCore's, as the queue counts it (`DeckQueue.swift`), with the settings
// the window reads the queue with. Start adds one of Ficha's decks, or the
// deck of a `.ficha`, saves the pace as `ficha pace` does, and puts the deck
// first as `ficha deck queue --first` does, when Put it first is ticked;
// Cancel changes nothing, so a deck that came in stays last, where it came,
// and one of Ficha's decks, or a `.ficha`'s, isn't added.

extension CardsWindowState {
    /// How fast?, while the window asks it: the deck it asks about, the three
    /// paces, each with its new cards a day and, when the deck has new cards,
    /// when they're all met, and where the deck goes in the queue.
    public struct HowFast: Sendable, Equatable {
        /// What How fast? asks about.
        public enum Subject: Sendable, Equatable {
            /// The deck at the top of the tree, by its whole name, or Default
            /// by `Deck.defaultName`, that New Deck…'s OK just made, or that
            /// an import made, the one its new cards came into that the user
            /// didn't have.
            case deck(String)
            /// The decks at the top of the tree an import made, when they're
            /// several, in the queue's order: the paces then say when the
            /// last of them is all met.
            case decks([String])
            /// One of Ficha's decks, after its Add Deck…, before it comes in
            /// (#458): its cards counted as they'd come in now, those that
            /// repeat none of the user's, into the deck of theirs by its
            /// name at its place in the queue, or else last, and Start adds
            /// it.
            case fichaDeck(FichaDeck)
            /// The deck a `.ficha` holds, after Open Deck… or Finder opened
            /// it, before it comes in (#554): its cards counted as for one
            /// of Ficha's decks, into the deck at the top of the tree it
            /// comes into, and Start adds it.
            case deckFile(DeckFile)
        }

        /// What the line under the deck's name says.
        public enum Line: Sendable, Equatable {
            /// "No cards yet": the deck New Deck…'s OK just made.
            case noCards
            /// "14 cards · imported from Arte.apkg": the deck an import made,
            /// with its cards and those of the decks inside it, whatever
            /// their standing, or those of all the decks it made, and the
            /// name of the file it came from.
            case imported(cardCount: Int, fileName: String)
            /// "40 cards · one of Ficha's decks": one of Ficha's decks, with a
            /// count of its cards: in How fast?, those that would come in,
            /// those of its file that repeat none of the user's (#458); and
            /// under the deck's name in the Cards window, before its Add
            /// Deck…, every card its file holds (`FichaDeckFile.cardCount`).
            case fichaDeck(cardCount: Int)
            /// "12 cards · from Capitales.ficha": the deck of a `.ficha`,
            /// with a count of the cards that would come in, as for one of
            /// Ficha's decks, and the file's name.
            case deckFile(cardCount: Int, fileName: String)
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
        /// The decks it asks about, as the sidebar lists them, with their
        /// emoji, in the queue's order, which the sheet names at its top:
        /// none for one of Ficha's decks, or a `.ficha`'s, which the sheet
        /// names as it is.
        public let decks: [Deck]
        /// The emoji the sheet shows before the name of one of Ficha's
        /// decks, or a `.ficha`'s, which `decks` doesn't list: the one its
        /// file holds, which the deck takes as it comes in new, or the
        /// user's own deck's, which keeps its own; nil for none, and for the
        /// decks the user has, whose emoji `decks` holds.
        public let emoji: String?
        /// What the line under the deck's name says.
        public let line: Line
        /// The pace Start saves, ticked in the radio group: the user's as
        /// the sheet opens, or Steady while their new cards a day are no
        /// pace, until they choose another.
        public internal(set) var pace: Pace
        /// The decks at the top of the tree with new cards ahead of the deck
        /// in the queue, in its order, the first the one the user is meeting
        /// now: "Goes after Arte, which you're meeting now."
        public let decksAhead: [String]
        /// Those of `decksAhead` the deck goes ahead of with Put it first, in
        /// the queue's order, as FichaCore's queue puts it
        /// (`CardsInReviews.decksInQueue(putting:at:now:)`), which wait until
        /// it's all met: "Goes first: Arte waits until you've met it all."
        /// Put it first is offered while there are some.
        public let decksPassed: [String]
        /// The decks at the top of the tree still ahead of the deck once Put
        /// it first puts it first, in the queue's order: those listed first
        /// for their priority cards, whose new cards still come first. "Goes
        /// after Música, ahead of Arte, which waits until you've met it all."
        public let decksStillAhead: [String]
        /// Whether Put it first is ticked: unticked as the sheet opens.
        public internal(set) var putsFirst: Bool
        /// Whether the user has other decks, so the sheet says one pace is
        /// for all of them, and that a deck waits its turn for new cards.
        public let hasOtherDecks: Bool
        /// Chill, Steady and Faster, each with when the deck's new cards are
        /// all met at it where the deck is in the queue, as the sheet opens.
        let pacesWhereItIs: [PaceOption]
        /// The same, once the deck is first in the queue, as Put it first
        /// would put it.
        let pacesFirst: [PaceOption]

        /// Whether the sheet says where the deck goes in the queue: while
        /// some deck with new cards is ahead of it, as `decksAhead` says,
        /// with Put it first beside it while it's offered.
        public var saysWhereItGoes: Bool {
            !decksAhead.isEmpty
        }

        /// Whether the sheet offers Put it first, beside where the deck
        /// goes: while it passes some deck, one with new cards ahead of the
        /// deck in the queue that isn't listed first for its priority cards.
        /// With only decks listed first for their priority cards ahead, the
        /// sheet says the deck goes after them, and offers nothing.
        public var offersPutItFirst: Bool {
            !decksPassed.isEmpty
        }

        /// Chill, Steady and Faster, in that order, each with when the deck's
        /// new cards are all met at it, where the deck goes as Put it first
        /// says.
        public var paces: [PaceOption] {
            putsFirst ? pacesFirst : pacesWhereItIs
        }
    }

    /// How a deck How fast? asks about came in.
    enum ComingIn {
        /// New Deck…'s OK made it, with no card.
        case newDeck
        /// An import from the file named `fileName` made it.
        case anImport(fileName: String)
    }

    /// How fast?, while the window asks it.
    public var howFast: HowFast? {
        guard case .howFast(let howFast) = question else { return nil }
        return howFast
    }

    /// Chooses `pace` in How fast?'s radio group, which Start saves.
    public mutating func chooseHowFastPace(_ pace: Pace) {
        guard case .howFast(var howFast) = question else { return }
        howFast.pace = pace
        question = .howFast(howFast)
    }

    /// Ticks How fast?'s Put it first, or unticks it when `isFirst` is
    /// false, while it's offered: the paces then say when the deck's new
    /// cards are all met with the deck first in the queue.
    public mutating func putHowFastFirst(_ isFirst: Bool) {
        guard case .howFast(var howFast) = question, howFast.offersPutItFirst else { return }
        howFast.putsFirst = isFirst
        question = .howFast(howFast)
    }

    /// Chooses Start in How fast?: for one of Ficha's decks, or a `.ficha`'s,
    /// adds it first (`Engine.addFichaDeck(_:)`, `Engine.addDeck(_:)`), and
    /// the sidebar then chooses the deck;
    /// saves the pace chosen, when it changed, through
    /// `Engine.saveProgressSettings(_:changedFrom:)`, as `ficha pace` does,
    /// puts the deck first through `Engine.moveInQueue(deck:to:)`, as `ficha
    /// deck queue --first` does, when Put it first is ticked, and reads the
    /// cards again; or records why it couldn't and goes on asking. One of
    /// Ficha's decks, or a `.ficha`'s, that came in stays in, so Start again
    /// adds nothing more.
    public mutating func startHowFast() {
        guard case .howFast(let howFast) = question else { return }
        // The deck Put it first puts first, for one deck alone.
        let firstable: String?
        switch howFast.subject {
        case .deck(let deck):
            firstable = deck
        case .decks:
            firstable = nil
        case .fichaDeck(let deck):
            guard addFichaDeck(deck) else { return }
            firstable = deck.name
        case .deckFile(let file):
            guard addDeckFile(file) else { return }
            firstable = TagPath.top(of: file.deck)
        }
        let done = perform(.startHowFast) { engine throws(EngineError) in
            let old = try engine.progressSettings()
            var paced = old
            paced.newCardsPerDay = howFast.pace.newCardsPerDay
            try engine.saveProgressSettings(paced, changedFrom: old)
            if howFast.putsFirst, let firstable {
                try engine.moveInQueue(deck: firstable, to: .first)
            }
        }
        if done {
            question = nil
            readAgain()
            askForTheFichaDeckAskedToAdd()
        } else if howFast.subject.comesFromAFile {
            // It came in all the same, which the window lists.
            readAgain()
        }
    }

    /// Asks How fast? about `names`, decks at the top of the tree that came
    /// in as `comingIn` says, by their whole names, or Default by
    /// `Deck.defaultName`, once the window read them again: nothing for no
    /// deck. When the queue can't be read, it asks nothing, and says why in
    /// the log, so the decks stay where they came in, at the pace there was,
    /// as after Cancel.
    mutating func askHowFast(about names: [String], cameInFrom comingIn: ComingIn) {
        guard !names.isEmpty else { return }
        do throws(EngineError) {
            let cards = try engine.cardsForHowFast(countingIn: names)
            let settings = try engine.cardsWindowQueueSettings(activeHours: activeHours)
            let line: HowFast.Line =
                switch comingIn {
                case .newDeck: .noCards
                case .anImport(let fileName): .imported(cardCount: cards.cardCount, fileName: fileName)
                }
            question = .howFast(
                HowFast(
                    about: names, line: line, amongTopDecks: listedTopDecks, cards: cards.inReviews,
                    settings: settings, now: engine.now, calendar: engine.calendar))
        } catch {
            logger.error("Couldn't read the queue for How fast?: \(String(describing: error), privacy: .public)")
        }
    }
}

extension CardsWindowState.HowFast.Subject {
    /// Whether it's a deck that comes in from a file once Start adds it: one
    /// of Ficha's decks, or a `.ficha`'s.
    var comesFromAFile: Bool {
        switch self {
        case .deck, .decks: false
        case .fichaDeck, .deckFile: true
        }
    }
}

extension CardsWindowState.HowFast {
    /// How fast? as it opens about `names`, decks at the top of the tree
    /// among `topDecks`, those the sidebar lists, or about `file`, one of
    /// Ficha's decks or a `.ficha`'s, by its name alone, before it comes in,
    /// as `names`' one deck, with `emoji` before it, with `line` under their
    /// names, out of `cards`, the cards in the user's reviews, with those of
    /// `file` as they'd come in, at `now`, by `calendar`, the engine's, with
    /// `settings`' pace and Ficha's other settings: at the user's pace, or
    /// Steady while it's none, with Put it first unticked, and each pace's
    /// finish date, of the deck, or of the last of the decks in the queue,
    /// where it is and with the deck first. Put it first is for one deck
    /// alone.
    init(
        about names: [String], fromFile file: Subject? = nil, emoji: String? = nil, line: Line,
        amongTopDecks topDecks: [Deck], cards: CardsInReviews, settings: ReviewSettings, now: Date, calendar: Calendar
    ) {
        let queue = settings.queue(of: cards, now: now, calendar: calendar).map(\.deck)
        let inQueueOrder = queue.filter(names.contains) + names.filter { !queue.contains($0) }
        let last = queue.last(where: names.contains)
        let paces = { (first: Bool) -> [PaceOption] in
            Pace.allCases.map { pace in
                var paced = settings
                paced.newCardsPerDay = pace.newCardsPerDay
                let finish = last.flatMap {
                    paced.finishDate(of: $0, first: first, in: cards, now: now, calendar: calendar)
                }
                return PaceOption(pace: pace, finish: finish, wording: finish?.wording(now: now, calendar: calendar))
            }
        }
        // The decks ahead of the deck where it is, and those still ahead
        // once it's first, as FichaCore's queue puts it, for one deck alone.
        var decksAhead: [String] = []
        var decksStillAhead: [String] = []
        if names.count == 1, let place = queue.firstIndex(of: names[0]) {
            decksAhead = Array(queue[..<place])
            let withItFirst = cards.decksInQueue(putting: names[0], at: .first, now: now)
            decksStillAhead = Array(withItFirst.prefix { $0 != names[0] })
        }
        var subject = names.count == 1 ? Subject.deck(names[0]) : .decks(inQueueOrder)
        var decks = inQueueOrder.compactMap { name in topDecks.first { $0.name == name } }
        if let file {
            subject = file
            decks = []
        }
        self.init(
            subject: subject, decks: decks, emoji: file == nil ? nil : emoji, line: line,
            pace: Pace(newCardsPerDay: settings.newCardsPerDay) ?? .steady, decksAhead: decksAhead,
            decksPassed: decksAhead.filter { !decksStillAhead.contains($0) }, decksStillAhead: decksStillAhead,
            putsFirst: false, hasOtherDecks: topDecks.contains { !names.contains($0.name) },
            pacesWhereItIs: paces(false), pacesFirst: paces(true))
    }
}

extension Engine {
    /// What How fast? reads of the cards, in one read: those in the user's
    /// reviews, as the planners take them, and how many cards the decks
    /// `names`, decks at the top of the tree, hold, with the decks inside
    /// them, whatever their standing.
    fileprivate func cardsForHowFast(countingIn names: [String]) throws(EngineError)
        -> (inReviews: CardsInReviews, cardCount: Int)
    {
        try read { db in
            let cardCount = try allCards(in: db).count { names.contains(TagPath.top(of: $0.deck)) }
            let inReviews = try cardsThatShowUp(in: db).inReviews
            return (inReviews: inReviews, cardCount: cardCount)
        }
    }
}
