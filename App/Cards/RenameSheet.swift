import FichaCore
import FichaData
import SwiftUI

/// The sheet the Cards window opens from Rename… in a tag's context menu,
/// with one field for the tag's whole name, which starts with the one it has,
/// its levels joined by `::`, as in "economía::Argentina". OK renames the tag
/// and every tag inside it, which also moves it inside another tag, or to the
/// top, as the name's levels say, and joins it with a tag that already has
/// the name. It refuses a blank name, or one inside the tag itself, which the
/// sheet says under the field. `CardsWindowState` decides what OK takes.
struct RenameSheet: View {
    let tag: CardTag
    /// What couldn't be saved, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    /// What OK makes of what the field holds.
    let entry: (String) -> CardsWindowState.RenameEntry
    /// OK, with what the field holds.
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var fieldIsFocused: Bool

    init(
        tag: CardTag, failure: Binding<Failure?>, entry: @escaping (String) -> CardsWindowState.RenameEntry,
        choose: @escaping (String) -> Void
    ) {
        self.tag = tag
        self.failure = failure
        self.entry = entry
        self.choose = choose
        _name = State(initialValue: tag.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Rename “\(TagPath.shown(tag.name))”",
                    comment: "The title of the Cards window's sheet that renames a tag, with the tag's whole name."
                )
                .font(.headline)
                Text(
                    """
                    Write “::” between a tag and a tag inside it, as in “economía::Argentina”. The tags inside this \
                    one move with it, and a name another tag has joins the two.
                    """,
                    comment: "Under the title of the Cards window's sheet that renames a tag."
                )
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField(
                String(localized: "Name", comment: "The field of the sheet that renames a tag: its whole name."),
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

    /// Why OK refuses what the field holds, while it does.
    private var refusal: EngineError? {
        guard case .refused(let error) = entry(name) else { return nil }
        return error
    }

    /// Renames the tag to what the field holds, unless OK refuses it.
    private func submit() {
        guard refusal == nil else { return }
        choose(name)
    }
}
