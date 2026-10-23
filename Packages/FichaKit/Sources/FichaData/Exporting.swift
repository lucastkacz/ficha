import FichaCore
import Foundation
internal import GRDB

/// Which of the user's cards an export takes.
public enum CardsToExport: Sendable, Hashable {
    /// The cards with these ids, whatever their standing: those the user
    /// selected.
    case cards(Set<Int64>)
    /// The cards with this tag that aren't buried, as the Cards window's
    /// sidebar lists them under the tag.
    case tag(String)
    /// Every card that isn't buried, as the Cards window's All cards lists
    /// them.
    case all

    /// Whether the export takes `card`.
    fileprivate func takes(_ card: Card) -> Bool {
        switch self {
        case .cards(let ids): ids.contains(card.id)
        case .tag(let tag): card.tags.contains(tag) && card.standing.isInAllCards
        case .all: card.standing.isInAllCards
        }
    }
}

extension Engine {
    /// Writes the cards `cards` takes to `file`, in the order they came in,
    /// as the text file the import reads: what each card says, its front,
    /// back, tags, type and source, and never where it stands, its review
    /// log, its flag or its burial. Returns how many cards it wrote.
    @discardableResult
    public func export(_ cards: CardsToExport, to file: URL) throws(EngineError) -> Int {
        let contents = try read { db in
            try allCards(in: db).filter(cards.takes).map(exportedContent(of:))
        }
        do {
            // A file the user chose in a save panel, in an app with a
            // sandbox; outside one, there's nothing to start.
            let isAccessing = file.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    file.stopAccessingSecurityScopedResource()
                }
            }
            try Data(CardsTextFile.text(of: contents).utf8).write(to: file, options: .atomic)
        } catch {
            logger.error("Couldn't write the exported cards: \(String(describing: error))")
            throw .unwritableFile(file.lastPathComponent)
        }
        return contents.count
    }

    /// How many cards each of `choices` takes, in its order, as the cards
    /// are now, read once for all of them.
    func cardCounts(toExport choices: [CardsToExport]) throws(EngineError) -> [Int] {
        try read { db in
            let cards = try allCards(in: db)
            return choices.map { choice in cards.count(where: choice.takes) }
        }
    }
}

/// What `card` holds, as an export writes it, which every card it read
/// makes, since every card came in through the same check.
private func exportedContent(of card: Card) throws -> CardContent {
    guard
        let content = CardContent(
            type: card.type, front: card.front, back: card.back, tags: card.tags, source: card.source)
    else {
        throw unreadable("Card \(card.id) has a blank front or back")
    }
    return content
}
