import FichaData
import SwiftUI

/// New Deck…, in a deck's menu and the menu of the sidebar's Your Decks title:
/// it asks for a new deck's name, in the New Deck sheet, and OK makes the
/// deck.
struct NewDeckItem: View {
    @Binding var state: CardsWindowState

    var body: some View {
        Button {
            state.askToMakeDeck()
        } label: {
            Text(
                "New Deck…",
                comment: """
                    An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the grid, and of the menu of the Your Decks title in the sidebar: it asks for a new \
                    deck's name, and OK makes the deck.
                    """)
        }
    }
}

/// Open Deck…, beside New Deck… in a deck's menu and the menu of the
/// sidebar's Your Decks title, on ⌘O, and beside New Card while the user has
/// no cards: it opens an open panel for a deck's `.ficha`, and the deck it
/// holds comes in after How fast? (ADR 0044, `CardsWindowOpenDeck.swift`).
struct OpenDeckItem: View {
    @Binding var state: CardsWindowState

    var body: some View {
        Button {
            state.askToOpenDeck()
        } label: {
            Self.title
        }
    }

    /// Its title, the same wherever it shows.
    static var title: Text {
        Text(
            "Open Deck…",
            comment: """
                An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu above \
                the grid, and of the menu of the Your Decks title in the sidebar, and a button of the window while \
                the user has no cards: it opens an open panel for a deck's .ficha file, and asks how fast new \
                cards come before the deck comes in.
                """)
    }
}

/// The items of a deck's menu, the same in the context menu of its row in
/// the sidebar's Your Decks section and in the Actions menu above the grid
/// while the sidebar chose it, as the state offers them: New Deck…
/// (`NewDeckItem`) and Open Deck… (`OpenDeckItem`), which act on no deck;
/// Set Aside, ticked while the deck is set aside on its own; Prioritize,
/// ticked while it's a priority deck, and off while it's set aside, on its
/// own or inside a deck that is (ADR 0011, ADR 0024); Rename…, which opens
/// the rename sheet on the deck's whole name; Color, with None and Finder's
/// seven colors, each with a swatch, the deck's own ticked; Emoji…, which
/// opens the emoji sheet; Description…, which edits the deck's description
/// in place above its cards (`DeckBar`); Share Deck…, off while the deck holds
/// no card, which opens macOS's Share menu on its `.ficha` (`ShareDeck.swift`);
/// and Delete…, which asks first. Default's has neither Rename… nor
/// Delete…. Each calls the state, which reads the decks as they are when
/// Lucas chooses it.
struct DeckMenuItems: View {
    let menu: CardsWindowState.DeckMenu
    @Binding var state: CardsWindowState

    var body: some View {
        NewDeckItem(state: $state)
        OpenDeckItem(state: $state)
        Divider()
        Toggle(
            isOn: Binding(get: { menu.isSetAsideTicked }, set: { _ in state.chooseSetAside(onDeck: menu.deck.name) })
        ) {
            Text(
                "Set Aside",
                comment: """
                    An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the grid, ticked while the deck is set aside: its cards, and those of the decks \
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
                    above the grid, ticked while the deck is a priority deck, and off while it's set aside.
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
                        above the grid: it asks for the deck's whole name, which moves it too.
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
                    above the grid: the deck's color, which the decks inside it show while they have none.
                    """)
        }
        Button {
            state.askForEmoji(onDeck: menu.deck.name)
        } label: {
            Text(
                "Emoji…",
                comment: """
                    An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the grid: it asks for the deck's emoji.
                    """)
        }
        Button {
            state.askForDescription(onDeck: menu.deck.name)
        } label: {
            Text(
                "Description…",
                comment: """
                    An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the grid: it edits the deck's description, one or two lines on what it holds, in place \
                    above its cards.
                    """)
        }
        Divider()
        Button {
            _ = state.shareDeck(menu.deck.name)
        } label: {
            Text(
                "Share Deck…",
                comment: """
                    An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                    above the grid: it opens macOS's Share menu with the deck's .ficha file, which ends in Save to \
                    File….
                    """)
        }
        .disabled(!menu.canShare)
        if menu.offersRenameAndDelete {
            Divider()
            Button {
                state.askToDeleteDeck(menu.deck.name)
            } label: {
                Text(
                    "Delete…",
                    comment: """
                        An item of a deck's menu in the Cards window, on its row in the sidebar or in the Actions menu \
                        above the grid: it asks whether to delete the deck, with the decks inside it and their \
                        cards.
                        """)
            }
        }
    }
}

/// The bar above the grid while the sidebar chose a deck, Default too:
/// the deck's whole name, after its emoji and its symbol in its color, and
/// the Actions menu, which holds the deck's menu, as its row's context menu
/// in the sidebar does, and under them the deck's description, as the state
/// says it, or the field Description… opens in its place (ADR 0044). Share
/// Deck…'s Share menu opens from the Actions menu. It's the keyboard's way to
/// that menu: the arrow keys
/// choose the deck in the sidebar, Tab goes on to the Actions menu while
/// Keyboard navigation is on in System Settings, and Space opens it.
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
                            A menu button of the Cards window, above the grid while the sidebar chose a deck: \
                            the deck's menu, as on its row in the sidebar.
                            """)
                }
                .fixedSize()
                // Share Deck…'s Share menu opens from the Actions menu.
                .sharingDecks($state)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            if let deck = state.describedDeck, deck.name == menu.deck.name {
                DescriptionField(deck: deck, state: $state)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else if let description = state.chosenDeckDescription {
                TextAsItReads(description)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
        }
        .background(.bar)
    }
}

/// The field Description… opens in place of a deck's description, above its
/// cards, as the desktop mock draws it: one or two lines, starting with the
/// deck's own description, with Cancel, on Escape, and Done, on Return, which
/// gives the deck what the field holds, trimmed, or none when it's blank. A
/// description longer than `Deck.longestDescription` keeps Done off, and the
/// field says why under it. `CardsWindowState` decides what Done takes.
private struct DescriptionField: View {
    let deck: Deck
    @Binding var state: CardsWindowState
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(deck: Deck, state: Binding<CardsWindowState>) {
        self.deck = deck
        _state = state
        _text = State(initialValue: deck.description ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                String(
                    localized: "Description",
                    comment: """
                        The field Description… opens above a deck's cards in the Cards window: its label, and what \
                        it shows while it's empty.
                        """),
                text: $text, axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .alignedAsItReads(text)
            .focused($isFocused)
            .onSubmit(submit)
            if let refusal {
                Text(refusal.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    state.cancelDescription()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    Text(
                        "Done",
                        comment: """
                            The button under the field of a deck's description in the Cards window, which gives the \
                            deck what the field holds.
                            """)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(refusal != nil)
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    /// Why Done refuses what the field holds, while it does.
    private var refusal: EngineError? {
        state.descriptionRefusal(text)
    }

    /// Gives the deck what the field holds, unless Done refuses it.
    private func submit() {
        guard refusal == nil else { return }
        state.chooseDescription(text)
    }
}
