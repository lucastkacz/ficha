import FichaCore
import FichaData
import SwiftUI

/// The sheet the Cards window opens from Rename… in a deck's menu, with one
/// field for its name, which starts with the deck's whole name, its levels
/// joined by `::`, as in "Idiomas::Inglés". OK renames the deck and every
/// deck inside it, which also moves it inside another deck, or to the top, as
/// the name's levels say, and joins it with a deck that already has the name,
/// which keeps what it has of its own; it refuses a blank name, one of
/// Default's names, or one inside the deck itself. The sheet says why under
/// the field. `CardsWindowState` decides what OK takes.
struct RenameSheet: View {
    let deck: Deck
    /// What couldn't be saved, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    /// What OK makes of what the field holds, or nil while the window asks
    /// about no name.
    let entry: (String) -> CardsWindowState.RenameEntry?
    /// OK, with what the field holds.
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var fieldIsFocused: Bool

    init(
        deck: Deck, failure: Binding<Failure?>,
        entry: @escaping (String) -> CardsWindowState.RenameEntry?, choose: @escaping (String) -> Void
    ) {
        self.deck = deck
        self.failure = failure
        self.entry = entry
        self.choose = choose
        _name = State(initialValue: deck.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.headline)
                explanation
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField(
                String(localized: "Name", comment: "The field of the sheet that renames a deck, its whole name."),
                text: $name
            )
            .textFieldStyle(.roundedBorder)
            .focused($fieldIsFocused)
            // A focused text field keeps Return from reaching the default
            // button.
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
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("OK") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(refusal != nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            fieldIsFocused = true
        }
        .failureAlert(failure)
    }

    /// The sheet's title, with the deck's whole name.
    private var title: Text {
        Text(
            "Rename “\(Deck.shownName(deck.name))”",
            comment: "The title of the Cards window's sheet that renames a deck, with the deck's whole name.")
    }

    /// What the sheet says under its title.
    private var explanation: Text {
        Text(
            """
            Write “::” between a deck and a deck inside it, as in “Idiomas::Inglés”. The decks inside this one move \
            with it, and a name another deck has joins the two.
            """,
            comment: "Under the title of the Cards window's sheet that renames a deck.")
    }

    /// Why OK refuses what the field holds, while it does.
    private var refusal: EngineError? {
        guard case .refused(let error)? = entry(name) else { return nil }
        return error
    }

    /// Renames the deck to what the field holds, unless OK refuses it.
    private func submit() {
        guard refusal == nil else { return }
        choose(name)
    }
}
