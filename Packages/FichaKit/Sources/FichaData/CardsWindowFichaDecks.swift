import FichaCore
import Foundation

// The Cards window's Ficha's Decks (#458): a sidebar section after Your Decks
// lists the decks of Ficha's the user hasn't added (`FichaDecks.swift`), each
// with its emoji, name and how many cards it holds, until all are added.
// Choosing one shows it in the grid's and the detail's place: its emoji,
// name and "40 cards · one of Ficha's decks", its first card, front and
// back, and Add Deck…, which asks How fast? for it before it comes in
// (`HowFast.swift`). Start adds it, sets the pace and its place, and the
// sidebar then chooses the deck in Your Decks. The review panel's "You've met
// them all" asks for one too, which opens the window on it with How fast?.

extension CardsWindowState {
    /// Takes Ficha's decks as the app read them from its bundle
    /// (`Engine.readFichaDeck(_:at:)`), each deck's file or why it couldn't
    /// be read, which the sidebar's Ficha's Decks section, after Your Decks,
    /// lists while the user hasn't added them, in `FichaDeck`'s order, and
    /// leaves out once all are, as each read of the cards finds them; and
    /// asks How fast? for the one the review panel asked for meanwhile
    /// (`askToAddFichaDeck(_:)`), while it's offered, as the app's read of
    /// the cards does. A deck whose file couldn't be read, such as one
    /// missing from a damaged copy of the app, isn't listed: the window says
    /// why the first couldn't until Lucas closes it, and the log says each.
    public mutating func offerFichaDecks(_ read: [FichaDeck: Result<FichaDeckFile, EngineError>]) {
        let (files, failures) = FichaDeck.files(in: read)
        fichaDeckFiles = files
        readAgain()
        askForTheFichaDeckAskedToAdd()
        if let failed = failures.first {
            record(failed.error, for: .readFichaDeck(failed.deck))
        }
    }

    /// The one of Ficha's decks the sidebar chose, as its file holds it,
    /// which the window shows in the grid's and the detail's place, with its
    /// first card's images among the images it shows (`images`): nil while
    /// the sidebar chose something else.
    public var shownFichaDeck: FichaDeckFile? {
        guard case .fichaDeck(let deck) = sidebarItem else { return nil }
        return fichaDecksNotAdded.first { $0.deck == deck }
    }

    /// Asks How fast? for the one of Ficha's decks the sidebar chose, after
    /// its Add Deck…: before it comes in, with its cards counted as they'd
    /// come in now, those that repeat none of the user's, which Add Deck…
    /// skips, into the user's deck by its name, at its place in the queue,
    /// or else last, as a deck that comes in goes. Its Start adds the deck,
    /// sets the pace and its place, and the sidebar then chooses the deck in
    /// Your Decks. When the queue can't be read, it asks nothing, and says
    /// why.
    public mutating func askToAddFichaDeck() {
        guard let file = shownFichaDeck else { return }
        do throws(EngineError) {
            let cards = try engine.cardsForHowFast(adding: file.file)
            let settings = try engine.cardsWindowQueueSettings(activeHours: activeHours)
            question = .howFast(
                HowFast(
                    about: [file.deck.name], fromFile: .fichaDeck(file.deck), emoji: file.emoji,
                    line: .fichaDeck(cardCount: cards.cardCount), amongTopDecks: listedTopDecks,
                    cards: cards.inReviews, settings: settings, now: engine.now, calendar: engine.calendar))
        } catch {
            record(error, for: .addFichaDeck(file.deck))
        }
    }

    /// Chooses `deck`, one of Ficha's decks, in the sidebar, and asks How
    /// fast? for it, as its Add Deck… does: what the review panel's "You've
    /// met them all" asks for, which has closed, so the window never drops
    /// it. Before the app gave the window Ficha's decks
    /// (`offerFichaDecks(_:)`), or while the window asks something else,
    /// Lucas edits, or a sheet of its own is open, it waits, and asks once
    /// they come and what's open closes, as
    /// `askForTheFichaDeckAskedToAdd()` says; and it asks nothing for one
    /// the user has added.
    public mutating func askToAddFichaDeck(_ deck: FichaDeck) {
        fichaDeckAskedToAdd = deck
        askForTheFichaDeckAskedToAdd()
    }

    /// Asks How fast? for the deck of the `.ficha` Open Deck… or Finder
    /// opened meanwhile, as soon as the window can
    /// (`askForTheDeckFileOpened()`), and else for the one of Ficha's decks
    /// the review panel asked for (`askToAddFichaDeck(_:)`): once the app
    /// gave it the deck's file, and while it asks nothing else, Lucas edits
    /// nothing, and no sheet of its own is open. The app's read of the
    /// cards calls it (`read(with:)`), and so does the end of each way out
    /// of a question, an edit, the card form or a sheet, once it's over,
    /// never a read partway through one (`readAgain()`), so the sidebar stays
    /// where that leaves it. Show Card's is the exception: it leaves the
    /// window on the card it shows (`showRepeatedCard()`), so the app's next
    /// read asks. It forgets the deck once it asks, or once the user has
    /// added it meanwhile.
    mutating func askForTheFichaDeckAskedToAdd() {
        askForTheDeckFileOpened()
        guard let deck = fichaDeckAskedToAdd, fichaDeckFiles.contains(where: { $0.deck == deck }),
            question == nil, editing == nil, cardForm == nil
        else { return }
        fichaDeckAskedToAdd = nil
        guard fichaDecksNotAdded.contains(where: { $0.deck == deck }) else { return }
        choose(.fichaDeck(deck))
        askToAddFichaDeck()
    }

    /// Adds `deck`, one of Ficha's decks, as How fast?'s Start does before it
    /// saves the pace (`Engine.addFichaDeck(_:)`), and has the sidebar choose
    /// it in Your Decks once the window reads the cards again; or records why
    /// it couldn't: whether it did.
    mutating func addFichaDeck(_ deck: FichaDeck) -> Bool {
        guard let file = fichaDeckFiles.first(where: { $0.deck == deck }) else {
            record(.fichaDeckMissing(deck.name), for: .addFichaDeck(deck))
            return false
        }
        guard perform(.addFichaDeck(deck), { engine throws(EngineError) in _ = try engine.addFichaDeck(file) }) else {
            return false
        }
        sidebarItem = .cards(.deck(deck.name))
        return true
    }
}

extension Engine {
    /// What How fast? reads of the cards for `file`, a deck's `.ficha`, one
    /// of Ficha's decks or another, before it comes in, in one read: those in
    /// the user's reviews, as the planners take them, with the file's cards
    /// as they'd come in now, as `addDeck(_:)` imports them, but for those
    /// that repeat one of the user's, which it skips; and how many come in.
    func cardsForHowFast(adding file: DeckFile) throws(EngineError)
        -> (inReviews: CardsInReviews, cardCount: Int)
    {
        let now = time.now
        return try read { db in
            let coming = try cardsComingIn(file.preview, at: now, in: db)
            return (inReviews: try cardsThatShowUp(in: db, adding: coming).inReviews, cardCount: coming.count)
        }
    }
}
