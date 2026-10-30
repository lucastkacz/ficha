import FichaData
import SwiftUI
import UniformTypeIdentifiers

// Dragging in the Cards window onto its sidebar's decks (ADR 0024): cards
// from the card list, which move to the deck they're dropped on, as Change
// Deck moves them, and a deck's row, which goes inside the deck it's dropped
// on, or to the top on the Decks section's title. `CardsWindowState` decides
// which drops it takes (`CardsWindowDeckEdits.swift`); this file carries
// what's dragged, hands what's dropped to it as it came, and draws where it
// lands. Tags are dragged in All Tags alone, as text, with an outline of
// their own (`AllTagsOutline.swift`).

/// What Lucas drags onto the sidebar's decks, as the window's state names
/// it: a card of the card list, each of the selected ones when he drags one
/// of them, or a deck's row. It stays within Ficha, under a type of its own,
/// so no other app takes it, and the sidebar's pinned tags, which take text,
/// don't either.
nonisolated struct SidebarDrag: Codable, Sendable, Transferable {
    let dragged: CardsWindowState.Dragged

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .sidebarDrag)
            .visibility(.ownProcess)
    }
}

extension UTType {
    /// The type of what Lucas drags onto the sidebar's decks, the app's own,
    /// as its Info.plist exports it, under the app's bundle identifier, so
    /// Ficha and Ficha Dev each have theirs.
    nonisolated static let sidebarDrag = UTType(exportedAs: AppVariant.current.sidebarDragIdentifier)
}

/// Where Lucas drops cards or a deck in the sidebar, a deck's row or the
/// Decks section's title, as wide as the list, highlighted while he holds
/// them over it. `drop` takes what's dropped, and says whether it took it:
/// when it doesn't, it goes back where it came from.
private struct SidebarDropTarget: ViewModifier {
    let drop: ([CardsWindowState.Dragged]) -> Bool
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background(
                isTargeted ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 4)
            )
            .dropDestination(for: SidebarDrag.self) { items, _ in
                drop(items.map(\.dragged))
            } isTargeted: {
                isTargeted = $0
            }
    }
}

extension View {
    /// The view as a place in the sidebar where Lucas drops cards or a deck,
    /// highlighted while he holds them over it, which `drop` takes, saying
    /// whether it took them.
    func takingSidebarDrops(_ drop: @escaping ([CardsWindowState.Dragged]) -> Bool) -> some View {
        modifier(SidebarDropTarget(drop: drop))
    }

    /// The view, which Lucas drags as `dragged`, a card onto a deck's row, or
    /// a deck onto another's row or the Decks section's title; or as it is,
    /// when `dragged` is nil, as for Default, which stays where it is.
    @ViewBuilder
    func dragging(_ dragged: CardsWindowState.Dragged?) -> some View {
        if let dragged {
            draggable(SidebarDrag(dragged: dragged))
        } else {
            self
        }
    }
}
