import FichaCore
import Foundation

// Ficha's decks (ADR 0040, #458): three small decks that come inside the app,
// in Spanish for now, each a Ficha package in its resources, a zip of cards
// as Ficha exports one, which comes in through the same import as any
// (ADR 0041), and never from the network (ADR 0017). The app gives FichaData
// each file's URL, from its bundle; the render tool and the tests find them
// in the repo's `App/FichaDecks/`. Opening the app never imports, updates or
// touches one: only Add Deck… does, so an update of the app leaves a deck the
// user added, and its progress, as they were.

/// One of Ficha's decks, in the order the Cards window offers them.
public enum FichaDeck: String, Sendable, CaseIterable {
    case palabrasLindas = "palabras-lindas"
    case arteArgentino = "arte-argentino"
    case floresDeBuenosAires = "flores-de-buenos-aires"

    /// The deck's whole name, which each of its cards names in its file's
    /// Deck column, and which it comes into.
    public var name: String {
        switch self {
        case .palabrasLindas: "Palabras lindas"
        case .arteArgentino: "Arte argentino"
        case .floresDeBuenosAires: "Flores de Buenos Aires"
        }
    }

    /// Its file's name in the app's resources, `App/FichaDecks/` in the repo,
    /// without `.zip`.
    public var fileName: String {
        rawValue
    }

    /// The emoji the deck gets when it comes in new, as `ficha deck emoji`
    /// gives one: provisional.
    public var emoji: String {
        switch self {
        case .palabrasLindas: "💬"
        case .arteArgentino: "🖼️"
        case .floresDeBuenosAires: "💐"
        }
    }
}

/// One of Ficha's decks as its file holds it, read without importing it: what
/// the Cards window shows of it, and what Add Deck… imports.
public struct FichaDeckFile: Sendable, Equatable {
    /// The deck.
    public let deck: FichaDeck

    /// How many cards the file holds: "40 cards". Not read yet (#458): none.
    public var cardCount: Int {
        0
    }

    /// The card the Cards window shows of the deck, front and back: the
    /// file's first, with its front's image, which the window shows along
    /// with it. Not read yet (#458): none.
    public var firstCard: CardContent? {
        nil
    }
}

extension Engine {
    /// Reads the file of `deck` at `file`, the app's own, without importing
    /// it, through the import's own reader of a zip of cards and its preview,
    /// as `previewImport(of:)` reads one, so adding the deck is the same
    /// import as any Ficha package's. It takes a while, so the app calls it
    /// away from the main actor. A missing file is an error whose message
    /// says to reinstall the app, never a crash. Not read yet (#458): the
    /// deck alone.
    public func readFichaDeck(_ deck: FichaDeck, at file: URL) async throws(EngineError) -> FichaDeckFile {
        FichaDeckFile(deck: deck)
    }

    /// Whether the user has added the deck `file` holds: once any of its
    /// cards is among theirs, as the import finds a card that repeats one,
    /// whatever deck it's in now, so that renaming the deck, or getting its
    /// cards from another device, still counts, and deleting all its cards
    /// offers it again. Not worked out yet (#458): never.
    public func hasAdded(_ file: FichaDeckFile) throws(EngineError) -> Bool {
        false
    }

    /// Adds the deck `file` holds, after Add Deck… and How fast?'s Start:
    /// imports its cards as the Import sheet imports a zip of cards, skipping
    /// those that repeat the user's, which stay as they are, with their
    /// progress, so that adding it twice adds nothing, and without the tag
    /// an import gives a file's cards after the file's name; and gives the
    /// deck its emoji when it came in new. Returns what the import did. Not
    /// worked out yet (#458): it adds nothing.
    @discardableResult
    public func add(_ file: FichaDeckFile) throws(EngineError) -> ImportOutcome {
        ImportOutcome(added: 0, updated: 0, skipped: 0, copyBeforeImport: nil)
    }
}
