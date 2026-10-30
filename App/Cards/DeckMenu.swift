import FichaData
import SwiftUI

/// The items of a deck's menu, the same in the context menu of its row in
/// the sidebar's Decks section and in the Actions menu above the card list
/// while the sidebar chose it, as the state offers them: Set Aside, ticked
/// while the deck is set aside on its own; and Prioritize, ticked while it's
/// a priority deck, and off while it's set aside, on its own or inside a deck
/// that is (ADR 0011, ADR 0024). Each calls the state, which reads the decks
/// as they are when Lucas chooses it.
struct DeckMenuItems: View {
    let menu: CardsWindowState.DeckMenu
    @Binding var state: CardsWindowState

    var body: some View {
        Toggle(
            isOn: Binding(get: { menu.isSetAsideTicked }, set: { _ in state.chooseSetAside(onDeck: menu.deck.name) })
        ) {
            Text(
                "Set Aside",
                comment: """
                    An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the card list, ticked while the deck is set aside: its cards, and those of the decks \
                    inside it, are out of Lucas's reviews for now.
                    """)
        }
        Toggle(
            isOn: Binding(get: { menu.isPriorityTicked }, set: { _ in state.choosePriority(onDeck: menu.deck.name) })
        ) {
            Text(
                "Prioritize",
                comment: """
                    An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the card list, ticked while the deck is a priority deck, and off while it's set aside.
                    """)
        }
        .disabled(!menu.canPrioritize)
    }
}

/// The bar above the card list while the sidebar chose a deck, Default too:
/// the deck's whole name, and the Actions menu, which holds the deck's menu,
/// as its row's context menu in the sidebar does. It's the keyboard's way to
/// that menu: the arrow keys choose the deck in the sidebar, Tab goes on to
/// the Actions menu while Keyboard navigation is on in System Settings, and
/// Space opens it.
struct DeckBar: View {
    let menu: CardsWindowState.DeckMenu
    @Binding var state: CardsWindowState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(Deck.shownName(menu.deck.name), systemImage: CardGroup.deck(menu.deck.name).symbol)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // Its whole name, which a narrow pane may cut short.
                    .help(Text(verbatim: Deck.shownName(menu.deck.name)))
                Spacer()
                Menu {
                    DeckMenuItems(menu: menu, state: $state)
                } label: {
                    Text(
                        "Actions",
                        comment: """
                            A menu button of the Cards window, above the card list while the sidebar chose a deck: \
                            the deck's menu, as on its row in the sidebar.
                            """)
                }
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
        }
        .background(.bar)
    }
}
