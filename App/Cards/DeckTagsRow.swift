import FichaCore
import FichaData
import SwiftUI

/// The chosen deck's tags, in the bar above the card list (`DeckBar`): each
/// a button drawn as its capsule, with how many of the deck's cards carry it,
/// the most first, then "+N more", a menu of the tags that don't fit. As
/// many fit as the pane's width holds, up to `mostShown`: the line shows the
/// most tags that fit beside "+N more", as the review panel's line of tags
/// does. A tag chosen narrows the card list to the deck's cards that carry
/// it, outlined while it's chosen, and choosing it again lists them all.
/// `CardsWindowState` decides which tags show for each count that fits, and
/// what choosing one does (`CardsWindowDeckTags.swift`).
struct DeckTagsRow: View {
    @Binding var state: CardsWindowState

    /// The most tags the line shows before "+N more", whatever the pane's
    /// width: the line tries each count from it down, so a deck with
    /// hundreds of tags, as an Anki package can bring, tries a few lines,
    /// not hundreds.
    private static let mostShown = 15

    var body: some View {
        // The first line that fits shows: the most tags, then one fewer and
        // "+N more", down to "+N more" alone.
        ViewThatFits(in: .horizontal) {
            ForEach((0...min(state.deckTags.count, Self.mostShown)).reversed(), id: \.self) { count in
                line(state.deckTagsRow(fitting: count))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A line of the row: its tags, then "+N more" while it lists some.
    private func line(_ row: CardsWindowState.DeckTagsRow) -> some View {
        HStack(spacing: 6) {
            ForEach(row.shown) { tag in
                DeckTagButton(tag: tag, isChosen: tag.id == state.chosenDeckTag) {
                    state.chooseDeckTag(tag.id)
                }
            }
            if !row.more.isEmpty {
                moreTags(row.more)
            }
        }
    }

    /// "+N more", a menu of `tags`, the deck's tags that don't fit, the
    /// chosen one ticked.
    private func moreTags(_ tags: [DeckTag]) -> some View {
        Menu {
            ForEach(tags) { tag in
                Toggle(
                    isOn: Binding(get: { tag.id == state.chosenDeckTag }, set: { _ in state.chooseDeckTag(tag.id) })
                ) {
                    Text(
                        "\(tag.tag.title) (\(tag.cards))",
                        comment: """
                            An item of the “+N more” menu above the Cards window's card list: a tag of the deck the \
                            sidebar chose, with how many of its cards carry it.
                            """)
                }
            }
        } label: {
            Text(
                "+\(tags.count) more",
                comment: """
                    A menu above the Cards window's card list, after the tags of the deck the sidebar chose that fit: \
                    the tags that don't, with how many.
                    """)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// A tag of the chosen deck, as a button drawn as its capsule, with how many
/// of the deck's cards carry it, outlined in its color while it's chosen.
private struct DeckTagButton: View {
    let tag: DeckTag
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 4) {
                Text(verbatim: tag.tag.title)
                Text(tag.cards, format: .number)
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .capsuleLook(tintedWith: tag.tag.shownColor)
            .overlay {
                if isChosen {
                    Capsule().strokeBorder(tag.tag.shownColor?.color ?? .secondary, lineWidth: 1.5)
                }
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .help(help)
    }

    /// What its tooltip says: what choosing it does.
    private var help: Text {
        if isChosen {
            Text(
                "List all of the deck's cards again",
                comment: "The tooltip of a tag above the Cards window's card list, while it narrows the list to it.")
        } else {
            Text(
                "List only the deck's cards tagged \(TagPath.shown(tag.tag.name))",
                comment: """
                    The tooltip of a tag above the Cards window's card list, with its whole name: choosing it \
                    narrows the deck's cards to those that carry it, or a tag inside it.
                    """)
        }
    }
}
