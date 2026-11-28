import FichaCore
import FichaSVG
import Foundation
internal import GRDB
internal import ZIPFoundation

// A deck's file, a `.ficha` (ADR 0044, #554): a zip, through ZIPFoundation
// (ADR 0014), holding the deck's cards as `CardsTextFile` reads them, their
// images and sounds, and `deck.json`, with the deck's emoji and description,
// and never the user's progress. The engine writes a deck as one
// (`Engine.export(_:to:)`), reads one without importing it, and brings it in
// as Add Deck… brings in one of Ficha's decks (`FichaDecks.swift`), which
// are such files too: what Open Deck… and a file opened from Finder do
// (`CardsWindowOpenDeck.swift`). `deck.json` beside the text file, and its
// two keys, are our own.

/// A deck's `.ficha`, read without importing it, as `FichaDeckFile` holds one
/// of Ficha's decks: what Open Deck… and a file opened from Finder bring in.
public struct DeckFile: Sendable, Equatable {
    /// The extension of a deck's file, without its dot: the one file Open
    /// Deck… and Finder open in Ficha.
    public static let fileExtension = "ficha"

    /// The deck the file holds, by its whole name, or Default by
    /// `Deck.defaultName`: the deepest deck all its cards come into, as they
    /// come in new, or sit inside, which the emoji and the description
    /// describe.
    public let deck: String
    /// The emoji its `deck.json` holds, which the deck takes when it comes in
    /// new: nil for none.
    public let emoji: String?
    /// The description its `deck.json` holds, which the deck takes when it
    /// comes in new: nil for none.
    public let description: String?
    /// What importing the file would do, as the import read it, with the
    /// images and sounds its cards refer to, which `Engine.addDeck(_:)`
    /// imports.
    let preview: ImportPreview

    /// The file's name, as Finder shows it: "Capitales.ficha".
    public var fileName: String {
        preview.fileName
    }

    /// How many cards the file holds, the deck's own size. How fast? counts
    /// those that come in, fewer when some repeat the user's, which
    /// `Engine.addDeck(_:)` skips.
    public var cardCount: Int {
        preview.cardCount
    }

    /// The lines of its text file of cards that make no card, with why, in
    /// the file's order, which `make preview-import` lists.
    public var leftOut: [LeftOutLine] {
        preview.leftOut
    }
}

/// Why a deck's `.ficha` can't come in, as Open Deck… and a file opened from
/// Finder say it (`EngineError.unreadableFile(_:_:)`).
public enum DeckFileProblem: Error, Sendable, Equatable {
    /// It couldn't be opened or read, as one gone since it was chosen.
    case cannotOpen
    /// It isn't a deck's `.ficha`, by its name's extension: the one file Open
    /// Deck… and Finder open in Ficha (ADR 0044).
    case notADeckFile
    /// It can't be read as a deck's `.ficha`: it isn't a zip, or it holds no
    /// `deck.json` Ficha reads, no text file of cards Ficha reads
    /// (`CardsFileProblem`), or cards that share no deck. The engine logs
    /// which.
    case damagedDeckFile
}

/// What a deck's file's `deck.json` holds: the deck's own emoji and
/// description, each null when it has none, and both always written.
private struct DeckJSON: Codable {
    let emoji: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case emoji, description
    }

    /// Both keys, null for none, which a synthesized encoding leaves out.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(description, forKey: .description)
    }
}

/// The name of the file in a deck's `.ficha` that holds its emoji and its
/// description, at the zip's top.
private let deckJSONName = "deck.json"

/// `deck.json` for the deck `deck`, with its own emoji and description,
/// indented and with its keys sorted, so that a person reads it, and a change
/// to it shows in a diff: its name in a deck's `.ficha`, and what it holds.
func deckJSON(of deck: Deck) throws -> (name: String, data: Data) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (deckJSONName, try encoder.encode(DeckJSON(emoji: deck.emoji, description: deck.description)))
}

/// The emoji and the description the `deck.json` at the top of `archive`
/// holds, as a deck keeps them: the emoji as one, and the description as
/// `Deck.checkedDescription(_:)` keeps it, each nil for none, or blank. A
/// zip without one, or with one that isn't JSON, whose emoji isn't one, or
/// whose description is too long, is a damaged deck's file.
private func emojiAndDescription(in archive: Archive) throws(DeckFileProblem) -> (
    emoji: String?, description: String?
) {
    guard let entry = archive[deckJSONName] else {
        logger.error("A deck's file holds no deck.json")
        throw .damagedDeckFile
    }
    do {
        let held = try JSONDecoder().decode(DeckJSON.self, from: try contents(of: entry, in: archive))
        let emoji = held.emoji.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return (try emoji.map { try Emoji($0).text }, try Deck.checkedDescription(held.description))
    } catch {
        logger.error("Couldn't read a deck's deck.json: \(String(describing: error), privacy: .public)")
        throw .damagedDeckFile
    }
}

extension Engine {
    /// Reads the deck's `.ficha` at `file` without importing it, through
    /// the import's reader and its preview: its cards, images and sounds, the deck they're in, and the emoji and
    /// the description its `deck.json` holds. A file that isn't a zip, holds
    /// no `deck.json` it can read or no text file of cards, or whose cards
    /// share no deck is a damaged deck's file, which it refuses, saying so;
    /// one it can't open, as one gone since, says that. It takes a while for
    /// a big file, so the app calls it away from the main actor.
    public func readDeckFile(at file: URL) async throws(EngineError) -> DeckFile {
        let name = file.lastPathComponent
        // A file the user chose in an open panel, or opened from Finder, in
        // an app with a sandbox, held until it's read; outside one, there's
        // nothing to start.
        let isAccessing = file.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                file.stopAccessingSecurityScopedResource()
            }
        }
        let held: (emoji: String?, description: String?)
        let zipped: (reading: ImportReading, images: [ImageName: CardImage], sounds: [SoundName: CardSound])
        do throws(DeckFileProblem) {
            let archive = try deckArchive(at: file)
            held = try emojiAndDescription(in: archive)
            zipped = try await cardsInDeckFile(archive, drawingSVGsWith: newSVGDrawer?())
        } catch {
            throw .unreadableFile(name, error)
        }
        let preview = try self.preview(
            zipped.reading.outsideDefault(), of: name, images: zipped.images, sounds: zipped.sounds)
        guard let deck = try sharedDeck(of: preview.cards) else {
            logger.error("A deck's file holds no cards, or cards that share no deck")
            throw .unreadableFile(name, .damagedDeckFile)
        }
        return DeckFile(deck: deck, emoji: held.emoji, description: held.description, preview: preview)
    }

    /// Adds the deck `file` holds, as `addFichaDeck(_:)` adds one of Ficha's
    /// decks: its cards that repeat none of the user's, into the decks they
    /// name, with their own tags alone; those that repeat one stay as the
    /// user's are, with their progress, so adding it twice adds nothing. A
    /// deck the user didn't have, no card in it or in a deck inside it, and
    /// no row for either, that cards came into, takes the emoji and the
    /// description its `deck.json` holds; one they had keeps its own, or its
    /// lack of one. Returns what the import did.
    @discardableResult
    public func addDeck(_ file: DeckFile) throws(EngineError) -> ImportOutcome {
        let had = try read { db in try hasDeck(file.deck, in: db) }
        let outcome = try importCards(file.preview)
        if !had, outcome.added > 0, file.emoji != nil || file.description != nil {
            try write { db in
                try changeOwnDecks([file.deck], in: db) { deck in
                    deck.emoji = file.emoji
                    deck.description = file.description
                }
            }
        }
        return outcome
    }

    /// The deck `cards` are in, by its whole name, as they'd come in new, or
    /// Default by `Deck.defaultName` for one that names none
    /// (`deckComingIn(proposed:)`): the deepest deck each is
    /// in, or sits inside; or nil for no cards, or cards whose decks share
    /// none, as Default and another, or two at the top of the tree. An error
    /// for a deck's name the import refuses.
    private func sharedDeck(of cards: [ImportedCard]) throws(EngineError) -> String? {
        var decks: Set<String> = []
        for card in cards {
            decks.insert(try deckComingIn(proposed: card.deck))
        }
        guard let some = decks.first else {
            return nil
        }
        // The lineage lists the deck first, then those it sits inside.
        return TagPath.lineage(of: some).first { deck in decks.allSatisfy { TagPath.isTag($0, within: deck) } }
    }
}

/// The zip at `file`, a deck's `.ficha`, open to read its files as they're
/// needed, or why it can't be: one that can't be opened, and one that isn't
/// a zip, or a damaged one, which is a damaged deck's file.
private func deckArchive(at file: URL) throws(DeckFileProblem) -> Archive {
    let archive: Archive?
    do throws(CardsFileProblem) {
        archive = try zipArchive(at: file)
    } catch {
        throw error == .cannotOpen ? .cannotOpen : .damagedDeckFile
    }
    guard let archive else {
        logger.error("A deck's file isn't a zip")
        throw .damagedDeckFile
    }
    return archive
}

/// What the text file of cards in `archive`, a deck's `.ficha`, holds, with
/// its cards' images and sounds, as `readZipOfCards(_:drawingSVGsWith:)`
/// reads them, its SVGs drawn by `drawer`; or, for a text file or a zip
/// Ficha can't read, which the engine logs, a damaged deck's file.
private func cardsInDeckFile(_ archive: Archive, drawingSVGsWith drawer: (any SVGDrawer)?) async throws(DeckFileProblem)
    -> (reading: ImportReading, images: [ImageName: CardImage], sounds: [SoundName: CardSound])
{
    do throws(CardsFileProblem) {
        return try await readZipOfCards(archive, drawingSVGsWith: drawer)
    } catch {
        logger.error("Couldn't read a deck's file: \(String(describing: error), privacy: .public)")
        throw .damagedDeckFile
    }
}

/// Whether the user has the deck `deck`, by its whole name: a card of theirs
/// is in it or in a deck inside it, or the `deck` table has a row for one of
/// them, as for a deck made with no cards.
private func hasDeck(_ deck: String, in db: Database) throws -> Bool {
    (try allCards(in: db).map(\.deck) + OwnDecks(in: db).names).contains { TagPath.isTag($0, within: deck) }
}
