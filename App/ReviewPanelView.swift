import FichaCore
import FichaData
import SwiftUI

/// What the review panel shows, on Liquid Glass: the cards a review now or an
/// appearance brought, one at a time. Every action has a key and a button:
/// Enter ends a first view, Space flips a card, 1, 2 and 3 rate it, M flags it
/// with a note, E buries it, ⌘Z undoes what Lucas did with the last card, and
/// Esc closes the panel, which snoozes an appearance. Once Lucas went through
/// every card, the panel closes on its own.
struct ReviewPanelView: View {
    /// The cards a review now or an appearance brought, or why review now
    /// couldn't bring them.
    let model: Result<ReviewPanelModel, EngineError>
    /// Closes the panel's window.
    let closeWindow: () -> Void
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model {
            case .success(let panel):
                content(of: panel)
                    .onChange(of: panel.isClosed) { _, isClosed in
                        if isClosed {
                            closeWindow()
                        }
                    }
                    .failureAlert(Bindable(panel).failure)
            case .failure(let failure):
                header {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't load the cards")
                            .font(.headline)
                        Text(failure.localizedDescription)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } buttons: {
                    closeButton(closeWindow)
                }
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private func content(of panel: ReviewPanelModel) -> some View {
        let closeByLucas = { panel.close(.byLucas) }
        switch panel.content {
        case .nothingToReview:
            header {
                Text("No cards to review right now.")
                    .font(.headline)
            } buttons: {
                closeButton(closeByLucas)
            }
        case .firstView(let card):
            header {
                VStack(alignment: .leading, spacing: 8) {
                    newBadge
                    front(of: card)
                }
            } buttons: {
                cardButtons(of: panel)
                closeButton(closeByLucas)
            }
            back(of: card)
            HStack {
                Spacer()
                Button(action: panel.endFirstView) {
                    KeyLabel(title: Text("Got it"), key: "↩")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        case .front(let card):
            header {
                front(of: card)
            } buttons: {
                cardButtons(of: panel)
                closeButton(closeByLucas)
            }
            HStack {
                Spacer()
                Button(action: panel.flip) {
                    KeyLabel(
                        title: Text("Flip"),
                        key: String(localized: "space", comment: "The Space key's name, next to the button it presses.")
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
            }
        case .back(let card):
            header {
                front(of: card)
            } buttons: {
                cardButtons(of: panel)
                closeButton(closeByLucas)
            }
            back(of: card)
            HStack {
                ratingButton("Don't know", key: "1", rating: .again, in: panel)
                ratingButton("Sort of", key: "2", rating: .hard, in: panel)
                ratingButton("Know it", key: "3", rating: .good, in: panel)
            }
        case .flagging(let card, let showsBack):
            // Esc goes back to the card here, so the close button doesn't
            // take it.
            header {
                front(of: card)
            } buttons: {
                closeButton(closeByLucas, withEsc: false)
            }
            if showsBack {
                back(of: card)
            }
            noteEditor(of: panel)
        case .done:
            // The panel closes.
            EmptyView()
        }
    }

    /// The panel's first line, and the buttons at its end.
    private func header(@ViewBuilder _ title: () -> some View, @ViewBuilder buttons: () -> some View) -> some View {
        HStack(alignment: .top) {
            title()
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                buttons()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    /// The button that closes the panel with `close`, and with Esc unless the
    /// panel takes Esc for something else.
    private func closeButton(_ close: @escaping () -> Void, withEsc: Bool = true) -> some View {
        Button("Close", systemImage: "xmark", action: close)
            .keyboardShortcut(withEsc ? .cancelAction : nil)
            .help(withEsc ? Text("Close (esc)") : Text("Close"))
    }

    /// The buttons for the card Lucas is on: ⌘Z undoes what he did with the
    /// last card, M flags this one with a note, and E buries it.
    @ViewBuilder
    private func cardButtons(of panel: ReviewPanelModel) -> some View {
        Button("Undo", systemImage: "arrow.uturn.backward", action: panel.undo)
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!panel.canUndo)
            .help("Undo (⌘Z)")
        Button(
            String(
                localized: "Flag…",
                comment: "A button that flags the card the review panel shows, asking for a note on what to fix."),
            systemImage: "flag", action: panel.startFlagging
        )
        .keyboardShortcut("m", modifiers: [])
        .help(Text("Flag… (m)", comment: "The tooltip of the button that flags the card, with its key."))
        Button(
            String(
                localized: "Bury",
                comment: "A button that buries the card the review panel shows: it never shows up again."),
            systemImage: "eye.slash", action: panel.bury
        )
        .keyboardShortcut("e", modifiers: [])
        .help(Text("Bury (e)", comment: "The tooltip of the button that buries the card, with its key."))
    }

    /// Where Lucas writes what to fix in the card he flags: Enter flags it,
    /// Option-Enter starts a new line, and Esc goes back to the card.
    private func noteEditor(of panel: ReviewPanelModel) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            TextField(
                "Note",
                text: Binding(get: { panel.note ?? "" }, set: { panel.write(note: $0) }),
                prompt: Text("What needs fixing?"),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .focused($noteIsFocused)
            // A focused text field keeps Return from reaching the default
            // button.
            .onSubmit(panel.flag)
            HStack {
                Button(action: panel.cancelFlagging) {
                    KeyLabel(
                        title: Text("Cancel"),
                        key: String(localized: "esc", comment: "The Esc key's name, next to the button it presses.")
                    )
                }
                .keyboardShortcut(.cancelAction)
                Button(action: panel.flag) {
                    KeyLabel(
                        title: Text("Flag", comment: "The button that flags the card with the note written above it."),
                        key: "↩")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!panel.noteSaysWhatToFix)
            }
        }
        .onAppear {
            noteIsFocused = true
        }
    }

    private var newBadge: some View {
        Text("New", comment: "A badge on a card the review panel shows for the first time.")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: .capsule)
    }

    private func front(of card: Card) -> some View {
        Text(card.front)
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The card's back, and its source, small, when it has one.
    private func back(of card: Card) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(card.back)
                .fixedSize(horizontal: false, vertical: true)
            if let source = card.source {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ratingButton(
        _ title: LocalizedStringKey, key: Character, rating: Rating, in panel: ReviewPanelModel
    ) -> some View {
        Button {
            panel.rate(rating)
        } label: {
            KeyLabel(title: Text(title), key: String(key))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
    }
}

/// A button's title, followed by the key that does the same, small. The key
/// shows as it's given: a symbol, a digit, or a key's name, like Space's,
/// which the caller translates.
private struct KeyLabel: View {
    let title: Text
    let key: String

    var body: some View {
        HStack(spacing: 6) {
            title
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
