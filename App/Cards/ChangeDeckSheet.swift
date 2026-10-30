import FichaCore
import FichaData
import SwiftUI

extension View {
    /// The Change Deck sheet over the view while the window `state` runs asks
    /// which deck the selected cards move to, with `failure` as the alert
    /// over it.
    func changeDeckSheet(_ state: Binding<CardsWindowState>, failure: Binding<Failure?>) -> some View {
        sheet(
            isPresented: Binding(
                get: { state.wrappedValue.deckChange != nil },
                set: { if !$0 { state.wrappedValue.cancelQuestion() } })
        ) {
            ChangeDeckSheet(state: state, failure: failure)
        }
    }
}

/// The sheet Change Deck… opens: the deck tree, Default first, in which Lucas
/// picks the deck the selected cards move to, with the arrow keys or a click,
/// and Move, or Return, moves them there. New Deck…, or ⌘N, asks for a new
/// deck's whole name in the sheet's place, as “Idiomas::Inglés”, and OK, or
/// Return, lists it in the tree, chosen, for Move to make it as it moves the
/// cards; Cancel, or Escape, goes back to the tree. `CardsWindowState` decides what the tree
/// lists and what OK and Move take (`CardsWindowDecks.swift`).
struct ChangeDeckSheet: View {
    @Binding var state: CardsWindowState
    /// What couldn't be saved, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    @Environment(\.dismiss) private var dismiss
    /// What the name field holds, after New Deck….
    @State private var name = ""
    @FocusState private var isTreeFocused: Bool
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.deckChange?.isNamingNewDeck == true {
                naming
            } else {
                choosing
            }
        }
        .padding(20)
        .frame(width: 360)
        .failureAlert(failure)
    }

    /// The deck tree, with New Deck…, Cancel and Move.
    @ViewBuilder
    private var choosing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Change Deck", comment: "The title of the Cards window's sheet that moves cards to another deck.")
                .font(.headline)
            Text(
                "Move \(state.deckChange?.cards.count ?? 0) cards to the deck you choose.",
                comment:
                    "Under the title of the Cards window's sheet that moves cards to another deck, with how many."
            )
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        List(selection: chosenDeck) {
            ForEach(Self.lines(of: state.deckChoices, depth: 0), id: \.row.id) { line in
                Label(line.row.shownTitle, systemImage: CardGroup.deck(line.row.id).symbol)
                    .padding(.leading, CGFloat(line.depth) * 16)
                    .tag(line.row.id)
            }
        }
        .frame(height: 220)
        .focused($isTreeFocused)
        .task {
            isTreeFocused = true
        }
        HStack {
            Button(
                String(
                    localized: "New Deck…",
                    comment: "A button of the Cards window's Change Deck sheet: it asks for a new deck's name."
                )
            ) {
                name = ""
                state.askForNewDeck()
            }
            .keyboardShortcut("n", modifiers: .command)
            .help(
                Text(
                    "New Deck… (⌘N)",
                    comment: "The tooltip of the Change Deck sheet's button that asks for a new deck's name."))
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(
                String(
                    localized: "Move",
                    comment:
                        "The button of the Cards window's Change Deck sheet that moves the cards to the chosen deck."
                )
            ) {
                state.changeDeck()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(state.deckChange?.chosenDeck == nil)
        }
    }

    /// The new deck's name field, with Cancel and OK.
    @ViewBuilder
    private var naming: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New Deck", comment: "The title of the Cards window's Change Deck sheet, after New Deck….")
                .font(.headline)
            Text(
                "Write “::” between a deck and a deck inside it, as in “Idiomas::Inglés”.",
                comment: "Under the title of the Cards window's Change Deck sheet, after New Deck…."
            )
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        TextField(
            String(localized: "Name", comment: "The field of the Cards window's Change Deck sheet: a new deck's name."),
            text: $name
        )
        .textFieldStyle(.roundedBorder)
        .focused($isNameFocused)
        // A focused text field keeps Return from reaching the default button.
        .onSubmit(submitName)
        .task {
            isNameFocused = true
        }
        if case .refused(let error)? = state.newDeckEntry(name) {
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            Button("Cancel") {
                state.cancelNewDeck()
            }
            .keyboardShortcut(.cancelAction)
            Button("OK") {
                submitName()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canChooseName)
        }
    }

    /// The deck the tree has chosen, which choosing another changes.
    private var chosenDeck: Binding<String?> {
        Binding {
            state.deckChange?.chosenDeck
        } set: { deck in
            if let deck {
                state.chooseInDeckChange(deck)
            }
        }
    }

    /// Whether OK takes what the name field holds.
    private var canChooseName: Bool {
        guard case .name? = state.newDeckEntry(name) else { return false }
        return true
    }

    /// Lists the new deck in the tree, chosen, unless OK doesn't take the
    /// name.
    private func submitName() {
        guard canChooseName else { return }
        state.chooseNewDeck(name)
    }

    /// The rows of `rows`, and of the rows inside them, in the order a tree
    /// lists them, each with how deep it sits, from `depth`.
    private static func lines(of rows: [CardsWindowState.DeckRow], depth: Int) -> [DeckLine] {
        rows.flatMap { row in [DeckLine(row: row, depth: depth)] + lines(of: row.children, depth: depth + 1) }
    }
}

/// A row of the Change Deck sheet's tree, with how deep it sits: 0 at the
/// top.
private struct DeckLine {
    let row: CardsWindowState.DeckRow
    let depth: Int
}
