import FichaCore
import FichaData
import SwiftUI

/// What the review panel shows, on Liquid Glass: the cards a review now or an
/// appearance brought, one at a time. Every action has a key and a button:
/// Enter ends a first view, Space flips a card, 1, 2 and 3 rate it, M flags it
/// with a note, E buries it, ⌘Z undoes what Lucas did with the last card, and
/// Esc closes the panel, which snoozes an appearance. Once Lucas went through
/// every card, the panel stays open until he closes it, and offers more cards
/// if there are any, which Enter brings; review now with nothing due offers
/// to review ahead the same way. A card taller than the panel's maximum
/// height scrolls between the line at its top and what's under it, which
/// stay in view. `ReviewPanelState` decides what the panel shows and what
/// happens when Lucas acts, and the view draws it.
struct ReviewPanelView: View {
    /// The corner radius of the panel's glass, with continuous corners. The
    /// panel's window clips its content to it, which matches the glass while
    /// the glass is the view's outermost modifier.
    static let cornerRadius: CGFloat = 24

    /// The cards a review now or an appearance brought, or why review now
    /// couldn't bring them.
    let model: Result<ReviewPanelModel, EngineError>
    /// Closes the panel's window.
    let closeWindow: () -> Void
    /// The tallest the panel grows, which its window sets by the screen it
    /// shows on: a card taller than that scrolls.
    var maximumHeight = CGFloat.infinity
    /// The tallest a side's image shows: a third of the panel's tallest, so a
    /// card with an image on each side and a line or two of text on each fits
    /// without scrolling, and never more than 280 pt.
    private var imageHeight: CGFloat { min(280, maximumHeight / 3) }
    /// Whether the note's field has the keyboard. Whatever shows the note
    /// sets it, in the same action, as the flag button does.
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        HeightUpTo(maximum: maximumHeight) {
            VStack(alignment: .leading, spacing: 16) {
                switch model {
                case .success(let panel):
                    content(of: panel)
                        .onChange(of: panel.state.outcome != nil) { _, isClosed in
                            if isClosed {
                                closeWindow()
                            }
                        }
                        .failureAlert(failure(of: panel))
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
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    /// What Lucas did in the panel that couldn't be saved, as an alert says
    /// it, which closing it clears.
    private func failure(of panel: ReviewPanelModel) -> Binding<Failure?> {
        Binding {
            panel.state.failure.map(alert(for:))
        } set: {
            if $0 == nil {
                panel.state.dismissFailure()
            }
        }
    }

    /// What the alert says when `failure` happened: what Lucas did that
    /// couldn't be saved, and why, in the panel's words.
    private func alert(for failure: ReviewPanelState.Failure) -> Failure {
        let error = failure.error
        return switch failure.action {
        case .answer: Failure(title: "Couldn't save your answer", message: error.messageInReviewPanel)
        case .flag: Failure(title: "Couldn't flag the card", message: error.messageInReviewPanel)
        case .bury: Failure(title: "Couldn't bury the card", message: error.messageInReviewPanel)
        case .undo: Failure(title: "Couldn't undo", message: error.messageInReviewPanel)
        case .lookForMore: Failure(title: "Couldn't look for more cards", error: error)
        }
    }

    @ViewBuilder
    private func content(of panel: ReviewPanelModel) -> some View {
        let closeByLucas = { panel.state.close(.byLucas) }
        switch panel.state.content {
        case .nothingToReview where panel.state.canSeeMore:
            header {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No cards are due right now.")
                        .font(.headline)
                    aheadExplanation
                }
            } buttons: {
                closeButton(closeByLucas)
            }
            enterButton(
                Text(
                    "Review ahead", comment: "A button that brings the cards closest to being due, to review them now.")
            ) {
                panel.state.seeMore()
            }
        case .nothingToReview:
            header {
                Text("No cards to review right now.")
                    .font(.headline)
            } buttons: {
                closeButton(closeByLucas)
            }
        case .firstView(let card):
            sides(of: card, showingBack: true, buttons: .forTheCard, in: panel) {
                TagLine(tags: panel.state.tags) {
                    newBadge
                }
            }
            enterButton(Text("Got it")) {
                panel.state.endFirstView()
            }
        case .front(let card, let isAhead):
            sides(of: card, showingBack: false, buttons: .forTheCard, in: panel) {
                topLine(isAhead: isAhead, tags: panel.state.tags)
            }
            HStack {
                Spacer()
                Button {
                    panel.state.flip()
                } label: {
                    KeyLabel(
                        title: Text("Flip"),
                        key: String(localized: "space", comment: "The Space key's name, next to the button it presses.")
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
            }
        case .back(let card, let isAhead):
            sides(of: card, showingBack: true, buttons: .forTheCard, in: panel) {
                topLine(isAhead: isAhead, tags: panel.state.tags)
            }
            HStack {
                ratingButton("Don't know", key: "1", rating: .again, in: panel)
                ratingButton("Sort of", key: "2", rating: .hard, in: panel)
                ratingButton("Know it", key: "3", rating: .good, in: panel)
            }
        case .flagging(let card, let showsBack):
            sides(of: card, showingBack: showsBack, buttons: .closeWithoutEsc, in: panel) {}
            noteEditor(of: panel)
        case .done where panel.state.canSeeMore:
            header {
                VStack(alignment: .leading, spacing: 6) {
                    Text("See more?")
                        .font(.headline)
                    Text(
                        "You went through every card. More can come: the ones that didn't fit, then the closest to being due."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } buttons: {
                undoButton(of: panel)
                closeButton(closeByLucas)
            }
            enterButton(Text("See more")) {
                panel.state.seeMore()
            }
        case .done:
            header {
                Text("You went through every card.")
                    .font(.headline)
            } buttons: {
                undoButton(of: panel)
                closeButton(closeByLucas)
            }
            enterButton(
                Text("Done", comment: "A button that closes the review panel once every card was gone through."),
                action: closeByLucas)
        }
    }

    /// The panel's main button, at its bottom right, which Enter presses.
    private func enterButton(_ title: Text, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(action: action) {
                KeyLabel(title: title, key: "↩")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    /// What a review ahead does, under the offer to review ahead.
    private var aheadExplanation: some View {
        Text("A review ahead brings the cards closest to being due. Only “Don't know” moves them.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The panel's first line, and the buttons at its end.
    private func header(@ViewBuilder _ title: () -> some View, @ViewBuilder buttons: () -> some View) -> some View {
        HStack(alignment: .top) {
            title()
            Spacer(minLength: 12)
            iconButtons(buttons)
        }
    }

    /// Buttons in a row at the end of the panel's first line, as icons.
    private func iconButtons(@ViewBuilder _ buttons: () -> some View) -> some View {
        HStack(spacing: 2) {
            buttons()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    /// A card's sides, under the line at its top and beside the buttons at
    /// the panel's top right: its front, and its back when it shows. The
    /// panel's window stops at its share of the screen (`ReviewPanelWindow`).
    /// A card that doesn't fit has its front go under the line at its top,
    /// the panel's width, and when it still doesn't fit, its front and its
    /// back scroll, each card from its top, while the line at its top and the
    /// buttons stay in view, as what's under the card does. The scroll never
    /// takes the keyboard, so the panel's keys work as on a short card. The
    /// buttons show once, over the room each layout keeps for them, so no key
    /// belongs to two buttons.
    private func sides<TopLine: View>(
        of card: Card, showingBack: Bool, buttons: TopButtons, in panel: ReviewPanelModel,
        @ViewBuilder topLine: () -> TopLine
    ) -> some View {
        let line = topLine()
        let room = topButtons(buttons, of: panel, withKeys: false).hidden()
        let frontAndBack = VStack(alignment: .leading, spacing: 16) {
            front(of: card, in: panel)
            if showingBack {
                back(of: card, in: panel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        return ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 16) {
                header {
                    VStack(alignment: .leading, spacing: 8) {
                        line
                        front(of: card, in: panel)
                    }
                } buttons: {
                    room
                }
                if showingBack {
                    back(of: card, in: panel)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                header {
                    line
                } buttons: {
                    room
                }
                frontAndBack
            }
            VStack(alignment: .leading, spacing: 8) {
                header {
                    line
                } buttons: {
                    room
                }
                ScrollView {
                    frontAndBack
                        // The scroller sits in the panel's margin, beside the
                        // text rather than over it.
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
                .id(card.id)
            }
        }
        .overlay(alignment: .topTrailing) {
            iconButtons {
                topButtons(buttons, of: panel, withKeys: true)
            }
        }
    }

    /// Which buttons a card has at the panel's top right.
    private enum TopButtons {
        /// Undo, flag, bury, and close, with Esc.
        case forTheCard
        /// Close alone, without Esc, which goes back to the card while the user
        /// writes a note to flag it.
        case closeWithoutEsc
    }

    /// The buttons at a card's top right, with their keys, or, `withKeys`
    /// false, a copy without them that only keeps their room.
    @ViewBuilder
    private func topButtons(_ buttons: TopButtons, of panel: ReviewPanelModel, withKeys: Bool) -> some View {
        let closeByLucas = { panel.state.close(.byLucas) }
        switch buttons {
        case .forTheCard:
            cardButtons(of: panel, withKeys: withKeys)
            closeButton(closeByLucas, withEsc: withKeys)
        case .closeWithoutEsc:
            closeButton(closeByLucas, withEsc: false)
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
    /// last card, M flags this one with a note, and E buries it. Without
    /// `withKeys`, none of them has its key.
    @ViewBuilder
    private func cardButtons(of panel: ReviewPanelModel, withKeys: Bool) -> some View {
        undoButton(of: panel, withKeys: withKeys)
        Button(
            String(
                localized: "Flag…",
                comment: "A button that flags the card the review panel shows, asking for a note on what to fix."),
            systemImage: "flag"
        ) {
            panel.state.startFlagging()
            // The note's field gets the keyboard in the same action that
            // shows it. Asked from the field's `onAppear` instead, after M,
            // SwiftUI never focused it while the panel had the keyboard (#61).
            noteIsFocused = true
        }
        .keyboardShortcut(withKeys ? KeyboardShortcut("m", modifiers: []) : nil)
        .help(Text("Flag… (m)", comment: "The tooltip of the button that flags the card, with its key."))
        Button(
            String(
                localized: "Bury",
                comment: "A button that buries the card the review panel shows: it never shows up again."),
            systemImage: "eye.slash"
        ) {
            panel.state.buryCard()
        }
        .keyboardShortcut(withKeys ? KeyboardShortcut("e", modifiers: []) : nil)
        .help(Text("Bury (e)", comment: "The tooltip of the button that buries the card, with its key."))
    }

    /// The button that undoes what the user did with the last card: ⌘Z, unless
    /// `withKeys` is false.
    private func undoButton(of panel: ReviewPanelModel, withKeys: Bool = true) -> some View {
        Button("Undo", systemImage: "arrow.uturn.backward") {
            panel.state.undoLastCard()
        }
        .keyboardShortcut(withKeys ? KeyboardShortcut("z", modifiers: .command) : nil)
        .disabled(!panel.state.canUndo)
        .help("Undo (⌘Z)")
    }

    /// Where Lucas writes what to fix in the card he flags: Enter flags it,
    /// Option-Enter starts a new line, and Esc goes back to the card.
    private func noteEditor(of panel: ReviewPanelModel) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            TextField(
                "Note",
                text: Binding(get: { panel.state.note ?? "" }, set: { panel.state.write(note: $0) }),
                prompt: Text("What needs fixing?"),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .focused($noteIsFocused)
            // A focused text field keeps Return from reaching the default
            // button.
            .onSubmit {
                panel.state.finishFlagging()
            }
            HStack {
                Button {
                    panel.state.cancelFlagging()
                } label: {
                    KeyLabel(
                        title: Text("Cancel"),
                        key: String(localized: "esc", comment: "The Esc key's name, next to the button it presses.")
                    )
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    panel.state.finishFlagging()
                } label: {
                    KeyLabel(
                        title: Text("Flag", comment: "The button that flags the card with the note written above it."),
                        key: "↩")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!panel.state.noteSaysWhatToFix)
            }
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

    /// The line at the top of a card the user reviews: the badge of a review
    /// ahead, when it's one, and the card's tags, when it has some.
    @ViewBuilder
    private func topLine(isAhead: Bool, tags: [CardTag]) -> some View {
        if isAhead || !tags.isEmpty {
            TagLine(tags: tags) {
                if isAhead {
                    AheadBadge()
                }
            }
        }
    }

    /// The card's front: its image, fitted to the panel's width, above its
    /// text, each when it has one.
    private func front(of card: Card, in panel: ReviewPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = card.frontImage {
                SideImage(image: panel.state.images[image], maximumHeight: imageHeight)
            }
            if !card.front.isEmpty {
                Text(card.front)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The card's back: its image, fitted to the panel's width, above its
    /// text, each when it has one, and its source, small, when it has one.
    private func back(of card: Card, in panel: ReviewPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let image = card.backImage {
                SideImage(image: panel.state.images[image], maximumHeight: imageHeight)
            }
            if !card.back.isEmpty {
                Text(card.back)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            panel.state.rate(rating)
        } label: {
            KeyLabel(title: Text(title), key: String(key))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
    }
}

/// The badge of a review ahead, on the card the review panel brings before
/// it's due and beside the review in the Cards window's review log, with a
/// tooltip on what a review ahead moves.
struct AheadBadge: View {
    var body: some View {
        Text(
            "Ahead",
            comment:
                "A badge on a card the review panel brings before it's due, in a review ahead, and beside such a review in the Cards window's review log."
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.secondary.opacity(0.15), in: .capsule)
        .help(Text("A review ahead: only “Don't know” moves the card."))
    }
}

/// The line at the top of a card in the review panel: its badge, "New" or
/// "Ahead", when it has one, and then its tags, each as the Cards window's
/// Tags column draws it, so that Lucas knows which subject the card is about
/// before he answers it. It's one line, so the panel stays as small as it is:
/// the tags that don't fit collapse into a "+n" capsule, whose tooltip names
/// them.
private struct TagLine<Badge: View>: View {
    let tags: [CardTag]
    @ViewBuilder let badge: Badge

    var body: some View {
        // The first line that fits shows: every tag, then one fewer and
        // "+1", down to none and "+n".
        ViewThatFits(in: .horizontal) {
            ForEach((0...tags.count).reversed(), id: \.self) { shown in
                HStack(spacing: 4) {
                    badge
                    ForEach(tags.prefix(shown), id: \.name) { tag in
                        TagCapsule(tag: tag)
                    }
                    if shown < tags.count {
                        MoreTagsCapsule(tags: Array(tags.dropFirst(shown)))
                    }
                }
            }
        }
    }
}

/// The tags that don't fit on a card's line in the review panel, as one
/// capsule that counts them, gray like a tag without a color, and whose
/// tooltip names them, one per line, each as its capsule names it.
private struct MoreTagsCapsule: View {
    let tags: [CardTag]

    var body: some View {
        Text(
            "+\(tags.count)",
            comment:
                "A capsule on the review panel's card, after the tags that fit on its line, counting those that don't. Its tooltip names them."
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.secondary.opacity(0.15), in: .capsule)
        .fixedSize()
        .help(Text(verbatim: tags.map(\.title).joined(separator: "\n")))
    }
}

/// The review panel's content at its ideal height, or, when that's more than
/// `maximum`, as the content lays itself out in `maximum`, whatever height
/// it's offered: the panel's window takes the view's smallest and largest
/// size as its own, which this makes the same, so the window fits the content
/// as it changes. In `maximum`, a card taller than that scrolls, and one that
/// fits in less, once its front moves under the line at its top, takes less.
/// SwiftUI's `Layout` is standard; this one is ours.
private struct HeightUpTo: Layout {
    let maximum: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else {
            return .zero
        }
        let ideal = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        guard ideal.height > maximum else {
            return ideal
        }
        return content.sizeThatFits(ProposedViewSize(width: proposal.width, height: maximum))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
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

extension EngineError {
    /// Why what Lucas did with a card in the review panel couldn't be saved,
    /// as its alert says it. A card that isn't found was deleted in the Cards
    /// window while the panel showed it: the engine's message for it names
    /// the card by its id, which the panel doesn't show, and says to check
    /// the id, as the CLI needs.
    fileprivate var messageInReviewPanel: String {
        switch self {
        case .cardNotFound:
            String(
                localized: """
                    This card was deleted meanwhile, in the Cards window. Close the review panel and open \
                    “Review now” again.
                    """,
                comment: "An alert's message in the review panel, when the card it shows was deleted meanwhile."
            )
        case .migratedByNewerVersion, .emptyCapture, .captureNotInInbox, .notAnExpansion, .noCards, .cardNotNew,
            .cardStillNew, .cardNotDue, .cardNotInAppearance, .placementIsNotAnAnswer, .cardFlagged, .cardNotFlagged,
            .cardBuried, .cardNotBuried, .cardSetAside, .notOneEmoji, .cannotUndo, .unreadableReviewLog, .storage,
            .copyNotFound, .copyMigratedByNewerVersion, .backupsFolder, .notAnImage, .unreadableImageFile, .imagesFolder, .unreadableFile,
            .unwritableFile:
            localizedDescription
        }
    }
}
