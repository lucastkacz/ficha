import FichaData
import SwiftUI

/// The items of a deck's menu, the same in the context menu of its row in
/// the sidebar's Decks section and in the Actions menu above the card list
/// while the sidebar chose it, as the state offers them: Set Aside, ticked
/// while the deck is set aside on its own; Prioritize, ticked while it's a
/// priority deck, and off while it's set aside, on its own or inside a deck
/// that is (ADR 0011, ADR 0024); Rename…, which opens the rename sheet on the
/// deck's whole name; Color, with None and Finder's seven colors, each with a
/// swatch, the deck's own ticked; Emoji…, which opens the emoji sheet; and
/// Delete…, which asks first. Default's has neither Rename… nor Delete…. Each
/// calls the state, which reads the decks as they are when Lucas chooses it.
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
        Divider()
        if menu.offersRenameAndDelete {
            Button {
                state.askToRenameDeck(menu.deck.name)
            } label: {
                Text(
                    "Rename…",
                    comment: """
                        An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                        above the card list: it asks for the deck's whole name, which moves it too.
                        """)
            }
        }
        Menu {
            ForEach(menu.colorItems, id: \.color) { item in
                Toggle(
                    isOn: Binding(
                        get: { item.isTicked }, set: { _ in state.chooseColor(item.color, onDeck: menu.deck.name) })
                ) {
                    ColorItemLabel(color: item.color)
                }
            }
        } label: {
            Text(
                "Color",
                comment: """
                    A submenu of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the card list: the deck's color, which the decks inside it show while they have none.
                    """)
        }
        Button {
            state.askForEmoji(onDeck: menu.deck.name)
        } label: {
            Text(
                "Emoji…",
                comment: """
                    An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the card list: it asks for the deck's emoji.
                    """)
        }
        if menu.offersRenameAndDelete {
            Divider()
            Button {
                state.askToDeleteDeck(menu.deck.name)
            } label: {
                Text(
                    "Delete…",
                    comment: """
                        An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                        above the card list: it asks whether to delete the deck, with the decks inside it and their \
                        cards.
                        """)
            }
        }
    }
}

/// The bar above the card list while the sidebar chose a deck, Default too:
/// the deck's whole name, after its emoji and its symbol in its color, and
/// the Actions menu, which holds the deck's menu, as its row's context menu
/// in the sidebar does; and under them, while its cards carry tags, the
/// deck's tags (`DeckTagsRow`). It's the keyboard's way to that menu and to
/// those tags: the arrow keys choose the deck in the sidebar, Tab goes on to
/// the Actions menu and to each tag while Keyboard navigation is on in
/// System Settings, and Space opens the menu or chooses the tag.
struct DeckBar: View {
    let menu: CardsWindowState.DeckMenu
    @Binding var state: CardsWindowState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label {
                    Text(verbatim: menu.deck.title)
                } icon: {
                    menu.deck.symbol
                }
                .lineLimit(1)
                .truncationMode(.middle)
                // Its whole name, which a narrow pane may cut short.
                .help(Text(verbatim: menu.deck.title))
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
            if !state.deckTags.isEmpty {
                DeckTagsRow(state: $state)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            Divider()
        }
        .background(.bar)
    }
}
