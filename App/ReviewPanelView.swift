import FichaCore
import FichaData
import SwiftUI

/// What the review panel shows, on Liquid Glass: the cards a review now or an
/// appearance brought, one at a time, each with its upper side on top and, once
/// flipped, its lower side under it, the card alone, with no deck, tags or
/// intervals (ADR 0033). A card shows front first, or, when it goes both ways,
/// back first too, with the back on top and a "Back first" mark, and a review
/// ahead is marked "Ahead". Every action on a card has a key: Space flips a
/// card, and then three buttons answer it, Forgot, on 1, a yellow Kind of, on
/// 2, and Got it, on Space and 3, named New to me, Kind of and Knew it on a new
/// way's first review (`AnswerButton`). A ⋯ menu in the corner offers the rest,
/// each also on its key: M flags the card with a note, E sets it aside
/// (`CardAction`), ⌘Z undoes the last thing Lucas did, and Esc closes the
/// panel, which snoozes an appearance. A side with a sound has a ▶ under its
/// text, which plays it and shows ■ while it plays, and R plays or stops the
/// lower side's sound once it shows, or else the upper side's. When 1 makes a
/// card forgotten often, the panel offers to flag it, its note written: Enter
/// flags it, and Esc leaves it in his reviews. Once Lucas went through every
/// card, the panel stays open until he closes it, says "You've met them all"
/// for each deck whose last new card he met in it, with the next deck in the
/// queue, or, while nothing waits there, a button for one of Ficha's decks,
/// which opens the Cards window to add it, and offers more cards if there are
/// any, which Enter brings; review now with nothing due offers to review ahead
/// the same way. A card taller than the panel's maximum height scrolls between
/// the line at its top and what's under it, which stay in view. A card's text
/// and images show at the card size, which ⌘+, ⌘− and ⌘0 change
/// (`ReviewPanelWindow`), and above 100% the panel widens with them; its
/// buttons, a sound's ▶, the note's field and its messages stay their size, as
/// Anki's bottom bar does. `ReviewPanelState` decides what the panel shows and
/// what happens when Lucas acts, and the view draws it.
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
                    The note the review panel offers to flag a card with, once the user answered “Forgot”, Anki's \
                    Again, to it this many times front first while it was graduated, out of its learning and \
                    relearning steps, since its front or back last changed: Anki's lapses. They can add to it.
                    """)
        case .backFirst:
            String(
                localized: "Forgotten \(forgotten.times) times back first",
                comment: """
                    The note the review panel offers to flag a card with, once the user answered “Forgot”, Anki's \
                    Again, to it this many times back first, its back shown on top, while it was graduated, out of \
                    its learning and relearning steps, since its front or back last changed: Anki's lapses. They can \
                    add to it.
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
    /// Reads Ficha's decks from the app, once "You've met them all" asks for
    /// them, to offer one while nothing waits in the queue, each deck's file
    /// or why it couldn't be read: nil until the window gives the panel a
    /// way to, or when the render tool reads none.
    var readFichaDecks: () async -> [FichaDeck: Result<FichaDeckFile, EngineError>]? = { nil }
    /// Opens the Cards window on one of Ficha's decks with How fast?, as its
    /// Add Deck… does, as the panel closes.
    var addFichaDeck: (FichaDeck) -> Void = { _ in }
    /// The tallest a side's image shows.
    private var imageHeight: CGFloat { cardSize.imageHeightLimit(panelTallest: maximumHeight) }
    /// The widest the answer buttons and the writing fields show, the inside of
    /// the panel at 100%, so they stay their size as it widens with the card.
    private static let controlsWidth = CardSize.normal.panelWidth - 2 * 20
    /// How large a card's text and images show.
    @Environment(\.cardSize) private var cardSize
    /// Whether the note's field has the keyboard. Whatever shows the note
    /// sets it, in the same action, as M and the ⋯ menu's Flag… do.
    @FocusState private var noteIsFocused: Bool
    /// Where the cursor is in the note, or what's selected: at the end of the
    /// note the panel offers, which the field would otherwise select whole as
    /// it takes the keyboard, so Lucas adds to it rather than replacing it.
    /// Whatever shows the note clears it first, in the same action, since a
    /// selection in the last note may lie past the end of the new one.
    @State private var noteSelection: TextSelection?
    /// Whether the panel reads right to left, which says whether a card's
    /// upper side can sit beside the ⋯ menu.
    @Environment(\.layoutDirection) private var layoutDirection
    /// Whether the panel looks as it does with the keyboard, which macOS
    /// draws a prominent button's color in: without it, Kind of is gray, as
    /// Got it is.
    @Environment(\.appearsActive) private var appearsActive

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
            .task(id: asksForFichaDecks) {
                guard asksForFichaDecks, case .success(let panel) = model else { return }
                if let read = await readFichaDecks() {
                    panel.state.offerFichaDecks(read)
                }
            }
            .padding(20)
            .frame(width: cardSize.panelWidth, alignment: .leading)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    /// The sound the panel says plays, if any.
    private var playingSound: ReviewPanelState.PlayingSound? {
        guard case .success(let panel) = model else { return nil }
        return panel.state.playingSound
    }

    /// Whether the panel asks for Ficha's decks, to offer one in "You've met
    /// them all".
    private var asksForFichaDecks: Bool {
        guard case .success(let panel) = model else { return false }
        return panel.state.asksForFichaDecks
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
        case .setAside: Failure(title: "Couldn't set the card aside", message: error.messageInReviewPanel)
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
        case .upperSide(let card, let way, _, let isAhead):
            sides(of: card, way, showingLowerSide: false, buttons: .forTheCard, in: panel) {
                marks(way, isAhead: isAhead)
            }
            HStack {
                Spacer()
                Button {
                    panel.state.flip()
                } label: {
                    KeyLabel(title: Text("Flip"), key: keyName(of: .space))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
            }
        case .bothSides(let card, let way, let isNew, let isAhead):
            sides(of: card, way, showingLowerSide: true, buttons: .forTheCard, in: panel) {
                marks(way, isAhead: isAhead)
            }
            answerButtons(isNew: isNew, in: panel)
        case .flagging(let card, let way, let showsLowerSide):
            sides(of: card, way, showingLowerSide: showsLowerSide, buttons: .whileWriting, in: panel) {}
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
                moreMenu(of: panel)
            }
            .background {
                menuKeys(of: panel)
            }
            metThemAll(of: panel)
            enterButton(Text("See more")) {
                panel.state.seeMore()
            }
        case .done:
            header {
                Text("You went through every card.")
                    .font(.headline)
            } buttons: {
                moreMenu(of: panel)
            }
            .background {
                menuKeys(of: panel)
            }
            metThemAll(of: panel)
            enterButton(
                Text("Done", comment: "A button that closes the review panel once every card was gone through."),
                action: closeByLucas)
        }
    }

    /// What the done panel says it met in full, under its title (ADR 0034,
    /// #491), as the state says it: "You've met them all", for each deck an
    /// answer in it met in full, and then the next deck in the queue new
    /// cards come from, or that nothing waits there, with a button for one
    /// of Ficha's decks the user hasn't added, which closes the panel and
    /// opens the Cards window on it, with How fast? (#458), on the same row
    /// as the line while they fit, and under it otherwise. All in a filled
    /// rounded box, as the mock's `MetThemAll` is. Nothing while it met
    /// none.
    @ViewBuilder
    private func metThemAll(of panel: ReviewPanelModel) -> some View {
        if let met = panel.state.metThemAll {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(met.decks, id: \.name) { deck in
                    Text(
                        "You've met them all: \(deck.title)",
                        comment: """
                            In the review panel, once it went through its cards, for each deck whose last new card \
                            an answer in it met, with the deck's emoji and name.
                            """
                    )
                    .fontWeight(.semibold)
                }
                if let next = met.nextInQueue {
                    Text(
                        "Next in the queue: \(next.title). Its first card comes with the next new one.",
                        comment: """
                            In the review panel, under the decks it met in full: the deck new cards come from \
                            now, with its emoji and name.
                            """
                    )
                    .foregroundStyle(.secondary)
                } else if let deck = met.fichaDeck {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            anotherFichaDeck
                            Spacer(minLength: 0)
                            fichaDeckButton(deck, of: panel)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            anotherFichaDeck
                            fichaDeckButton(deck, of: panel)
                        }
                    }
                } else {
                    Text(
                        "Nothing waits in the queue.",
                        comment: "In the review panel, under the decks it met in full: no deck has new cards."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 14))
        }
    }

    /// What "You've met them all" says while nothing waits in the queue and
    /// it offers one of Ficha's decks.
    private var anotherFichaDeck: some View {
        Text(
            "Nothing waits in the queue. Another of Ficha's decks?",
            comment: """
                In the review panel, under the decks it met in full: no deck has new cards, and a \
                button beside it, or under it, adds one of the decks that come with Ficha.
                """
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The button for `deck`, one of Ficha's decks the user hasn't added,
    /// which closes the panel and opens the Cards window on it, with How
    /// fast?.
    private func fichaDeckButton(_ deck: FichaDeck, of panel: ReviewPanelModel) -> some View {
        Button {
            addFichaDeck(deck)
            panel.state.close(.byLucas)
        } label: {
            Text(
                "\(deck.emoji) \(deck.name)…",
                comment: """
                    A button in the review panel, once nothing waits in the queue, with the emoji and the \
                    name of one of Ficha's decks: it opens the Cards window to add it.
                    """)
        }
        .fixedSize()
    }

    /// The panel's main button, at its bottom trailing corner, which Enter
    /// presses.
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
        Text(
            """
            A review ahead brings the cards closest to being due. It counts, and lengthens a card's interval less \
            the earlier it comes.
            """,
            comment:
                "Under the review panel's offer to review ahead, when no card is due: what a review ahead does, as FSRS counts it."
        )
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

    /// A card's sides, under the line at its top and beside the ⋯ menu at the
    /// panel's top trailing corner: the upper side, which `way` says, and the
    /// lower one when it shows. The panel's window stops at its share of the
    /// screen (`ReviewPanelWindow`). A card that doesn't fit has its upper
    /// side go under the line at its top, the panel's width, and when it still
    /// doesn't fit, its sides scroll, each card and way from its top, while
    /// the line at its top and the menu stay in view, as what's under the card
    /// does. The scroll never takes the keyboard, so the panel's keys work as
    /// on a short card. The menu shows once, over the room each layout keeps
    /// for it. An upper side that reads against the panel, a Spanish card in
    /// Arabic, always goes under the line at its top, since beside the menu it
    /// would start from where the menu ends, rather than from the panel's edge
    /// as its lower side does.
    private func sides<TopLine: View>(
        of card: Card, _ way: Way, showingLowerSide: Bool, buttons: TopButtons, in panel: ReviewPanelModel,
        @ViewBuilder topLine: () -> TopLine
    ) -> some View {
        let line = topLine()
        let room = moreMenu(of: panel).hidden()
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
            if layoutDirection.readsFromLeadingSide(card.text(on: way.upperSide)) {
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
                moreMenu(of: panel)
            }
        }
        .background {
            // R, as A, M and E (`menuKeys(of:)`), while the card shows, on a
            // layout of another script too (`LetterKey`). It works through a
            // hidden button, since the ▶ it presses changes with the side that
            // shows.
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
                menuKeys(of: panel)
            }
        }
    }

    /// Whether the panel takes the keys of a card's ⋯ menu, as its state says
    /// what the menu holds.
    private enum TopButtons {
        /// M, E, ⌘Z and Esc, and R, while the card shows.
        case forTheCard
        /// None, while Lucas writes a note to flag the card, where Esc goes
        /// back to the card.
        case whileWriting
    }

    /// The ⋯ menu at the panel's top trailing corner, for whoever doesn't
    /// remember a key (ADR 0033): what Lucas can do with the card he's on
    /// (`CardAction`), then Undo and Close. While he writes about the card,
    /// it holds Close alone, and once he went through every card, Undo and
    /// Close (`ReviewPanelState.menuOffersUndo`). Its items show no keys,
    /// which the panel keeps on hidden buttons instead (`menuKeys(of:)`), so
    /// that each key belongs to one control, which takes it whether the menu
    /// is open or not.
    private func moreMenu(of panel: ReviewPanelModel) -> some View {
        Menu {
            ForEach(panel.state.cardActions, id: \.self) { action in
                Button {
                    perform(action, in: panel)
                } label: {
                    title(of: action)
                }
            }
            if !panel.state.cardActions.isEmpty {
                Divider()
            }
            if panel.state.menuOffersUndo {
                Button("Undo") {
                    panel.state.undoLastCard()
                }
                .disabled(!panel.state.canUndo)
            }
            Button("Close") {
                panel.state.close(.byLucas)
            }
        } label: {
            Label {
                moreTitle
            } icon: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(moreTitle)
    }

    /// The ⋯ menu's name, which its tooltip and VoiceOver say.
    private var moreTitle: Text {
        Text(
            "More",
            comment: """
                The review panel's ⋯ menu, which asks about the card, flags it or sets it aside, undoes the last \
                thing the user did, or closes the panel.
                """)
    }

    /// The keys of what the ⋯ menu does, on hidden buttons, since a menu's
    /// items take their keys only while it's open: A, M and E, while a card
    /// shows (`CardAction`), ⌘Z, which undoes the last thing Lucas did, and
    /// Esc, which closes the panel. The letters work on a layout of another
    /// script too (`LetterKey`).
    @ViewBuilder
    private func menuKeys(of panel: ReviewPanelModel) -> some View {
        ForEach(panel.state.cardActions, id: \.self) { action in
            Button {
                perform(action, in: panel)
            } label: {
                title(of: action)
            }
            .keyboardShortcut(KeyEquivalent(action.key), modifiers: [])
            .hidden()
        }
        Button("Undo") {
            panel.state.undoLastCard()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!panel.state.canUndo)
        .hidden()
        Button("Close") {
            panel.state.close(.byLucas)
        }
        .keyboardShortcut(.cancelAction)
        .hidden()
    }

    /// What the ⋯ menu calls `action`.
    private func title(of action: CardAction) -> Text {
        switch action {
        case .flag:
            Text(
                "Flag…",
                comment: """
                    An item of the review panel's ⋯ menu, whose key is M: it flags the card the panel shows, asking \
                    for a note on what to fix.
                    """)
        case .setAside:
            Text(
                "Set Aside",
                comment: """
                    An item of the review panel's ⋯ menu, whose key is E: it sets aside the card the panel shows, \
                    which shows up no more until the user puts it back in the Cards window.
                    """)
        }
    }

    /// Does `action` with the card Lucas is on, from the ⋯ menu or its key.
    /// The note's field gets the keyboard in the same
    /// action that shows it, with no selection left from the last one: asked
    /// from the field's `onAppear` instead, after M, SwiftUI never focused it
    /// while the panel had the keyboard (#61).
    private func perform(_ action: CardAction, in panel: ReviewPanelModel) {
        panel.state.choose(action)
        switch action {
        case .flag:
            noteSelection = nil
            noteIsFocused = true
        case .setAside:
            break
        }
    }

    /// The button that closes the panel with `close`, and with Esc, while it
    /// shows no card.
    private func closeButton(_ close: @escaping () -> Void) -> some View {
        Button("Close", systemImage: "xmark", action: close)
            .keyboardShortcut(.cancelAction)
            .help(Text("Close (esc)"))
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
        // In the trailing corner of a wider panel, as its main button is.
        .frame(maxWidth: Self.controlsWidth)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The marks over a card's upper side, each when it applies: "Ahead" on a
    /// review ahead, and "Back first" when `way` is. The panel shows nothing
    /// else of the card above it (ADR 0033).
    @ViewBuilder
    private func marks(_ way: Way, isAhead: Bool) -> some View {
        if isAhead || way == .backFirst {
            HStack(spacing: 4) {
                if isAhead {
                    AheadBadge()
                }
                if way == .backFirst {
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
                TextAsItReads(card.text(on: side))
                    .cardFont(.title)
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
                TextAsItReads(card.text(on: side))
                    .cardFont(.body)
            }
            if let sound = card.sound(on: side) {
                soundControls(sound, on: side, in: panel)
            }
            if let source = card.source {
                TextAsItReads(source)
                    .cardFont(.caption)
                    .foregroundStyle(.secondary)
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

    /// The three buttons that answer the card once its lower side shows
    /// (`AnswerButton`), in the middle of a wider panel, as Anki's bottom bar.
    /// Their rating keys work through hidden buttons, one each (`RatingKey`),
    /// since a button takes one key, and Got it's is Space. Key 4 has none, so
    /// it rates nothing (ADR 0039). The note's field never shows with them,
    /// so Space in it types a space.
    private func answerButtons(isNew: Bool, in panel: ReviewPanelModel) -> some View {
        HStack {
            ForEach(AnswerButton.allCases, id: \.self) { button in
                answerButton(button, isNew: isNew, in: panel)
            }
        }
        .frame(maxWidth: Self.controlsWidth)
        .frame(maxWidth: .infinity)
        .background {
            ForEach(AnswerButton.allCases, id: \.self) { button in
                Button {
                    rate(button.rating, in: panel)
                } label: {
                    Text(verbatim: String(button.ratingKey))
                }
                .keyboardShortcut(KeyEquivalent(button.ratingKey), modifiers: [])
                .hidden()
            }
        }
    }

    /// The button that rates the card as `button` says, with the key its label
    /// shows. When `isNew`, a new way's first review, where Forgot means nothing,
    /// Forgot and Got it are named New to me and Knew it, and Kind of keeps its
    /// name. The one Space presses is the prominent one, as Flip is. Kind of is
    /// yellow, filled as the prominent one is, with a dark title, since a white
    /// one on yellow barely reads; Forgot stays gray. Without the keyboard, macOS
    /// draws Kind of and Got it gray too, and Kind of's title takes the others'
    /// color, since a dark one barely reads on dark gray.
    @ViewBuilder
    private func answerButton(_ button: AnswerButton, isNew: Bool, in panel: ReviewPanelModel) -> some View {
        let label = KeyLabel(title: name(of: button, isNew: isNew), key: keyName(of: button.key))
            .frame(maxWidth: .infinity)
        let answer = { rate(button.rating, in: panel) }
        switch button {
        case .gotIt:
            Button(action: answer) { label }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
        case .kindOf:
            Button(action: answer) {
                if appearsActive {
                    label.foregroundStyle(.black)
                } else {
                    label
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
        case .forgot:
            Button(action: answer) { label }
                .buttonStyle(.bordered)
        }
    }

    /// What `button` is called, on a new way's first review when `isNew`.
    private func name(of button: AnswerButton, isNew: Bool) -> Text {
        switch (button, isNew) {
        case (.forgot, false):
            Text(
                "Forgot",
                comment: """
                    The review panel's button, once a card is turned over, for a card the user didn't remember: it \
                    records Anki's Again. Its key is 1.
                    """)
        case (.kindOf, _):
            Text(
                "Kind of",
                comment: """
                    The review panel's yellow button in the middle, once a card is turned over, a new card's first \
                    turn included, for a card the user remembered with effort: it records Anki's Hard. Its key is 2.
                    """)
        case (.gotIt, false):
            Text(
                "Got it",
                comment: """
                    The review panel's button, once a card is turned over, for a card the user remembered: it records \
                    Anki's Good. Its keys are Space and 3.
                    """)
        case (.forgot, true):
            Text(
                "New to me",
                comment: """
                    The review panel's Forgot button on a new card's first turn, for a card the user hadn't met \
                    before: it records Anki's Again. Its key is 1.
                    """)
        case (.gotIt, true):
            Text(
                "Knew it",
                comment: """
                    The review panel's Got it button on a new card's first turn, for a card the user already knew: it \
                    records Anki's Good. Its keys are Space and 3.
                    """)
        }
    }

    /// The name a button's label shows for `key`: a digit as it is, and
    /// Space's from the String Catalog.
    private func keyName(of key: AnswerButton.Key) -> String {
        switch key {
        case .digit(let digit): String(digit)
        case .space: String(localized: "space", comment: "The Space key's name, next to the button it presses.")
        }
    }

    /// Rates the card the panel shows `rating`. When the rating makes the
    /// card forgotten often, the panel offers to flag it: the note's field
    /// gets the keyboard in the same action that shows it, as after M (#61),
    /// with no selection left from the last note. Once it has the keyboard,
    /// the cursor goes after the note.
    private func rate(_ rating: Rating, in panel: ReviewPanelModel) {
        panel.state.rate(rating)
        if panel.state.offersToFlag {
            noteSelection = nil
            noteIsFocused = true
        }
    }
}

/// The badge of a review ahead, on the card the review panel brings before
/// it's due and beside the review in the Cards window's review log, with a
/// tooltip on what a review ahead does. Its title stays on one line, as a
/// capsule's can't wrap.
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
        .fixedSize()
        .help(
            Text(
                "A review ahead: it counts, and lengthens the card's interval less the earlier it comes.",
                comment: "The tooltip of the Ahead badge, in the review panel and the Cards window's review log."))
    }
}

/// The badge of a card that shows back first, on the card the review panel
/// shows that way and beside a review that went that way in the Cards
/// window's review log. Its title stays on one line, as a capsule's can't
/// wrap: in German, "Rückseite zuerst" broke onto three in the review log.
struct BackFirstBadge: View {
    var body: some View {
        Text(
            "Back first",
            comment: """
                A badge on a card the review panel shows back first, its back on top and its front under it once \
                flipped, and beside a review that went that way in the Cards window's review log.
                """
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.secondary.opacity(0.15), in: .capsule)
        .fixedSize()
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

/// A button's title, followed by the key that does the same, small, as the
/// review panel's buttons and How fast?'s show them. The key shows as it's
/// given: a symbol, a digit, or a key's name, like Space's, which the caller
/// takes from the String Catalog.
struct KeyLabel: View {
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
        case .migratedByNewerVersion, .blankSideOnNewCard, .sideLeftBlank, .noFileOnSide, .cardNotDue,
            .cardNotInAppearance, .placementIsNotAnAnswer, .cardFlagged, .cardNotFlagged, .cardBuried, .cardNotBuried,
            .cardSetAside, .notOneEmoji, .tagInsideItself, .blankTagName, .tagNotPinned, .deckSetAside, .blankDeckName,
            .defaultDeckName, .deckInsideItself, .deckInsideDefault, .defaultDeckStays, .deckNotFound, .blankTypeName,
            .builtInTypeName, .typeNameTaken, .userTypeNotFound, .cannotUndo, .unreadableReviewLog,
            .schedulerFailed, .storage,
            .copyNotFound, .copyMigratedByNewerVersion, .backupsFolder, .notAnImage, .notASound, .soundConversion,
            .unreadableFileForSide, .noSuchFile, .fileNotInDownloads, .fileNotAnImage, .fileNotASound,
            .notAnImageOrSound, .noFileNamed,
            .imagesFolder, .soundsFolder, .unreadableFile, .unwritableFile, .fichaDeckMissing, .descriptionTooLong:
            localizedDescription
        }
    }
}
