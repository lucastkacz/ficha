import AppKit
import FichaCore
import FichaData
import ImageIO
import SwiftUI

/// The Cards window's grid, in the middle pane, as the desktop mock draws it
/// (#536): the cards the sidebar chose, narrowed by the search, as tiles in
/// the order the state lists them, under a legend of their dots, as many a
/// row as fit the pane. A tile shows its front's picture, filling it, or
/// else its front's text, centered, with a dot for where its card stands:
/// green once Lucas met it, orange while it's due, and none while it's new,
/// whose tile is dimmed (`CardsWindowGrid.swift` decides which). Lucas
/// selects tiles as in Photos and the Finder, and the state decides what
/// each click and key selects: a click selects one, a ⌘-click adds one or
/// takes it out, a Shift-click selects the run from the last one clicked, a
/// click between the tiles selects none, the arrow keys move the selection,
/// with Shift extending the run, and Edit › Select All, ⌘A, selects every
/// tile, all while the grid has the keyboard, which a click gives it. He
/// drags a tile onto a deck in the sidebar, with the other selected ones
/// when it's one of them, as Change Deck… moves them (`SidebarDrops.swift`),
/// and the state says what the drag carries.
struct CardGrid: View {
    @Binding var state: CardsWindowState
    /// Whether the grid has the keyboard, for the arrow keys and Select All.
    let isFocused: FocusState<Bool>.Binding
    /// How many tiles a row the grid lays out, which the arrow keys go up
    /// and down by.
    @State private var tilesPerRow = 1
    /// The thumbnails of the tiles' pictures, which the tiles make as they
    /// appear, and keep while there's room.
    @State private var thumbnails = TileThumbnails()
    @Environment(\.layoutDirection) private var layoutDirection

    /// The least width of a tile, as the mock's: the grid fits as many as it
    /// can in a row, and shares out what's left among them.
    private static let tileWidth: CGFloat = 112
    /// The room between two tiles, and between two rows.
    private static let spacing: CGFloat = 10

    var body: some View {
        let tiles = state.tiles
        VStack(alignment: .leading, spacing: 0) {
            GridLegend()
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Self.tileWidth), spacing: Self.spacing)],
                        spacing: Self.spacing
                    ) {
                        ForEach(tiles) { tile in
                            tileView(tile)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.width
                    } action: { width in
                        // As SwiftUI lays out an adaptive grid's columns.
                        tilesPerRow = max(1, Int((width + Self.spacing) / (Self.tileWidth + Self.spacing)))
                    }
                    .padding(16)
                }
                // A click between the tiles selects none, as in the Finder: a
                // tile's own click takes precedence over this one.
                .contentShape(.rect)
                .onTapGesture {
                    isFocused.wrappedValue = true
                    state.clickBetweenTiles()
                }
                // The card Show Card selected, or the arrow keys moved to,
                // which may be far down the grid.
                .onChange(of: state.cardToReveal, initial: true) {
                    guard let id = state.cardToReveal else { return }
                    proxy.scrollTo(id)
                    state.cardRevealed()
                }
            }
        }
        .focusable(interactions: .edit)
        .focused(isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            state.moveSelection(
                move(for: press.key), tilesPerRow: tilesPerRow, extending: press.modifiers.contains(.shift))
            return .handled
        }
        // Edit › Select All, from the menu or by ⌘A, sent to the grid while
        // it has the keyboard: a text field that has it, as the search field
        // or the editor's, selects its own text instead.
        .onCommand(#selector(NSResponder.selectAll(_:))) {
            state.selectAllTiles()
        }
    }

    /// The tile of `tile`, which a click selects, as the keys held down say,
    /// and Lucas drags onto a deck, with what the state says it drags.
    private func tileView(_ tile: CardsWindowState.Tile) -> some View {
        let isSelected = state.selection.contains(tile.id)
        let images = state.tileImages
        return CardTile(tile: tile, isSelected: isSelected, thumbnails: thumbnails, images: images, readAt: state.now)
            .id(tile.id)
            .onTapGesture {
                click(tile.id)
            }
            .accessibilityAction {
                isFocused.wrappedValue = true
                state.clickTile(tile.id, .alone)
            }
            .draggable(SidebarDrag(dragged: state.draggedCards(from: tile.id)))
    }

    /// Selects the tile of the card `id` as a click with the keys Lucas
    /// holds down does: Shift selects the run, ⌘ adds it or takes it out.
    private func click(_ id: CardRow.ID) {
        let keys = NSEvent.modifierFlags
        let click: CardsWindowState.TileClick =
            keys.contains(.shift) ? .extending : keys.contains(.command) ? .adding : .alone
        isFocused.wrappedValue = true
        state.clickTile(id, click)
    }

    /// Where the arrow key `key` moves the selection: up and down by a row,
    /// and the side arrows backward and forward in the layout's direction,
    /// which lays the tiles out from the right in a language that reads
    /// that way.
    private func move(for key: KeyEquivalent) -> CardsWindowState.TileMove {
        if key == .upArrow {
            return .up
        }
        if key == .downArrow {
            return .down
        }
        let pointsForward = (key == .rightArrow) == (layoutDirection == .leftToRight)
        return pointsForward ? .forward : .backward
    }
}

/// What the dots on the tiles say, above the grid, as the mock writes it.
private struct GridLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach([CardsWindowState.Tile.Mark.met, .due, .new], id: \.self) { mark in
                HStack(spacing: 4) {
                    Circle()
                        .fill(mark.legendColor)
                        .frame(width: 7, height: 7)
                    mark.name
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// A card's tile in the grid, four by three: its front's picture, filling
/// it, or else its front's text, or the word Sound for a front with a sound
/// alone, as the Cards window says it (`FrontCell`), with its dot at its top
/// corner, on the trailing side; dimmed while it's new, and ringed with the
/// accent color while it's selected. VoiceOver reads it as its front, and
/// where it stands. A picture's tile reads its image as it appears, away
/// from the main actor, and makes a thumbnail of it, which the grid's
/// `TileThumbnails` keeps while there's room, and the tile while it's in
/// sight; it reads it again each time the window reads the cards while it
/// couldn't show it, as while it's on its way from another device.
private struct CardTile: View {
    /// A picture a tile shows, as it is.
    enum Picture {
        case shown(CGImage)
        /// Not read yet, which it is soon after the tile appears, or on its
        /// way from another device.
        case unread
        /// Not an image, or its file couldn't be read.
        case unreadable
    }

    /// What a tile reads its picture again for: its image, and when the
    /// window last read the cards.
    nonisolated struct PictureRead: Equatable {
        let name: ImageName
        let readAt: Date
    }

    let tile: CardsWindowState.Tile
    let isSelected: Bool
    /// The thumbnails the grid's tiles made, which this one's picture comes
    /// from while they keep it.
    let thumbnails: TileThumbnails
    /// What reads the tile's image.
    let images: CardsWindowState.TileImages
    /// When the window last read the cards.
    let readAt: Date
    /// The picture the tile made of its image, by the image's name, while
    /// it's in sight.
    @State private var made: (name: ImageName, picture: Picture)? = nil

    private var isNew: Bool {
        tile.mark == .new
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12)
    }

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                face
            }
            .background(isNew ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.background), in: shape)
            .clipShape(shape)
            .overlay(alignment: .topTrailing) {
                dot
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(.tint, lineWidth: 2)
                } else if !isNew {
                    shape.strokeBorder(.separator, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(isNew ? 0 : isSelected ? 0.12 : 0.08), radius: isSelected ? 4 : 1.5, y: 1)
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(tile.mark.name)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .task(id: pictureRead) {
                guard let pictureRead else { return }
                await makePicture(pictureRead)
            }
            .onDisappear {
                made = nil
            }
    }

    /// What the tile reads its picture for, while its face is one.
    private var pictureRead: PictureRead? {
        guard case .picture(let name) = tile.face else { return nil }
        return PictureRead(name: name, readAt: readAt)
    }

    /// The picture of the image `name`: the one the tile made, or else the
    /// grid's thumbnail, or else that it isn't read yet.
    private func picture(named name: ImageName) -> Picture {
        if let made, made.name == name {
            return made.picture
        }
        return thumbnails.thumbnail(name).map(Picture.shown) ?? .unread
    }

    /// Makes the tile's picture for `read`: the grid's thumbnail of its
    /// image while it keeps one, or else one made of the image, which the
    /// grid keeps; or that it can't be shown, or not yet.
    private func makePicture(_ read: PictureRead) async {
        if let thumbnail = thumbnails.thumbnail(read.name) {
            made = (name: read.name, picture: .shown(thumbnail))
            return
        }
        let thumbnail = await madeThumbnail(of: read.name, readingWith: images)
        if case .made(let image, let cost) = thumbnail {
            thumbnails.keep(image, costing: cost, as: read.name)
        }
        // Out of sight, or read again, meanwhile.
        guard !Task.isCancelled else { return }
        switch thumbnail {
        case .made(let image, _):
            made = (name: read.name, picture: .shown(image))
        case .unreadable:
            made = (name: read.name, picture: .unreadable)
        case .onItsWay:
            made = (name: read.name, picture: .unread)
        }
    }

    /// What fills the tile.
    @ViewBuilder
    private var face: some View {
        switch tile.face {
        case .picture(let name):
            switch picture(named: name) {
            case .shown(let image):
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .opacity(isNew ? 0.7 : 1)
            case .unreadable:
                placeholder("photo.badge.exclamationmark")
            case .unread:
                placeholder("photo")
            }
        case .text(let text):
            // Centered, as the mock draws it: centered lines have no side
            // to start from, and SwiftUI gives each its text's own direction,
            // so an Arabic front reads from the right there too.
            Text(text)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(isNew ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        case .sound:
            Label {
                soundWord
            } icon: {
                Image(systemName: "speaker.wave.2")
            }
            .foregroundStyle(.secondary)
            .padding(10)
        }
    }

    /// The word for a front with a sound alone, as the Cards window says it.
    private var soundWord: Text {
        Text("Sound", comment: "The Cards window, in place of a card's front that has only a sound.")
    }

    /// In place of a picture the tile can't show yet, or at all: the symbol
    /// `symbol`, on the fill a picture leaves.
    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.fill.quaternary)
    }

    /// The dot that says where the card stands, ringed with the window's
    /// background so it reads on a picture too: none for a new card.
    @ViewBuilder
    private var dot: some View {
        if let color = tile.mark.dotColor {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(2)
                .background(.background, in: .circle)
                .padding(.top, 6)
                .padding(.trailing, 7)
        }
    }

    /// What VoiceOver names the tile: its front's text, or, for a front
    /// without text, the word the Cards window says in its place.
    private var label: Text {
        switch tile.face {
        case .text(let text):
            Text(verbatim: text)
        case .picture:
            tile.front.isEmpty
                ? Text("Image", comment: "The Cards window, in place of a card's front that has an image and no text.")
                : Text(verbatim: tile.front)
        case .sound:
            soundWord
        }
    }
}

extension CardsWindowState.Tile.Mark {
    /// Its name, in the legend above the grid, and for VoiceOver, a tile's.
    /// Due has a key of its own, since a language can word where a card
    /// stands apart from the detail's Due row, which says when it's due.
    fileprivate var name: Text {
        switch self {
        case .met:
            Text(
                "Met",
                comment: """
                    In the Cards window, above the grid of cards, and for VoiceOver, on a card's tile: the user met \
                    the card, and it isn't due.
                    """)
        case .due:
            Text(
                String(
                    localized: "grid.due", defaultValue: "Due",
                    comment: """
                        In the Cards window, above the grid of cards, and for VoiceOver, on a card's tile: the card \
                        is due.
                        """))
        case .new:
            Text(
                "New: waits its turn",
                comment: """
                    In the Cards window, above the grid of cards, and for VoiceOver, on a card's tile: the user \
                    hasn't met the card yet, which waits its turn in the queue of new cards.
                    """)
        }
    }

    /// The color of a tile's dot, or nil for none, as for a new card.
    fileprivate var dotColor: Color? {
        switch self {
        case .met: .green
        case .due: .orange
        case .new: nil
        }
    }

    /// The color of its dot in the legend, which shows a new card's too.
    fileprivate var legendColor: AnyShapeStyle {
        dotColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary)
    }
}

/// The thumbnails of the grid's tiles, by their images' names, which the
/// tiles make as they appear (`madeThumbnail(of:readingWith:)`), kept in an
/// `NSCache`, which lets go of some once they pass a hundred or 48 MB, a few
/// screens of tiles, and when the Mac runs short of memory, as Apple's
/// documentation of `NSCache` says. An image never changes once it's in,
/// named by its content (`ImageName`), so a thumbnail is never stale. Our
/// own: the cache's limits. A class, so the tiles fill it as they make
/// thumbnails, which changes nothing SwiftUI watches.
@MainActor
private final class TileThumbnails {
    private let cache = NSCache<NSString, CGImage>()

    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// The thumbnail of the image `name`, while the cache keeps it.
    func thumbnail(_ name: ImageName) -> CGImage? {
        cache.object(forKey: name.rawValue as NSString)
    }

    /// Keeps `thumbnail`, of the image `name`, whose pixels take `cost`
    /// bytes.
    func keep(_ thumbnail: CGImage, costing cost: Int, as name: ImageName) {
        cache.setObject(thumbnail, forKey: name.rawValue as NSString, cost: cost)
    }
}

/// The longest side of a tile's thumbnail, in pixels: a tile is narrower than
/// two of the least ones and the room between them, some 234 points, which a
/// Retina display draws with twice the pixels.
private nonisolated let thumbnailLongestSide = 480

/// What making a tile's thumbnail came to.
private nonisolated enum TileThumbnail {
    /// The thumbnail, with what its pixels take, in bytes.
    case made(CGImage, cost: Int)
    /// Not an image, or its file couldn't be read.
    case unreadable
    /// On its way from another device, so the tile shows without it.
    case onItsWay
}

/// The thumbnail of the image `name`, read with `images`, away from the main
/// actor: reading and decoding a photo takes a while, while the window goes
/// on answering. ImageIO makes it no larger than a tile can be, decoding
/// only what it needs, as Apple's "Image and Graphics Best Practices" (WWDC
/// 2018) advises for downsampling.
@concurrent
private func madeThumbnail(
    of name: ImageName, readingWith images: CardsWindowState.TileImages
) async -> sending TileThumbnail {
    switch images.image(name) {
    case .success(let data):
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailLongestSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return .unreadable
        }
        return .made(thumbnail, cost: thumbnail.bytesPerRow * thumbnail.height)
    case .failure:
        return .unreadable
    case nil:
        return .onItsWay
    }
}
