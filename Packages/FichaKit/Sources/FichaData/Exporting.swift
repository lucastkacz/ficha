import FichaCore
import Foundation
internal import GRDB

/// Which of the user's cards an export takes.
public enum CardsToExport: Sendable, Hashable {
    /// The cards with these ids: those the user selected.
    case cards(Set<Int64>)
    /// Every card with this tag.
    case tag(String)
    /// Every card.
    case all

    /// Whether the export takes `card`, whatever its standing: buried cards
    /// too, which the Cards window lists apart, since an export holds what
    /// cards say and never where they stand.
    fileprivate func takes(_ card: Card) -> Bool {
        switch self {
        case .cards(let ids): ids.contains(card.id)
        case .tag(let tag): card.tags.contains(tag)
        case .all: true
        }
    }
}

extension Engine {
    /// Writes the cards `cards` takes to `file`, in the order they came in,
    /// as the text file the import reads: what each card says, its front,
    /// back, tags, type and source, and never where it stands, its review
    /// log, its flag or its burial. When a card it takes has an image, the
    /// file is a zip instead, with that text file, named after `file`, and
    /// the cards' images beside it, which its lines name. Returns how many
    /// cards it wrote.
    @discardableResult
    public func export(_ cards: CardsToExport, to file: URL) throws(EngineError) -> Int {
        let contents = try read { db in
            try allCards(in: db).filter(cards.takes).map(exportedContent(of:))
        }
        var images: [CardImage] = []
        let names = Set(contents.flatMap(\.images))
        for name in names.sorted(by: { $0.rawValue < $1.rawValue }) {
            images.append(CardImage(name: name, data: try image(name)))
        }
        let text = CardsTextFile.text(of: contents)
        do {
            // A file the user chose in a save panel, in an app with a
            // sandbox; outside one, there's nothing to start.
            let isAccessing = file.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    file.stopAccessingSecurityScopedResource()
                }
            }
            let data =
                images.isEmpty
                ? Data(text.utf8)
                : try zipOfCards(
                    text: text, named: file.deletingPathExtension().lastPathComponent + ".txt", images: images,
                    at: time.now)
            try data.write(to: file, options: .atomic)
        } catch {
            logger.error("Couldn't write the exported cards: \(String(describing: error))")
            throw .unwritableFile(file.lastPathComponent)
        }
        return contents.count
    }

    /// How many cards each of `choices` takes, in its order, as the cards
    /// are now, read once for all of them, and whether one of them has an
    /// image, which makes the export a zip.
    func cardCounts(toExport choices: [CardsToExport]) throws(EngineError) -> [(count: Int, holdsImages: Bool)] {
        try read { db in
            let cards = try allCards(in: db)
            return choices.map { choice in
                let taken = cards.filter(choice.takes)
                return (taken.count, taken.contains { !$0.images.isEmpty })
            }
        }
    }
}

/// What `card` holds, as an export writes it, which every card it read
/// makes, since every card came in through the same check.
private func exportedContent(of card: Card) throws -> CardContent {
    guard
        let content = CardContent(
            type: card.type, front: card.front, back: card.back, tags: card.tags, source: card.source,
            frontImage: card.frontImage, backImage: card.backImage)
    else {
        throw unreadable("Card \(card.id) has a blank front or back")
    }
    return content
}
