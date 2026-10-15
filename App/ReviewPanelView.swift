import FichaCore
import FichaData
import SwiftUI

/// What the review panel shows, on Liquid Glass: the cards a review now
/// brought, one at a time. Every action has a key and a button: Enter ends a
/// first view, Space flips a card, 1, 2 and 3 rate it, and Esc closes the
/// panel. Once Lucas answered every card, the panel closes on its own.
struct ReviewPanelView: View {
    /// The cards a review now brought, or why it couldn't bring them.
    let model: Result<ReviewPanelModel, EngineError>
    /// Closes the panel.
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model {
            case .success(let panel):
                content(of: panel)
                    .onChange(of: panel.isDone) { _, isDone in
                        if isDone {
                            close()
                        }
                    }
                    .failureAlert("Couldn't save your answer", failure: Bindable(panel).failure)
            case .failure(let failure):
                header {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't load the cards")
                            .font(.headline)
                        Text(failure.localizedDescription)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private func content(of panel: ReviewPanelModel) -> some View {
        switch panel.content {
        case .nothingToReview:
            header {
                Text("No cards to review right now.")
                    .font(.headline)
            }
        case .firstView(let card):
            header {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New", comment: "A badge on a card the review panel shows for the first time.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: .capsule)
                    front(of: card)
                }
            }
            back(of: card)
            HStack {
                Spacer()
                Button(action: panel.endFirstView) {
                    KeyLabel(title: "Got it", key: "↩")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        case .front(let card):
            header {
                front(of: card)
            }
            HStack {
                Spacer()
                Button(action: panel.flip) {
                    KeyLabel(
                        title: "Flip",
                        key: String(localized: "space", comment: "The Space key's name, next to the button it presses.")
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
            }
        case .back(let card):
            header {
                front(of: card)
            }
            back(of: card)
            HStack {
                ratingButton("Don't know", key: "1", rating: .again, in: panel)
                ratingButton("Sort of", key: "2", rating: .hard, in: panel)
                ratingButton("Know it", key: "3", rating: .good, in: panel)
            }
        case .done:
            // The panel closes.
            EmptyView()
        }
    }

    /// The panel's first line, next to the button that closes it.
    private func header(@ViewBuilder _ title: () -> some View) -> some View {
        HStack(alignment: .top) {
            title()
            Spacer(minLength: 12)
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close (esc)")
        }
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
            KeyLabel(title: title, key: String(key))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
    }
}

/// A button's title, followed by the key that does the same, small. The key
/// shows as it's given: a symbol, a digit, or the Space key's name, which the
/// caller translates.
private struct KeyLabel: View {
    let title: LocalizedStringKey
    let key: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
