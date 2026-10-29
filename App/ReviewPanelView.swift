import FichaCore
import FichaData
import SwiftUI

/// What the review panel shows, on Liquid Glass: the cards a review now or an
/// appearance brought, one at a time, each with its upper side on top and,
/// once flipped, its lower side under it. A card shows front first, or, when
/// it goes both ways, back first too, with the back on top and a "Back first"
/// mark. Every action has a key and a button: Space flips a card, 1, 2 and 3
/// rate it, Enter ends a first view, which Space flips first when it shows
/// back first, A asks a question about the card, which waits in the inbox as
/// a follow-up, M flags it with a note, E buries it, ⌘Z undoes the last thing
/// Lucas did, and Esc closes the panel, which snoozes an appearance. A side
/// with a sound has a ▶ under its text, which plays it and shows ■ while it
/// plays, and R plays or stops the lower side's sound once it shows, or else
/// the upper side's. When 1 makes a card forgotten often,
/// the panel offers to flag it, its note written: Enter flags it, and Esc
/// leaves it in his reviews. Once Lucas went through every card, the
/// panel stays open until he closes it, and offers more cards if there are
/// any, which Enter brings; review now with nothing due offers to review
/// ahead the same way. A card taller than the panel's maximum
/// height scrolls between the line at its top and what's under it, which
/// stay in view. `ReviewPanelState` decides what the panel shows and what
/// happens when Lucas acts, and the view draws it.
struct ReviewPanelView: View {
    /// The corner radius of the panel's glass, with continuous corners. The
    /// panel's window clips its content to it, which matches the glass while
    /// the glass is the view's outermost modifier.
    static let cornerRadius: CGFloat = 24

    /// The note the panel offers to flag a card forgotten often with, which
    /// says how many times Lucas forgot it, and back first when it was that
    /// way, and which he can add to.
    nonisolated static func forgottenOftenNote(for forgotten: ForgottenOften) -> String {
        switch forgotten.way {
        case .frontFirst:
            String(
                localized: "Forgotten \(forgotten.times) times",
                comment: """
                    The note the review panel offers to flag a card with, once the user answered “Don't know” to it \
                    this many times front first since its front or back last changed. They can add to it.
                    """)
        case .backFirst:
            String(
                localized: "Forgotten \(forgotten.times) times back first",
                comment: """
                    The note the review panel offers to flag a card with, once the user answered “Don't know” to it \
                    this many times back first, its back shown on top, since its front or back last changed. They \
                    can add to it.
                    """)
        }
    }

    /// The cards a review now or an appearance brought, or why review now
    /// couldn't bring them.
    let model: Result<ReviewPanelModel, EngineError>
    /// Plays the sound the panel says plays.
    let player: SoundPlayer
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
    /// Where the cursor is in the note, or what's selected: at the end of the
    /// note the panel offers, which the field would otherwise select whole as
    /// it takes the keyboard, so Lucas adds to it rather than replacing it.
    /// Whatever shows the note clears it first, in the same action, since a
    /// selection in the last note may lie past the end of the new one.
    @State private var noteSelection: TextSelection?
    /// Whether the question's field has the keyboard. Whatever shows the
    /// question sets it, in the same action, as the ask button does.
    @FocusState private var questionIsFocused: Bool
    /// Where the cursor is in the question, or what's selected, which the ask
    /// button clears as the note's is.
    @State private var questionSelection: TextSelection?

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
            // Here, around the panel's content rather than on it, so it's
            // one view.
            .onChange(of: playingSound) { _, playing in
                play(playing)
            }
            .padding(20)
            .frame(width: 400, alignment: .leading)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    /// The sound the panel says plays, if any.
    private var playingSound: ReviewPanelState.PlayingSound? {
        guard case .success(let panel) = model else { return nil }
        return panel.state.playingSound
    }

    /// Plays `playing`, the sound the panel says plays, from the start, or
    /// stops the one that played when it's nil.
    private func play(_ playing: ReviewPanelState.PlayingSound?) {
        guard case .success(let panel) = model, let playing,
            case .success(let sound)? = panel.state.sounds[playing.name]
        else {
            player.stop()
            return
        }
        player.play(sound.data) {
            panel.state.soundEnded(playing)
        }
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
        case .ask: Failure(title: "Couldn't save your question", message: error.messageInReviewPanel)
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
        case .firstView(let card, let way):
            sides(of: card, way, showingLowerSide: true, buttons: .forTheCard, in: panel) {
                topLine(way, isNew: true, tags: panel.state.tags)
            }
            enterButton(Text("Got it")) {
                panel.state.endFirstView()
            }
        case .upperSide(let card, let way, let isNew, let isAhead):
            sides(of: card, way, showingLowerSide: false, buttons: .forTheCard, in: panel) {
                topLine(way, isNew: isNew, isAhead: isAhead, tags: panel.state.tags)
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
        case .bothSides(let card, let way, let isAhead):
            sides(of: card, way, showingLowerSide: true, buttons: .forTheCard, in: panel) {
                topLine(way, isAhead: isAhead, tags: panel.state.tags)
            }
            HStack {
                ratingButton("Don't know", key: "1", rating: .again, in: panel)
                ratingButton("Sort of", key: "2", rating: .hard, in: panel)
                ratingButton("Know it", key: "3", rating: .good, in: panel)
            }
        case .flagging(let card, let way, let showsLowerSide):
            sides(of: card, way, showingLowerSide: showsLowerSide, buttons: .closeWithoutEsc, in: panel) {}
            noteEditor(of: panel)
        case .asking(let card, let way, let showsLowerSide):
            sides(of: card, way, showingLowerSide: showsLowerSide, buttons: .closeWithoutEsc, in: panel) {}
            questionEditor(of: panel)
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
    /// the panel's top right: the upper side, which `way` says, and the lower
    /// one when it shows. The panel's window stops at its share of the
    /// screen (`ReviewPanelWindow`). A card that doesn't fit has its upper
    /// side go under the line at its top, the panel's width, and when it
    /// still doesn't fit, its sides scroll, each card and way from its top,
    /// while the line at its top and the buttons stay in view, as what's
    /// under the card does. The scroll never takes the keyboard, so the
    /// panel's keys work as on a short card. The buttons show once, over the
    /// room each layout keeps for them, so no key belongs to two buttons.
    private func sides<TopLine: View>(
        of card: Card, _ way: Way, showingLowerSide: Bool, buttons: TopButtons, in panel: ReviewPanelModel,
        @ViewBuilder topLine: () -> TopLine
    ) -> some View {
        let line = topLine()
        let room = topButtons(buttons, of: panel, withKeys: false).hidden()
        let upper = upperSide(of: card, way, in: panel)
        let lower = lowerSide(of: card, way, in: panel)
        let bothSides = VStack(alignment: .leading, spacing: 16) {
            upper
            if showingLowerSide {
                lower
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        return ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 16) {
                header {
                    VStack(alignment: .leading, spacing: 8) {
                        line
                        upper
                    }
                } buttons: {
                    room
                }
                if showingLowerSide {
                    lower
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                header {
                    line
                } buttons: {
                    room
                }
                bothSides
            }
            VStack(alignment: .leading, spacing: 8) {
                header {
                    line
                } buttons: {
                    room
                }
                ScrollView {
                    bothSides
                        // The scroller sits in the panel's margin, beside the
                        // text rather than over it.
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
                // A card's two ways can come one after the other.
                .id(CardWay(cardID: card.id, way: way))
            }
        }
        .overlay(alignment: .topTrailing) {
            iconButtons {
                topButtons(buttons, of: panel, withKeys: true)
            }
        }
        .background {
            // R, as M and E, while the card shows with its buttons. It works
            // through a hidden button, since the ▶ it presses changes with
            // the side that shows.
            if buttons == .forTheCard {
                Button {
                    panel.state.playOrStopSound()
                } label: {
                    Text(
                        "Play or Stop Sound",
                        comment:
                            "A hidden button of the review panel: R, which plays the sound of the side that shows, or stops the one that plays."
                    )
                }
                .keyboardShortcut("r", modifiers: [])
                .disabled(panel.state.sideForR == nil)
                .hidden()
            }
        }
    }

    /// Which buttons a card has at the panel's top right.
    private enum TopButtons {
        /// Undo, ask, flag, bury, and close, with Esc.
        case forTheCard
        /// Close alone, without Esc, which goes back to the card while the user
        /// writes a note to flag it or a question about it.
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

    /// The buttons for the card Lucas is on: ⌘Z undoes the last thing he did,
    /// A asks a question about this card, M flags it with a note, and E buries
    /// it. Without `withKeys`, none of them has its key.
    @ViewBuilder
    private func cardButtons(of panel: ReviewPanelModel, withKeys: Bool) -> some View {
        undoButton(of: panel, withKeys: withKeys)
        Button(
            String(
                localized: "Ask…",
                comment:
                    "A button that asks a question about the card the review panel shows, which waits in the inbox tied to the card."
            ),
            systemImage: "questionmark.bubble"
        ) {
            panel.state.startAsking()
            // The question's field gets the keyboard in the same action that
            // shows it, as the note's does (#61), with no selection left from
            // the last question.
            questionSelection = nil
            questionIsFocused = true
        }
        .keyboardShortcut(withKeys ? KeyboardShortcut("a", modifiers: []) : nil)
        .help(Text("Ask… (a)", comment: "The tooltip of the button that asks a question about the card, with its key."))
        Button(
            String(
                localized: "Flag…",
                comment: "A button that flags the card the review panel shows, asking for a note on what to fix."),
            systemImage: "flag"
        ) {
            panel.state.startFlagging()
            // The note's field gets the keyboard in the same action that
            // shows it, with no selection left from the last note. Asked from
            // the field's `onAppear` instead, after M, SwiftUI never focused
            // it while the panel had the keyboard (#61).
            noteSelection = nil
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

    /// The button that undoes the last thing the user did: ⌘Z, unless
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
    /// Option-Enter starts a new line, and Esc goes back to the card, or, when
    /// the panel offered to flag it, moves on without flagging it.
    private func noteEditor(of panel: ReviewPanelModel) -> some View {
        writingField(
            Text("Note"),
            text: Binding(get: { panel.state.note ?? "" }, set: { panel.state.write(note: $0) }),
            prompt: Text("What needs fixing?"),
            selection: $noteSelection,
            isFocused: $noteIsFocused,
            cancelTitle: panel.state.offersToFlag
                ? Text(
                    "Don't flag",
                    comment:
                        "The button that declines the review panel's offer to flag a card the user forgot often: the card stays in their reviews."
                ) : Text("Cancel"),
            finishTitle: Text("Flag", comment: "The button that flags the card with the note written above it."),
            canFinish: panel.state.noteSaysWhatToFix,
            cancel: { panel.state.cancelFlagging() },
            finish: { panel.state.finishFlagging() }
        )
        // Set once the field has the keyboard: it selects its whole text as
        // it takes it, which would replace the note the panel offers.
        .onChange(of: noteIsFocused) { _, isFocused in
            if isFocused, let note = panel.state.note {
                noteSelection = TextSelection(insertionPoint: note.endIndex)
            }
        }
    }

    /// Where Lucas writes a question about the card he's on: Enter saves it
    /// as a follow-up and stays on the card, Option-Enter starts a new line,
    /// and Esc goes back to the card.
    private func questionEditor(of panel: ReviewPanelModel) -> some View {
        writingField(
            Text(
                "Question",
                comment:
                    "The label of the field where the user writes a question about the card the review panel shows."
            ),
            text: Binding(get: { panel.state.question ?? "" }, set: { panel.state.write(question: $0) }),
            prompt: Text(
                "What do you want to know?",
                comment:
                    "The prompt of the field where the user writes a question about the card the review panel shows."
            ),
            selection: $questionSelection,
            isFocused: $questionIsFocused,
            cancelTitle: Text("Cancel"),
            finishTitle: Text(
                "Ask",
                comment:
                    "The button that saves the question written above it, which waits in the inbox tied to the card."),
            canFinish: panel.state.questionAsksSomething,
            cancel: { panel.state.cancelAsking() },
            finish: { panel.state.finishAsking() }
        )
    }

    /// A field under the card where Lucas writes about it, with its cursor or
    /// what's selected in `selection`, which has the keyboard while
    /// `isFocused` says so: Enter does `finish`, which its button, titled
    /// `finishTitle`, does only when `canFinish`, Option-Enter starts a new
    /// line, and Esc does `cancel`, as its button, titled `cancelTitle`, does.
    private func writingField(
        _ label: Text, text: Binding<String>, prompt: Text, selection: Binding<TextSelection?>,
        isFocused: FocusState<Bool>.Binding, cancelTitle: Text, finishTitle: Text, canFinish: Bool,
        cancel: @escaping () -> Void, finish: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            TextField(text: text, selection: selection, prompt: prompt, axis: .vertical) {
                label
            }
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .focused(isFocused)
            // A focused text field keeps Return from reaching the default
            // button.
            .onSubmit(finish)
            HStack {
                Button(action: cancel) {
                    KeyLabel(
                        title: cancelTitle,
                        key: String(localized: "esc", comment: "The Esc key's name, next to the button it presses.")
                    )
                }
                .keyboardShortcut(.cancelAction)
                Button(action: finish) {
                    KeyLabel(title: finishTitle, key: "↩")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canFinish)
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

    /// The line at the top of a card: its badges, "New" on a first view,
    /// "Ahead" on a review ahead and "Back first" when `way` is, each when it
    /// applies, and the card's tags, when it has some.
    @ViewBuilder
    private func topLine(_ way: Way, isNew: Bool = false, isAhead: Bool = false, tags: [CardTag]) -> some View {
        let isBackFirst = way == .backFirst
        if isNew || isAhead || isBackFirst || !tags.isEmpty {
            TagLine(tags: tags) {
                if isNew {
                    newBadge
                }
                if isAhead {
                    AheadBadge()
                }
                if isBackFirst {
                    BackFirstBadge()
                }
            }
        }
    }

    /// The side on top, which `way` says, and Lucas sees first: its image,
    /// fitted to the panel's width, above its text, large, and its sound's ▶
    /// under them, each when it has one.
    private func upperSide(of card: Card, _ way: Way, in panel: ReviewPanelModel) -> some View {
        let side = way.upperSide
        return VStack(alignment: .leading, spacing: 8) {
            if let image = card.image(on: side) {
                SideImage(image: panel.state.images[image], maximumHeight: imageHeight)
            }
            if !card.text(on: side).isEmpty {
                Text(card.text(on: side))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sound = card.sound(on: side) {
                soundControls(sound, on: side, in: panel)
            }
        }
    }

    /// The other side, under a line, once Lucas flips the card: its image,
    /// fitted to the panel's width, above its text, and its sound's ▶ under
    /// them, each when it has one, and the card's source, small, when it has
    /// one, at the card's foot whichever way it shows.
    private func lowerSide(of card: Card, _ way: Way, in panel: ReviewPanelModel) -> some View {
        let side = way.lowerSide
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let image = card.image(on: side) {
                SideImage(image: panel.state.images[image], maximumHeight: imageHeight)
            }
            if !card.text(on: side).isEmpty {
                Text(card.text(on: side))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sound = card.sound(on: side) {
                soundControls(sound, on: side, in: panel)
            }
            if let source = card.source {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The ▶ of `sound`, on `side` of the card, with its length: ■ while it
    /// plays, and off while Lucas writes about the card.
    private func soundControls(_ sound: SoundName, on side: CardSide, in panel: ReviewPanelModel) -> some View {
        SoundControls(
            sound: panel.state.sounds[sound], isPlaying: panel.state.isPlaying(on: side),
            takesR: panel.state.sideForR == side
        ) {
            panel.state.playOrStopSound(on: side)
        }
        .disabled(!panel.state.canPlaySounds)
    }

    private func ratingButton(
        _ title: LocalizedStringKey, key: Character, rating: Rating, in panel: ReviewPanelModel
    ) -> some View {
        Button {
            panel.state.rate(rating)
            // When the rating makes the card forgotten often, the panel
            // offers to flag it: the note's field gets the keyboard in the
            // same action that shows it, as after M (#61), with no selection
            // left from the last note. Once it has the keyboard, the cursor
            // goes after the note.
            if panel.state.offersToFlag {
                noteSelection = nil
                noteIsFocused = true
            }
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

/// The badge of a card that shows back first, on the card the review panel
/// shows that way and beside a first view or review that went that way in
/// the Cards window's review log.
struct BackFirstBadge: View {
    var body: some View {
        Text(
            "Back first",
            comment: """
                A badge on a card the review panel shows back first, its back on top and its front under it once \
                flipped, and beside a first view or review that went that way in the Cards window's review log.
                """
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.secondary.opacity(0.15), in: .capsule)
    }
}

/// The line at the top of a card in the review panel: its badges, "New" or
/// "Ahead", and "Back first", when it has some, and then its tags, each as
/// the Cards window's Tags column draws it, so that Lucas knows which subject
/// the card is about, and which way he's asked, before he answers it. It's
/// one line, so the panel stays as small as it is: the tags that don't fit
/// collapse into a "+n" capsule, whose tooltip names them.
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
/// fits in less, once its upper side moves under the line at its top, takes
/// less. SwiftUI's `Layout` is standard; this one is ours.
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
        case .migratedByNewerVersion, .emptyCapture, .captureNotInInbox, .notAnExpansion, .noCards,
            .blankSideOnNewCard, .sideLeftBlank, .noFileOnSide, .cardNotNew, .cardStillNew, .cardNotDue,
            .cardNotInAppearance, .placementIsNotAnAnswer, .cardFlagged, .cardNotFlagged, .cardBuried, .cardNotBuried,
            .cardSetAside, .notOneEmoji, .tagInsideItself, .blankTagName, .blankTypeName, .builtInTypeName,
            .typeNameTaken, .userTypeNotFound, .cannotUndo, .cannotUndoFollowUp, .unreadableReviewLog, .storage,
            .copyNotFound, .copyMigratedByNewerVersion, .backupsFolder, .notAnImage, .notASound, .soundConversion,
            .unreadableFileForSide, .noSuchFile, .fileNotInDownloads, .fileNotAnImage, .fileNotASound,
            .notAnImageOrSound, .noFileNamed,
            .imagesFolder, .soundsFolder, .unreadableFile, .unwritableFile:
            localizedDescription
        }
    }
}
