import FichaCore
import FichaData
import Foundation
import Testing

/// Creates one word card with this front and these tags, moves it to
/// `deck` with Change Deck, unless it's Default, where a card lives when it
/// has no other, and returns the card as it is then: a new card, after the
/// ones before it.
@discardableResult
func newCardInDeck(
    _ front: String, deck: String = Deck.defaultName, tags: [String] = [], in engine: Engine
) throws -> Card {
    let created = try newCard(
        card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    guard deck != Deck.defaultName else {
        return created
    }
    try engine.changeDeck(of: [created.id], to: deck)
    return try #require(try engine.cards().first { $0.id == created.id })
}

extension [CardsWindowState.DeckRow] {
    /// The tree, a row per deck in its order, each its title, or Default's
    /// name, its due count and " grayed" when it's grayed, indented two
    /// spaces per level.
    var outline: [String] {
        lines.map { line in
            let row = line.node
            let title = row.deck.isDefault ? "Default" : row.title
            let indent = String(repeating: "  ", count: line.depth)
            return "\(indent)\(title) \(row.counts.due)" + (row.isGrayed ? " grayed" : "")
        }
    }
}
