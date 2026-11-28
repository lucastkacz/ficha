import FichaCore
import Foundation
internal import GRDB

/// Which of the user's cards an export takes: a deck's, as its `.ficha`
/// (ADR 0044), the one file Ficha writes, which Share Deck… sends (#557).
public enum CardsToExport: Sendable, Hashable {
    /// Every card in this deck, by its whole name, or in a deck inside it;
    /// for Default, by `Deck.defaultName`, the cards in Default.
    case deck(String)

    /// Whether the export takes `card`, whatever its standing: set-aside
    /// cards too, since an export holds what cards say and never where they
    /// stand.
    fileprivate func takes(_ card: Card) -> Bool {
        switch self {
        case .deck(let deck): TagPath.isTag(card.deck, within: deck)
        }
    }
}

extension Engine {
    /// Writes the cards `cards` takes to `file` as the deck's `.ficha`
    /// (`DeckFile.swift`), in the order they came in: a zip with the text
    /// file the import reads, named after `file`, holding what each card
    /// says, its front, back, tags, type and source, its deck, and whether it
    /// goes both ways, and never where it stands, its review log, its flag or
    /// its burial; the cards' images and sounds beside it, each once, which
    /// its lines name; and `deck.json`, holding the deck's own emoji and
    /// description. Returns how many cards it wrote.
    @discardableResult
    public func export(_ cards: CardsToExport, to file: URL) throws(EngineError) -> Int {
        // The deck, with its own emoji and description.
        let (exported, deck) = try read { db -> ([CardsTextFile.ExportedCard], Deck?) in
            let exported = try allCards(in: db).filter(cards.takes).map(exportedCard(of:))
            switch cards {
            case .deck(let name): return (exported, try OwnDecks(in: db).deck(name))
            }
        }
        var images: [CardImage] = []
        for name in Set(exported.flatMap(\.content.images)).sorted(by: { $0.rawValue < $1.rawValue }) {
            images.append(CardImage(name: name, data: try image(name)))
        }
        var sounds: [CardSound] = []
        for name in Set(exported.flatMap(\.content.sounds)).sorted(by: { $0.rawValue < $1.rawValue }) {
            sounds.append(CardSound(name: name, data: try sound(name)))
        }
        let text = CardsTextFile.text(of: exported)
        do {
            // A file the user chose in a save panel, in an app with a
            // sandbox; outside one, there's nothing to start.
            let isAccessing = file.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    file.stopAccessingSecurityScopedResource()
                }
            }
            let data = try zipOfCards(
                text: text, named: file.deletingPathExtension().lastPathComponent + ".txt",
                beside: try deck.map { [try deckJSON(of: $0)] } ?? [], images: images, sounds: sounds, at: time.now)
            try data.write(to: file, options: .atomic)
        } catch {
            logger.error("Couldn't write the exported cards: \(String(describing: error))")
            throw .unwritableFile(file.lastPathComponent)
        }
        return exported.count
    }
}

/// What `card` holds, as an export writes it, which every card it read
/// makes, since every card came in through the same check, its deck, and
/// whether it goes both ways.
private func exportedCard(of card: Card) throws -> CardsTextFile.ExportedCard {
    guard
        let content = CardContent(
            type: card.type, front: card.front, back: card.back, tags: card.tags, source: card.source,
            frontImage: card.frontImage, backImage: card.backImage, frontSound: card.frontSound,
            backSound: card.backSound)
    else {
        throw unreadable("Card \(card.id) has a blank front or back")
    }
    return CardsTextFile.ExportedCard(content: content, deck: card.deck, bothWays: card.bothWays)
}
