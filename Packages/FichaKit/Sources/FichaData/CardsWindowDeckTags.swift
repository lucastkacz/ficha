import FichaCore
import Foundation

// A deck's tags in the Cards window (ADR 0024): while the sidebar chose a
// deck, the row above the card list shows the tags its cards carry, those of
// the decks inside it too, each with how many of them carry it, the most
// first (`DeckTags.swift`). The ones that fit show, up to 15, and "+N more"
// lists the rest; the window's width decides how many fit, which only the
// view knows, so the state offers the rows it may show (`deckTagsRows`), the
// most tags first, and the view shows the first that fits. Lucas chooses one
// at a time, which narrows the deck's cards to those that carry it or a tag
// inside it, with the search; choosing it again, or something else in the
// sidebar, lists them all again.

extension CardsWindowState {
    /// The most tags the row shows before "+N more", however wide the window:
    /// a deck with hundreds of tags, as an Anki package can bring, gives the
    /// view a few rows to try, not hundreds.
    private static let mostDeckTagsShown = 15

    /// A row of the chosen deck's tags, for the width that fits as many as
    /// it shows beside "+N more": the tags it shows, and those "+N more"
    /// lists.
    public struct DeckTagsRow: Sendable, Equatable {
        /// The tags it shows, in their order: the first that fit, the chosen
        /// one always among them, in the last place, when it would be further
        /// on.
        public let shown: [DeckTag]
        /// The tags "+N more" lists, in their order: the rest, none while
        /// every tag fits.
        public let more: [DeckTag]
    }

    /// The rows of the chosen deck's tags the bar above the card list may
    /// show, the most tags first, for the view to show the first that fits
    /// the window's width: every tag, or the first 15 and "+N more" for the
    /// rest, then one fewer each time, down to "+N more" alone. None while
    /// the sidebar chose no deck, or its cards carry no tag.
    public var deckTagsRows: [DeckTagsRow] {
        guard !deckTags.isEmpty else { return [] }
        return (0...min(deckTags.count, Self.mostDeckTagsShown)).reversed().map(deckTagsRow(fitting:))
    }

    /// The row of the chosen deck's tags (`deckTags`) when `count` of them
    /// fit: the first `count`, the most cards first, and the rest in "+N
    /// more"; or, when Lucas chose a tag further on, the first `count - 1`
    /// and the chosen one, so that it always shows while one fits, and "+N
    /// more" lists the others.
    private func deckTagsRow(fitting count: Int) -> DeckTagsRow {
        guard count < deckTags.count else {
            return DeckTagsRow(shown: deckTags, more: [])
        }
        let first = Array(deckTags.prefix(count))
        guard count > 0, let chosen = deckTags.first(where: { $0.id == chosenDeckTag }), !first.contains(chosen)
        else {
            return DeckTagsRow(shown: first, more: Array(deckTags.dropFirst(count)))
        }
        let shown = first.dropLast() + [chosen]
        return DeckTagsRow(shown: Array(shown), more: deckTags.filter { !shown.contains($0) })
    }

    /// Chooses the tag `tag` in the row of the chosen deck's tags, or "+N
    /// more": lists only the deck's cards that carry it or a tag inside it,
    /// or all of them again when it's the one chosen. A tag the row doesn't
    /// show changes nothing.
    public mutating func chooseDeckTag(_ tag: String) {
        guard deckTags.contains(where: { $0.id == tag }) else { return }
        chosenDeckTag = chosenDeckTag == tag ? nil : tag
        read(on: ladder)
    }

    /// Reads the tags of the deck the sidebar chose, or none while it chose
    /// no deck, and lets go of the chosen one once they no longer hold it.
    mutating func readDeckTags() throws(EngineError) {
        if case .cards(.deck(let deck)) = sidebarItem {
            deckTags = try engine.tags(inDeck: deck)
        } else {
            deckTags = []
        }
        if let chosen = chosenDeckTag, !deckTags.contains(where: { $0.id == chosen }) {
            chosenDeckTag = nil
        }
    }

    /// `rows`, the chosen deck's cards, narrowed to those that carry the tag
    /// Lucas chose in its row, or a tag inside it; all of them while he chose
    /// none.
    func narrowedToChosenDeckTag(_ rows: [CardRow]) -> [CardRow] {
        guard let chosen = chosenDeckTag else { return rows }
        return rows.filter { $0.card.hasTag(within: chosen) }
    }
}
