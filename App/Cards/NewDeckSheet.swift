import FichaCore
import FichaData
import SwiftUI

extension View {
    /// The New Deck sheet over the view while the window `state` runs asks
    /// for a new deck's name for the Deck field of `fields`, the card form
    /// or the editor.
    func newDeckSheet(for fields: CardsWindowState.CardFields, _ state: Binding<CardsWindowState>) -> some View {
        sheet(
            isPresented: Binding(
                get: { state.wrappedValue.question == .newDeck(fields) },
                set: { if !$0 { state.wrappedValue.cancelQuestion() } })
        ) {
            NewDeckName { name in
                state.wrappedValue.newDeckEntry(name)
            } choose: { name in
                state.wrappedValue.chooseNewDeck(name)
            } cancel: {
                state.wrappedValue.cancelQuestion()
            }
            .padding(20)
            .frame(width: 360)
        }
    }
}

/// A new deck's whole name, after New Deck…, as “Idiomas::Inglés”: in the
/// New Deck sheet a card's Deck field opens, in the card form or the editor,
/// where OK puts the deck in the field, for Add or Save to make it, and in
/// the Change Deck sheet, in its tree's place, where OK lists the deck there,
/// chosen, for Move to make it. Return chooses OK, and Escape Cancel. OK
/// stays off while the name is blank, and refuses one whose top level is
/// Default's, which it says under the field. `CardsWindowState` decides what
/// OK takes (`CardsWindowDecks.swift`).
struct NewDeckName: View {
    /// What OK makes of what the name field holds, or nil while the window
    /// asks for no new deck's name.
    let entry: (_ name: String) -> CardsWindowState.NewDeckEntry?
    /// OK, with what the name field holds.
    let choose: (_ name: String) -> Void
    /// Cancel.
    let cancel: () -> Void
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "New Deck", comment: "The title of the Cards window's sheet that names a new deck, after New Deck…."
                )
                .font(.headline)
                Text(
                    "Write “::” between a deck and a deck inside it, as in “Idiomas::Inglés”.",
                    comment: "Under the title of the Cards window's sheet that names a new deck, after New Deck…."
                )
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField(
                String(localized: "Name", comment: "The field of the Cards window's sheet that names a new deck."),
                text: $name
            )
            .textFieldStyle(.roundedBorder)
            .focused($isNameFocused)
            // A focused text field keeps Return from reaching the default
            // button.
            .onSubmit(submit)
            // Once the view is up, after the update that showed it, as the
            // New Type sheet's field takes it.
            .task {
                isNameFocused = true
            }
            if case .refused(let error)? = entry(name) {
                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canChoose)
            }
        }
    }

    /// Whether OK takes what the name field holds.
    private var canChoose: Bool {
        guard case .name? = entry(name) else { return false }
        return true
    }

    /// Chooses the name, unless OK doesn't take it.
    private func submit() {
        guard canChoose else { return }
        choose(name)
    }
}
