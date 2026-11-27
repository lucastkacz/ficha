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

    /// What the deck holds, in a sentence in its cards' language, which the
    /// Cards window shows under its name while the user hasn't added it: a
    /// stub, which #458's test fails.
    public var about: String {
        ""
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

    /// The files of `read`, what the app read of Ficha's decks from its
    /// bundle (`Engine.readFichaDeck(_:at:)`), each deck's file or why it
    /// couldn't be read, in `FichaDeck`'s order, which the Cards window and
    /// the review panel offer them in, and the decks that couldn't be read,
    /// each with why, in that order too, which the log says.
    static func files(in read: [FichaDeck: Result<FichaDeckFile, EngineError>])
        -> (files: [FichaDeckFile], failures: [(deck: FichaDeck, error: EngineError)])
    {
        var files: [FichaDeckFile] = []
        var failures: [(deck: FichaDeck, error: EngineError)] = []
        for deck in allCases {
            switch read[deck] {
            case .success(let file)?:
                files.append(file)
            case .failure(let error)?:
                logger.error(
                    "Couldn't read \(deck.fileName, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                failures.append((deck, error))
            case nil:
                break
            }
        }
        return (files, failures)
    }
}

/// One of Ficha's decks as its file holds it, read without importing it: what
/// the Cards window shows of it, and what Add Deck… imports.
public struct FichaDeckFile: Sendable, Equatable {
    /// The deck.
    public let deck: FichaDeck
    /// What importing the file would do, as the import read it, with the
    /// images its cards refer to, which `Engine.addFichaDeck(_:)` imports.
    let preview: ImportPreview

    /// How many cards the file holds, the deck's own size, which the Cards
    /// window says of it: "40 cards". How fast? counts those that come in,
    /// fewer when some repeat the user's, which Add Deck… skips.
    public var cardCount: Int {
        preview.cardCount
    }

    /// The card the Cards window shows of the deck, front and back: the
    /// file's first, with its front's image, which the window shows along
    /// with it (`firstCardImages`).
    public var firstCard: CardContent? {
        preview.cards.first?.content
    }

    /// The images on the first card's sides, as the file holds them, which
    /// the Cards window shows with it while they aren't the user's.
    var firstCardImages: [CardImage] {
        (firstCard?.images ?? []).sorted { $0.rawValue < $1.rawValue }.compactMap { preview.images[$0] }
    }

    /// What `Engine.addFichaDeck(_:)` chooses as it imports the file: the
    /// cards that repeat the user's skipped, and the tag an import gives a
    /// file's cards after the file's name left out.
    var importChoices: ImportChoices {
        // The proposed tags, each once, are the file's name alone.
        ImportChoices(
            tagNames: Dictionary(uniqueKeysWithValues: preview.proposedTags.map { ($0, "") }), repeatedCards: .skip)
    }
}

extension Engine {
    /// Reads the file of `deck` at `file`, the app's own, without importing
    /// it, as `previewImport(of:)` reads a file of cards: through the
    /// import's own reader of a zip of cards and its preview, so adding the
    /// deck is the same import as any Ficha package's. It takes a while, so
    /// the app calls it away from the main actor. A missing file is an error
    /// whose message says to reinstall the app, never a crash.
    public func readFichaDeck(_ deck: FichaDeck, at file: URL) async throws(EngineError) -> FichaDeckFile {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            logger.error("The file of one of Ficha's decks isn't there: \(deck.fileName, privacy: .public).zip")
            throw .fichaDeckMissing(deck.name)
        }
        return FichaDeckFile(deck: deck, preview: try await previewImport(of: file))
    }

    /// Whether the user has added the deck `file` holds: once any of its
    /// cards is among theirs, whatever deck it's in now, so that renaming the
    /// deck, or getting its cards from another device, still counts, and
    /// deleting all its cards offers it again. A card of the deck is among
    /// theirs when one of theirs repeats it, as the import finds a card that
    /// repeats one (`repeatedCards(of:in:)`), with its back as the file has
    /// it: so a card of the user's own with a word of Palabras lindas on its
    /// front, such as "serendipia", doesn't count, and an update of the app
    /// that changes a card's back still finds the deck by the others.
    public func hasAdded(_ file: FichaDeckFile) throws(EngineError) -> Bool {
        try !fichaDecks(among: [file], added: true).isEmpty
    }

    /// Those of `files` whose deck the user hasn't added, as `hasAdded(_:)`
    /// says, in their order, or those whose deck they have when `added`, in
    /// one read.
    func fichaDecks(among files: [FichaDeckFile], added: Bool = false) throws(EngineError) -> [FichaDeckFile] {
        try read { db in
            try files.filter { file in
                let repeated = try repeatedCards(of: file.preview.cards, in: db)
                let isAdded = zip(file.preview.cards, repeated).contains { card, theirs in
                    theirs?.back == card.content.back
                }
                return isAdded == added
            }
        }
    }

    /// Adds the deck `file` holds, after Add Deck… and How fast?'s Start:
    /// imports its cards as the Import sheet imports a zip of cards
    /// (`importCards(_:choosing:)`), skipping those that repeat the user's,
    /// which stay as they are, with their progress, so that adding it twice
    /// adds nothing, and without the tag an import gives a file's cards after
    /// the file's name; and gives the deck its emoji, as `ficha deck emoji`
    /// gives one, when the import made it: the user had no deck by its name,
    /// and cards came into it. Returns what the import did.
    @discardableResult
    public func addFichaDeck(_ file: FichaDeckFile) throws(EngineError) -> ImportOutcome {
        let imported = try importCardsAndTheirDecks(file.preview, choosing: file.importChoices)
        if imported.newDecks.contains(file.deck.name) {
            try setEmoji(try Emoji(file.deck.emoji), ofDeck: file.deck.name)
        }
        return imported.outcome
    }
}
