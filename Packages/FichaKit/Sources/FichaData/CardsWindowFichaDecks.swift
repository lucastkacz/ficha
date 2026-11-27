import FichaCore
import Foundation

// The Cards window's Ficha's Decks (#458): a sidebar section after Decks
// lists the decks of Ficha's the user hasn't added (`FichaDecks.swift`), each
// with its emoji, name and how many cards it holds, until all are added.
// Choosing one shows it in the table's and the detail's place: its emoji,
// name and "40 cards · one of Ficha's decks", its first card, front and
// back, and Add Deck…, which asks How fast? for it before it comes in
// (`HowFast.swift`). Start adds it, sets the pace and its place, and the
// sidebar then chooses the deck in Decks. The review panel's "You've met them
// all" asks for one too, which opens the window on it with How fast?.

extension CardsWindowState {
    /// Takes Ficha's decks as the app read them from its bundle
    /// (`Engine.readFichaDeck(_:at:)`), which the sidebar's Ficha's Decks
    /// section, after Decks, lists while the user hasn't added them, in
    /// `FichaDeck`'s order, and leaves out once all are, as each read of the
    /// cards finds them; and asks How fast? for the one the review panel
    /// asked for meanwhile (`askToAddFichaDeck(_:)`), while it's offered.
    public mutating func offerFichaDecks(_ files: [FichaDeckFile]) {
        fichaDeckFiles = FichaDeck.allCases.compactMap { deck in files.first { $0.deck == deck } }
        read(with: scheduler)
        if let asked = fichaDeckAskedToAdd {
            fichaDeckAskedToAdd = nil
            askToAddFichaDeck(asked)
        }
    }

    /// Records that the app couldn't read the file of `deck`, as `error`
    /// says, such as one missing from a damaged copy of the app, which the
    /// window says until Lucas closes it: the section doesn't list the deck.
    public mutating func couldNotRead(_ deck: FichaDeck, because error: EngineError) {
        record(error, for: .readFichaDeck(deck))
    }

    /// The one of Ficha's decks the sidebar chose, as its file holds it,
    /// which the window shows in the table's and the detail's place, with its
    /// first card's images among the images it shows (`images`): nil while
    /// the sidebar chose something else.
    public var shownFichaDeck: FichaDeckFile? {
        guard case .fichaDeck(let deck) = sidebarItem else { return nil }
        return fichaDecksNotAdded.first { $0.deck == deck }
    }

    /// Asks How fast? for the one of Ficha's decks the sidebar chose, after
    /// its Add Deck…: before it comes in, with its cards counted as if they
    /// came in now, last. Its Start adds the deck, sets the pace and its
    /// place, and the sidebar then chooses the deck in Decks. When the queue
    /// can't be read, it asks nothing, and says why.
    public mutating func askToAddFichaDeck() {
        guard let file = shownFichaDeck else { return }
        do throws(EngineError) {
            let cards = try engine.cardsInReviewsForFichaDeck()
            let settings = try engine.cardsWindowQueueSettings()
            question = .howFast(
                HowFast(
                    adding: file, amongTopDecks: listedTopDecks, cards: cards, settings: settings, now: engine.now,
                    calendar: engine.calendar))
        } catch {
            record(error, for: .addFichaDeck(file.deck))
        }
    }

    /// Chooses `deck`, one of Ficha's decks, in the sidebar, and asks How
    /// fast? for it, as its Add Deck… does: what the review panel's "You've
    /// met them all" asks for. Before the app gave the window Ficha's decks
    /// (`offerFichaDecks(_:)`), it asks once they come; and it asks nothing
    /// for one the user has added, or while the window asks something else,
    /// Lucas edits, or a sheet of its own is open.
    public mutating func askToAddFichaDeck(_ deck: FichaDeck) {
        guard fichaDeckFiles.contains(where: { $0.deck == deck }) else {
            fichaDeckAskedToAdd = deck
            return
        }
        guard question == nil, editing == nil, cardForm == nil, importing == nil, exporting == nil,
            fichaDecksNotAdded.contains(where: { $0.deck == deck })
        else { return }
        choose(.fichaDeck(deck))
        askToAddFichaDeck()
    }

    /// Adds `deck`, one of Ficha's decks, as How fast?'s Start does before it
    /// saves the pace (`Engine.addFichaDeck(_:)`), and has the sidebar choose
    /// it in Decks once the window reads the cards again; or records why it
    /// couldn't: whether it did.
    mutating func addFichaDeck(_ deck: FichaDeck) -> Bool {
        guard let file = fichaDeckFiles.first(where: { $0.deck == deck }) else {
            record(.fichaDeckMissing(deck.name), for: .addFichaDeck(deck))
            return false
        }
        guard perform(.addFichaDeck(deck), { engine throws(EngineError) in _ = try engine.addFichaDeck(file) }) else {
            return false
        }
        sidebarItem = .cards(.deck(deck.name))
        tagShownFromAllTags = nil
        chosenDeckTag = nil
        return true
    }
}

extension CardsWindowState.HowFast {
    /// How fast? as it opens for `file`, one of Ficha's decks, before it
    /// comes in, among `topDecks`, the decks at the top of the tree the
    /// sidebar lists, out of `cards`, the cards in the user's reviews, at
    /// `now`, by `calendar`, the engine's, with `settings`' pace and Ficha's
    /// other settings: at the user's pace, or Steady while it's none, with
    /// Put it first unticked, and each pace's finish date with the deck's
    /// new ways counted as if they came in now, last in the queue, after
    /// every deck with new cards, or first.
    fileprivate init(
        adding file: FichaDeckFile, amongTopDecks topDecks: [Deck], cards: CardsInReviews, settings: ReviewSettings,
        now: Date, calendar: Calendar
    ) {
        let queue = settings.queue(of: cards, now: now, calendar: calendar).map(\.deck)
        let paces = { (first: Bool) -> [PaceOption] in
            Pace.allCases.map { pace in
                var paced = settings
                paced.newCardsPerDay = pace.newCardsPerDay
                let finish = paced.finishDate(
                    ofComing: file.newWayCount, first: first, in: cards, now: now, calendar: calendar)
                return PaceOption(pace: pace, finish: finish, wording: finish?.wording(now: now, calendar: calendar))
            }
        }
        self.init(
            subject: .fichaDeck(file.deck), decks: [], line: .fichaDeck(cardCount: file.cardCount),
            pace: Pace(newCardsPerDay: settings.newCardsPerDay) ?? .steady, decksAhead: queue, putsFirst: false,
            hasOtherDecks: !topDecks.isEmpty, pacesWhereItIs: paces(false), pacesFirst: paces(true))
    }
}

extension Engine {
    /// The cards in the user's reviews, as the planners take them, which How
    /// fast? counts one of Ficha's decks' new ways after.
    fileprivate func cardsInReviewsForFichaDeck() throws(EngineError) -> CardsInReviews {
        try read { db in try cardsThatShowUp(in: db).inReviews }
    }
}
