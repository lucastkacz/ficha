import FichaCore
import Foundation

// A deck's tags (ADR 0024): the tags its cards carry, those of the decks
// inside it too, each with how many of them carry it or a tag inside it, as
// All Tags counts a tag's cards (ADR 0021). The Cards window shows them above
// the card list while the sidebar chose the deck, and one of them narrows the
// list (`CardsWindowDeckTags.swift`). They come from the cards' tags alone:
// nothing of them is stored.

/// A tag the cards of a deck carry, with how many of them do.
public struct DeckTag: Sendable, Equatable, Identifiable {
    /// The tag, with what it has of its own and takes from the tags it sits
    /// inside.
    public let tag: CardTag
    /// How many of the deck's cards carry it or a tag inside it: those that
    /// live in the deck or in a deck inside it, and aren't buried, as the
    /// deck lists them when it's chosen.
    public let cards: Int

    public init(tag: CardTag, cards: Int) {
        self.tag = tag
        self.cards = cards
    }

    public var id: String {
        tag.name
    }
}

extension Engine {
    /// The tags of the deck `deck`, by its whole name, or Default's by
    /// `Deck.defaultName`: every tag a card it lists carries, and every tag
    /// those sit inside, each with how many of those cards carry it or a tag
    /// inside it, the most first, and in the order a tree lists them between
    /// two that count as many. None for a deck whose cards carry no tag, or
    /// that isn't there.
    public func tags(inDeck deck: String) throws(EngineError) -> [DeckTag] {
        try read { db in
            let own = try OwnTags(in: db)
            var counts: [String: Int] = [:]
            for card in try allCards(in: db)
            where TagPath.isTag(card.deck, within: deck) && card.standing.isInAllCards {
                for tag in TagPath.lineages(of: card.tags) {
                    counts[tag, default: 0] += 1
                }
            }
            let inTreeOrder = TagPath.sortedAsTree(counts.keys).enumerated().map { (place: $0, name: $1) }
            return inTreeOrder.sorted { first, second in
                let (firstCount, secondCount) = (counts[first.name, default: 0], counts[second.name, default: 0])
                return firstCount != secondCount ? firstCount > secondCount : first.place < second.place
            }
            .map { DeckTag(tag: own.tag($0.name), cards: counts[$0.name, default: 0]) }
        }
    }
}
