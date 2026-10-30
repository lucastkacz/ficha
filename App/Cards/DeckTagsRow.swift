import FichaCore
import FichaData
import SwiftUI

/// The chosen deck's tags, in the bar above the card list (`DeckBar`): each
/// a button drawn as its capsule, with how many of the deck's cards carry it,
/// the most first, then "+N more", a menu of the tags that don't fit. As
/// many fit as the pane's width holds: the line shows the most tags that fit
/// beside "+N more", as the review panel's line of tags does.
/// `CardsWindowState` offers the lines to try, up to 15 tags, and decides
/// what choosing a tag does (`CardsWindowDeckTags.swift`): it narrows the
/// card list to the deck's cards that carry it, outlined while it's chosen,
/// and choosing it again lists them all.
struct DeckTagsRow: View {
    @Binding var state: CardsWindowState

    var body: some View {
        // The first line that fits shows: the most tags, then one fewer and
        // "+N more", down to "+N more" alone.
        ViewThatFits(in: .horizontal) {
            ForEach(state.deckTagsRows, id: \.shown.count) { row in
                line(row)
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
