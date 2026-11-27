import FichaCore
import Foundation

// The Cards window's grid (#536), where its table was: the chosen deck's
// cards as tiles, in the order they came in, which is the order its new
// cards wait their turn in, each its front's picture, or else its front's
// text, with a dot for where it stands, as the desktop mock draws it (ADR
// 0041): green once the user met the card, orange while it's due, and none
// while it's new, whose tile is dimmed. What a tile shows is the window's
// decision, so FichaData works it out here, and the app's grid
// (`App/Cards/CardGrid.swift`) draws it, reading each tile's picture as the
// tile appears (`TileImages`). Lucas selects tiles as in Photos and
// the Finder: a click selects one, a ⌘-click adds one or takes it out, a
// Shift-click selects the run from the last one clicked, the arrow keys move
// the selection, Shift extending the run with them, and Select All selects
// every tile.

extension CardsWindowState {
    /// A card as a tile of the grid shows it.
    public struct Tile: Sendable, Equatable, Identifiable {
        /// What fills a tile.
        public enum Face: Sendable, Equatable {
            /// The front's picture, the image named this, which fills the
            /// tile.
            case picture(ImageName)
            /// The front's text, as the user wrote it.
            case text(String)
            /// A front that holds a sound alone, which the tile names with a
            /// word.
            case sound
        }

        /// Where a tile's card stands, which its dot says.
        public enum Mark: Sendable, Hashable {
            /// The user met the card, and it isn't due: a green dot.
            case met
            /// The card is in the user's reviews, and a way of it is due: an
            /// orange dot.
            case due
            /// The user hasn't met the card yet, which waits its turn in the
            /// queue: no dot, and the tile dimmed.
            case new
        }

        /// The card's.
        public let id: CardRow.ID
        /// What fills the tile.
        public let face: Face
        /// Where the card stands.
        public let mark: Mark
        /// The front's text, empty when it has none, which names the tile
        /// for VoiceOver, a picture's too.
        public let front: String

        /// The tile of the card in `row`, which stands at `now`. A card is
        /// met once its front-first way has an entry, as a deck's row counts
        /// the cards met (`CardsInReviews.metCards(in:)`), whether or not it
        /// goes back first too.
        init(_ row: CardRow, at now: Date) {
            id = row.id
            let card = row.card
            front = card.front
            if let image = card.frontImage {
                face = .picture(image)
            } else if card.front.isEmpty, card.frontSound != nil {
                face = .sound
            } else {
                face = .text(card.front)
            }
            if row.isDue(at: now) {
                mark = .due
            } else if case .new = row.frontFirst.standing {
                mark = .new
            } else {
                mark = .met
            }
        }
    }

    /// Where an arrow key moves the grid's selection: to the tile before
    /// the selected one or after it, in the order the grid lists them, or to
    /// the one above it or below it. The app takes the arrow that points
    /// backward or forward from its layout's direction.
    public enum TileMove: Sendable, Equatable {
        case backward
        case forward
        case up
        case down
    }

    /// How a click selects a tile, as the keys held down while clicking say.
    public enum TileClick: Sendable, Equatable {
        /// A click alone, which selects the tile alone.
        case alone
        /// A ⌘-click, which adds the tile to the selection, or takes it out
        /// when it's in.
        case adding
        /// A Shift-click, which selects the run of tiles from the last one
        /// clicked to this one.
        case extending
    }

    /// What reads the pictures of the grid's tiles, one image at a time, as
    /// each tile appears: the app reads them away from the main actor, and
    /// keeps a thumbnail of each in a cache of its own, which lets go of
    /// those it doesn't need (`App/Cards/CardGrid.swift`). So the window
    /// reads none of them as it lists the cards or as Lucas selects one,
    /// which, for a deck of photos, would read them all at their full size
    /// on the main actor each time. Which image a tile shows is its face's
    /// (`Tile.Face.picture`).
    public struct TileImages: Sendable {
        let engine: Engine

        /// The image named `name`, as Ficha keeps it, or why it couldn't be
        /// read, or nil while it's on its way from another device, which the
        /// tile shows without, with no error, until it's read again once the
        /// window reads the cards again.
        public func image(_ name: ImageName) -> Result<Data, EngineError>? {
            engine.imageToShow(name)
        }
    }

    /// The tiles of the cards the grid lists, in its order: none while the
    /// window lists something else, such as the inbox.
    public var tiles: [Tile] {
        guard case .success(.cards(let rows))? = listing else {
            return []
        }
        return rows.map { Tile($0, at: now) }
    }

    /// What reads the pictures of the grid's tiles.
    public var tileImages: TileImages {
        TileImages(engine: engine)
    }

    /// The ids of the cards the grid lists, in its order.
    private var gridCardIDs: [CardRow.ID] {
        guard case .success(.cards(let rows))? = listing else {
            return []
        }
        return rows.map(\.id)
    }

    /// Selects the tile of the card `id` as a click does, as `click` says:
    /// alone, adding it or taking it out, or the run from the last tile
    /// clicked, or selected alone, to it, which a Shift-click selects alone
    /// while there's none listed.
    public mutating func clickTile(_ id: CardRow.ID, _ click: TileClick) {
        let listed = gridCardIDs
        guard listed.contains(id) else { return }
        switch click {
        case .alone:
            anchorCard = id
            setSelection([id])
        case .adding:
            anchorCard = id
            setSelection(selection.contains(id) ? selection.subtracting([id]) : selection.union([id]))
        case .extending:
            guard let anchor = anchorCard, let run = Self.run(from: anchor, to: id, in: listed) else {
                anchorCard = id
                setSelection([id])
                break
            }
            setSelection(run)
        }
        currentCard = id
    }

    /// Moves the grid's selection as an arrow key does, as `move` says, in a
    /// grid of `tilesPerRow` tiles a row, as the app lays it out: from the
    /// last tile clicked or moved to, to the next one that way, which the
    /// grid scrolls to, selected alone, or with Shift, when `extending` says
    /// so, the run from the last tile clicked to it. While no tile listed is
    /// selected, any arrow selects the first. At an edge it stays where it
    /// is.
    public mutating func moveSelection(_ move: TileMove, tilesPerRow: Int, extending: Bool) {
        let listed = gridCardIDs
        guard !listed.isEmpty else { return }
        let target: CardRow.ID
        if let current = currentCard, selection.contains(current), let index = listed.firstIndex(of: current) {
            target = listed[Self.index(after: move, from: index, among: listed.count, perRow: max(tilesPerRow, 1))]
        } else {
            target = listed[0]
        }
        if extending, let anchor = anchorCard, let run = Self.run(from: anchor, to: target, in: listed) {
            setSelection(run)
        } else {
            anchorCard = target
            setSelection([target])
        }
        currentCard = target
        cardToReveal = target
    }

    /// Selects every tile the grid lists, as Select All, ⌘A, does.
    public mutating func selectAllTiles() {
        let listed = gridCardIDs
        guard !listed.isEmpty else { return }
        setSelection(Set(listed))
    }

    /// Selects `selection`, reading the review log of the card the detail
    /// then shows.
    private mutating func setSelection(_ selection: Set<CardRow.ID>) {
        let anchor = anchorCard
        let current = currentCard
        select(selection)
        // A tile selected alone by a click or a key is already where the
        // next ones go from; a run keeps where it started.
        anchorCard = anchor
        currentCard = current
    }

    /// The ids of the tiles from `start` to `end`, both in, in `listed`'s
    /// order, or nil when it lists either no longer.
    private static func run(from start: CardRow.ID, to end: CardRow.ID, in listed: [CardRow.ID]) -> Set<CardRow.ID>? {
        guard let first = listed.firstIndex(of: start), let last = listed.firstIndex(of: end) else {
            return nil
        }
        return Set(listed[min(first, last)...max(first, last)])
    }

    /// The index of the tile `move` goes to from the one at `index`, among
    /// `count` tiles laid out `perRow` a row: the same one at an edge. Down
    /// from a tile with none right below it, in the row before the last,
    /// goes to the last tile, as in the Finder.
    private static func index(after move: TileMove, from index: Int, among count: Int, perRow: Int) -> Int {
        switch move {
        case .backward:
            return max(index - 1, 0)
        case .forward:
            return min(index + 1, count - 1)
        case .up:
            return index >= perRow ? index - perRow : index
        case .down:
            let lastRow = (count - 1) / perRow
            return index / perRow < lastRow ? min(index + perRow, count - 1) : index
        }
    }
}
