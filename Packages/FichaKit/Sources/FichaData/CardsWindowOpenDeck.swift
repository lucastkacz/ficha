import FichaCore
import Foundation

// Open Deck…, in the Cards window's sidebar beside New Deck…, and a file
// opened from Finder, which the app opens the same way (ADR 0044, #554): the
// window opens a deck's `.ficha` alone (`DeckFile.swift`), reading it away
// from the main actor, and asks How fast? for the deck before it comes in, as
// Add Deck… does for one of Ficha's decks (`CardsWindowFichaDecks.swift`).
// Start adds it, sets the pace and its place, and the sidebar then chooses
// the deck; Cancel brings nothing in. A file opened while the window asks
// something else, Lucas edits, or a sheet of its own is open, waits until
// what's open closes.

extension CardsWindowState {
    /// Whether the window asks which deck's `.ficha` to open, in an open
    /// panel, after Open Deck….
    public var isChoosingDeckFile: Bool {
        question == .deckFileToOpen
    }

    /// Asks which deck's `.ficha` to open, after Open Deck…, in the
    /// sidebar's menus, on ⌘O, or beside New Card while the user has no
    /// cards: the app's open panel answers it, with `openDeck(_:)` once the
    /// user chose a file, or `cancelQuestion()`.
    public mutating func askToOpenDeck() {
        question = .deckFileToOpen
    }

    /// Opens `file`, which the user chose with Open Deck… or opened from
    /// Finder: starts reading it while it's a deck's `.ficha`, and returns
    /// the work, which the app runs away from the main actor and hands to
    /// `finishOpenDeck(_:)`, after which How fast? asks for the deck; or
    /// refuses it at once, while it's anything else, recording an error that
    /// says Ficha opens a deck's `.ficha` file, and returns nil. Either way,
    /// the open panel is done. A file opened while another is read replaces
    /// it.
    public mutating func openDeck(_ file: URL) -> OpenDeckWork? {
        if question == .deckFileToOpen {
            question = nil
        }
        let name = file.lastPathComponent
        guard file.pathExtension.lowercased() == DeckFile.fileExtension else {
            record(.unreadableFile(name, .notADeckFile), for: .openDeck(fileName: name))
            askForTheFichaDeckAskedToAdd()
            return nil
        }
        let work = OpenDeckWork(id: UUID(), engine: engine, file: file)
        deckFileAwaited = work.id
        return work
    }

    /// Takes what the work `openDeck(_:)` started read, once the app ran it:
    /// asks How fast? for the deck of the file, as soon as the window can
    /// (`askForTheDeckFileOpened()`), or records why it couldn't read it.
    /// What a work the window no longer waits for read, it leaves alone.
    public mutating func finishOpenDeck(_ done: OpenDeckWork.Done) {
        guard deckFileAwaited == done.id else { return }
        deckFileAwaited = nil
        switch done.result {
        case .success(let file):
            deckFileOpened = file
            askForTheFichaDeckAskedToAdd()
        case .failure(let error):
            record(error, for: .openDeck(fileName: done.fileName))
        }
    }

    /// Asks How fast? for the deck of the `.ficha` the window read
    /// (`finishOpenDeck(_:)`), as soon as it can: while it asks nothing
    /// else, Lucas edits nothing, and no sheet of its own is open, as for
    /// one of Ficha's decks the review panel asks for
    /// (`askForTheFichaDeckAskedToAdd()`, which calls it first). Its cards
    /// are counted as they'd come in now, those that repeat none of the
    /// user's, into the deck at the top of the tree they come into, at its
    /// place in the queue, or else last. When the queue can't be read, it
    /// asks nothing, and says why. It forgets the file once it asks.
    mutating func askForTheDeckFileOpened() {
        guard let file = deckFileOpened, question == nil, editing == nil, cardForm == nil else { return }
        deckFileOpened = nil
        do throws(EngineError) {
            let cards = try engine.cardsForHowFast(adding: file)
            let settings = try engine.cardsWindowQueueSettings(activeHours: activeHours)
            // A deck the user has keeps its own emoji, and one that comes in
            // new takes the file's.
            let emoji = listedDeck(file.deck).map(\.shownEmoji) ?? file.emoji
            question = .howFast(
                HowFast(
                    about: [TagPath.top(of: file.deck)], fromFile: .deckFile(file), emoji: emoji,
                    line: .deckFile(cardCount: cards.cardCount, fileName: file.fileName),
                    amongTopDecks: listedTopDecks, cards: cards.inReviews, settings: settings, now: engine.now,
                    calendar: engine.calendar))
        } catch {
            record(error, for: .openDeck(fileName: file.fileName))
        }
    }

    /// Adds the deck of `file`, a `.ficha`, as How fast?'s Start does before
    /// it saves the pace (`Engine.addDeck(_:)`), and has the sidebar choose
    /// it in Your Decks once the window reads the cards again; or records
    /// why it couldn't: whether it did.
    mutating func addDeckFile(_ file: DeckFile) -> Bool {
        let added = perform(.openDeck(fileName: file.fileName)) { engine throws(EngineError) in
            _ = try engine.addDeck(file)
        }
        guard added else { return false }
        sidebarItem = .cards(.deck(file.deck))
        return true
    }
}

/// Work Open Deck… starts, reading a deck's `.ficha` for How fast?, which the
/// app runs away from the main actor and hands back to the window's
/// `finishOpenDeck(_:)`: a big file takes a while.
public struct OpenDeckWork: Sendable {
    /// What the work read.
    public struct Done: Sendable {
        fileprivate let id: UUID
        /// The name of the file it read, as Finder shows it.
        fileprivate let fileName: String
        fileprivate let result: Result<DeckFile, EngineError>
    }

    fileprivate let id: UUID
    fileprivate let engine: Engine
    fileprivate let file: URL

    /// Reads the file, away from the caller's actor, and says what it read.
    public func run() async -> Done {
        let name = file.lastPathComponent
        do {
            return Done(id: id, fileName: name, result: .success(try await engine.readDeckFile(at: file)))
        } catch {
            return Done(id: id, fileName: name, result: .failure(error))
        }
    }
}
