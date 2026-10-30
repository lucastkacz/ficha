import FichaCore
import FichaData
import Foundation
import Testing

/// Approves a capture into one word card with this front and these tags, the
/// way refining saves cards, moves it to `deck` with Change Deck, unless it's
/// Default, where a card lives when it has no other, and returns the card as
/// it is then: a new card, after the ones approved before it.
@discardableResult
func approveInDeck(_ front: String, deck: String, tags: [String] = [], in engine: Engine) throws -> Card {
    let approved = try approve(
        card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    guard deck != Deck.defaultName else {
        return approved
    }
    try engine.changeDeck(of: [approved.id], to: deck)
    return try #require(try engine.cards().first { $0.id == approved.id })
}
