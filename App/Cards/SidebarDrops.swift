import FichaData
import SwiftUI
import UniformTypeIdentifiers

// Dragging in the Cards window onto its sidebar's decks (ADR 0024): cards
// from the card list, which move to the deck they're dropped on, as Change
// Deck moves them, and a deck's row, which goes inside the deck it's dropped
// on, or to the top on the Decks section's title. `CardsWindowState` decides
// which drops it takes (`CardsWindowDeckEdits.swift`); this file carries
// what's dragged and draws where it lands. Tags are dragged in All Tags
// alone, as text, with an outline of their own (`AllTagsOutline.swift`).

/// What Lucas drags onto the sidebar's decks: a card of the card list, each
/// of the selected ones when he drags one of them, or a deck's row. It stays
/// within Ficha, under a type of its own, so no other app takes it, and the
/// sidebar's pinned tags, which take text, don't either.
nonisolated enum SidebarDrag: Codable, Sendable, Transferable {
    case card(CardRow.ID)
    case deck(String)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .sidebarDrag)
            .visibility(.ownProcess)
    }
}

extension UTType {
    /// The type of what Lucas drags onto the sidebar's decks, the app's own,
    /// as its Info.plist exports it, under the bundle's identifier, so Ficha
    /// and Ficha Dev each have theirs.
    nonisolated static let sidebarDrag = UTType(
        exportedAs: "\(Bundle.main.bundleIdentifier ?? "com.lucastkacz.ficha").sidebar-drag")
}

/// Where Lucas drops cards or a deck in the sidebar, a deck's row or the
/// Decks section's title, as wide as the list, highlighted while he holds
/// them over it. `drop` takes the cards, or the deck, and says whether it
/// took them: when it doesn't, they go back where they came from.
private struct SidebarDropTarget: ViewModifier {
    let drop: (_ cards: [CardRow.ID], _ deck: String?) -> Bool
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background(
                isTargeted ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 4)
            )
            .dropDestination(for: SidebarDrag.self) { items, _ in
                var cards: [CardRow.ID] = []
                var decks: [String] = []
                for item in items {
                    switch item {
                    case .card(let id): cards.append(id)
                    case .deck(let name): decks.append(name)
                    }
                }
                // One deck's row, or cards, never both: a drag holds one kind.
                guard decks.count <= 1, decks.isEmpty || cards.isEmpty else { return false }
                return drop(cards, decks.first)
            } isTargeted: {
                isTargeted = $0
            }
    }
}

extension View {
    /// The view as a place in the sidebar where Lucas drops cards or a deck,
    /// highlighted while he holds them over it, which `drop` takes, saying
    /// whether it took them.
    func takingSidebarDrops(_ drop: @escaping (_ cards: [CardRow.ID], _ deck: String?) -> Bool) -> some View {
        modifier(SidebarDropTarget(drop: drop))
    }

    /// The view, which Lucas drags as the deck `deck`, onto another deck's
    /// row or the Decks section's title; or as it is, when `deck` is nil, as
    /// for Default, which stays where it is.
    @ViewBuilder
    func draggingDeck(_ deck: String?) -> some View {
        if let deck {
            draggable(SidebarDrag.deck(deck))
        } else {
            self
        }
    }
}
