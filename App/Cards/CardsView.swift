import FichaCore
import FichaData
import SwiftUI
import UniformTypeIdentifiers

/// The Cards window's content, in three panes as Mail lays out its own: a
/// sidebar to choose a group of cards, the inbox, a deck or All Tags, a table
/// with one row per card in it, or per capture and flagged card in the inbox,
/// narrowed by the toolbar's search field, and the selected row whole beside
/// it, with what Lucas can do with it at its foot. The sidebar's Decks
/// section lists every deck as a tree, Default first while it holds cards,
/// each with how many of its cards are due, grayed while its cards are out
/// of Lucas's reviews; a deck's context menu, and the Actions menu above the
/// card list while the sidebar chose it (`DeckMenu.swift`), set it aside or
/// prioritize it; and Change Deck… moves the
/// selected cards to the deck Lucas picks in its sheet, or names there with
/// New Deck… (`ChangeDeckSheet.swift`). The sidebar's Tags section
/// lists the tags he pins, in the order he drags them into, and ends with All
/// Tags…, which lists every tag where the table was, as a tree with columns
/// and a checkbox (`AllTagsOutline.swift`, ADR 0022), and a tag's cards in
/// its place, with Back. A tag's context menu, in either place, and the
/// detail's Actions menu beside All Tags, act on the tags selected there:
/// they pin them to the sidebar or unpin them, give them a color and an
/// emoji, which the sidebar and the table's
/// Tags column show, rename one, in the rename sheet (`RenameSheet.swift`),
/// and delete them, asking first; and in All Tags Lucas drags tags into the
/// sidebar to pin them there, onto another to move them inside, or between
/// two rows to move them to that level. The sidebar's Types section lists
/// the four types Ficha comes with, then the user's, each with its emoji,
/// whose context menu renames it, gives it an emoji, in the same sheets, and
/// deletes it, asking first; New Type… in a card's type picker makes one, in
/// the New Type sheet (`NewTypeSheet.swift`).
/// The cards' table opens with the columns
/// and the order Lucas left it with, which he changes in its headers. He
/// edits a card or a capture right there, in fields that take the detail's
/// place while the sidebar and the table wait. He selects several cards with
/// ⌘ or Shift, as in Finder, and then the detail says how many, with what he
/// can do with all of them. New Card in the toolbar, or ⌘N, and Convert to
/// Card on a capture open the card form, a sheet of its own
/// (`CardFormSheet.swift`), Import… in the toolbar opens the Import sheet
/// (`ImportSheet.swift`), which imports a text file of cards, and Export…
/// opens the Export sheet (`ExportSheet.swift`), which saves cards to one.
/// `CardsWindowState` decides what the window lists, shows, offers and asks,
/// and what happens when Lucas acts, and the view draws it. It reads the cards
/// again whenever
/// the engine says they changed, from the app or the `ficha` CLI, when Lucas
/// changes the ladder in Settings, and every minute, since cards come due as
/// time passes, or at once when Ficha Dev's debug menu moves the time.
struct CardsView: View {
    let model: AppModel
    /// What the sidebar chose, what Lucas looks for and selected, and so what
    /// the table lists, the detail shows and its actions offer, and what he
    /// edits, what the window asks and what failed.
    @State private var state: CardsWindowState
    @FocusState private var isSearchFocused: Bool
    /// The table's order: the one Lucas left it in with a click on a column's
    /// header, and at first the newest cards first.
    @State private var sortOrder = Preferences.cardsSortOrder
    /// The table's columns as Lucas left them: which ones show, in what order
    /// and how wide. At first Front, Media, Step and Due, until he adds
    /// others from the headers' menu.
    @State private var columns = Preferences.cardsColumns
    /// The inbox's order: the latest added first, until Lucas clicks a
    /// column's header.
    @State private var inboxSortOrder = [InboxRowOrder(.added, order: .reverse)]
    /// Whether the table has the keyboard, which it gets back once Lucas
    /// saves or cancels an edit, for him to go on with the arrow keys.
    @FocusState private var isTableFocused: Bool
    /// Plays the sound the window says plays, in the form, the editor or the
    /// detail.
    @State private var player = SoundPlayer()

    /// The content for the user's cards in `model`, opening with `state` when
    /// it's given, as `make render` opens it partway through an import, and
    /// on All cards otherwise.
    init(model: AppModel, state: CardsWindowState? = nil) {
        self.model = model
        _state = State(initialValue: state ?? model.openCardsWindow())
    }

    var body: some View {
        askingAboutTags(askingAboutTypes(panes))
            .creatingCards($state, failure: failure(overSheet: true), newTypeFailure: failure(over: .newTypeSheet))
            .changeDeckSheet($state, failure: failure(overSheet: true))
            .sheet(item: Binding(get: { cardToFlag }, set: { if $0 == nil { state.cancelQuestion() } })) { row in
                FlagSheet(card: row.card, failure: failure(overSheet: true)) { note in
                    state.flag(note: note)
                }
            }
            // Each button acts on what its dialog presents, which SwiftUI
            // hands it: closing the dialog may drop the state's question
            // before the button acts.
            .confirmationDialog(
                captureToDiscard.map {
                    Text(
                        "Discard “\($0.text)”?",
                        comment: "The title of the Cards window's question before it discards a capture, with its text."
                    )
                } ?? Text(verbatim: ""),
                isPresented: Binding(get: { captureToDiscard != nil }, set: { if !$0 { state.cancelQuestion() } }),
                titleVisibility: .visible,
                presenting: captureToDiscard
            ) { capture in
                Button(role: .destructive) {
                    state.discard(capture)
                } label: {
                    Text("Discard", comment: "The button that discards the capture the Cards window asks about.")
                }
            } message: { _ in
                Text(
                    "It leaves the inbox without becoming cards, and you can't bring it back.",
                    comment: "Under the title of the Cards window's question before it discards a capture.")
            }
            .confirmationDialog(
                cardsToDelete.map { deletionTitle(for: $0) } ?? Text(verbatim: ""),
                isPresented: Binding(get: { cardsToDelete != nil }, set: { if !$0 { state.cancelQuestion() } }),
                titleVisibility: .visible,
                presenting: cardsToDelete
            ) { rows in
                Button(role: .destructive) {
                    state.delete(rows)
                } label: {
                    Text("Delete", comment: "The button that deletes the cards the Cards window asks about.")
                }
            } message: { rows in
                deletionMessage(for: rows)
            }
            .failureAlert(failure(overSheet: false))
            .task {
                // Listening before reading, so no change falls in between.
                let changes = model.changes()
                readCards()
                for await _ in changes {
                    readCards()
                }
            }
            .task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return
                    }
                    readCards()
                }
            }
            .onChange(of: model.settings.ladder) {
                readCards()
            }
            .onChange(of: model.debugTools?.timeShift) {
                readCards()
            }
            .onChange(of: state.playingSound) {
                play(state.playingSound)
            }
            .onDisappear {
                player.stop()
            }
    }

    /// The window's three panes, with the toolbar's search field, Import…
    /// and Export…, and ⌘F; and, while the table lists a tag's cards in All
    /// Tags' place, the tag's name as the window's title, and Back. While the
    /// table's pane lists All Tags' tree, it's at least wide enough for its
    /// six columns to leave the tag's some room, and the detail beside it,
    /// a few buttons, can be narrower to give it: a minimum the split view
    /// keeps whenever it changes, where an ideal width counts only as the
    /// window first opens. The panes' least widths add up to the window's
    /// either way.
    private var panes: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 280)
                .waiting(while: state.editing != nil)
        } content: {
            table
                .navigationSplitViewColumnWidth(min: listsAllTagsTree ? 500 : 380, ideal: 440)
                .waiting(while: state.editing != nil)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: listsAllTagsTree ? 220 : 300, ideal: 380)
        }
        .searchable(text: searchText, placement: .toolbar)
        .searchFocused($isSearchFocused)
        .navigationTitle(state.shownTag?.title ?? String(localized: "Cards", comment: "The Cards window's title."))
        .toolbar {
            if state.shownTag != nil {
                ToolbarItem(placement: .navigation) {
                    backButton
                }
            }
        }
        // The toolbar lists the outer modifier's buttons first: New Card,
        // then Import…, then Export….
        .exportButtonAndSheet($state, failure: failure(overSheet: true))
        .importButtonAndSheet($state)
        .background {
            // ⌘F puts Lucas in the search field, as in Mail and Finder. The
            // search field doesn't take it on its own.
            Button {
                isSearchFocused = true
            } label: {
                Text("Find", comment: "A hidden button of the Cards window: ⌘F, which goes to the search field.")
            }
            .keyboardShortcut("f")
            .hidden()
        }
    }

    /// `content` with the window's questions about card types of the user's
    /// own: the New Type sheet that New Type… in the editor's type picker
    /// opens, the card form's opening its own over the form, and the
    /// question Delete… on a user type asks, with how many cards have it.
    private func askingAboutTypes(_ content: some View) -> some View {
        content
            .newTypeSheet(for: .editor, $state, failure: failure(over: .newTypeSheet))
            .confirmationDialog(
                typeToDelete.map {
                    Text(
                        "Delete the type “\($0.type.name)”?",
                        comment:
                            "The title of the Cards window's question before it deletes a card type of the user's own, with its name."
                    )
                } ?? Text(verbatim: ""),
                isPresented: Binding(get: { typeToDelete != nil }, set: { if !$0 { state.cancelQuestion() } }),
                titleVisibility: .visible,
                presenting: typeToDelete
            ) { deleted in
                Button(role: .destructive) {
                    state.deleteType(deleted.type)
                } label: {
                    Text("Delete", comment: "The button that deletes the card type the Cards window asks about.")
                }
            } message: { deleted in
                Text(
                    "\(deleted.cardCount) cards have this type. They keep everything else, with no type.",
                    comment: """
                        Under the title of the Cards window's question before it deletes a card type of the user's own, \
                        with how many cards have it, buried ones too.
                        """)
            }
    }

    /// `content` with the window's questions about tags: Delete…'s, which
    /// says what deleting the tags does, since the Cards window has no undo,
    /// and Clear Unused Tags…'s, with how many tags it deletes. Each button
    /// acts on what its dialog presents.
    private func askingAboutTags(_ content: some View) -> some View {
        content
            .confirmationDialog(
                tagsToDelete.map(tagDeletionTitle(for:)) ?? Text(verbatim: ""),
                isPresented: Binding(get: { tagsToDelete != nil }, set: { if !$0 { state.cancelQuestion() } }),
                titleVisibility: .visible,
                presenting: tagsToDelete
            ) { deletion in
                Button(role: .destructive) {
                    state.deleteTags(deletion)
                } label: {
                    Text("Delete", comment: "The button that deletes the tags the Cards window asks about.")
                }
            } message: { deletion in
                Text(verbatim: tagDeletionMessage(for: deletion))
            }
            .confirmationDialog(
                unusedTagsToClear.map {
                    Text(
                        "Delete \($0.count) unused tags?",
                        comment: """
                            The title of the Cards window's question before Clear Unused Tags… deletes the tags no \
                            card carries, with how many.
                            """)
                } ?? Text(verbatim: ""),
                isPresented: Binding(get: { unusedTagsToClear != nil }, set: { if !$0 { state.cancelQuestion() } }),
                titleVisibility: .visible,
                presenting: unusedTagsToClear
            ) { _ in
                Button(role: .destructive) {
                    state.clearUnusedTags()
                } label: {
                    Text(
                        "Clear Unused Tags",
                        comment: "The button that deletes the unused tags the Cards window asks about.")
                }
            } message: { _ in
                Text(
                    """
                    No card carries them, so no card changes. What you gave them goes with them, a pin, a color or \
                    an emoji, and you can't undo this.
                    """,
                    comment: "Under the title of the Cards window's question before Clear Unused Tags… deletes them.")
            }
    }

    /// The tags the window asks whether to delete, with what that does,
    /// while it asks.
    private var tagsToDelete: TagDeletion? {
        guard case .deleteTags(let deletion) = state.question else { return nil }
        return deletion
    }

    /// The unused tags the window asks whether to delete, while it asks.
    private var unusedTagsToClear: [String]? {
        guard case .clearUnusedTags(let names) = state.question else { return nil }
        return names
    }

    /// The title of the question before Lucas deletes the tags of
    /// `deletion`: the tag's whole name when it's one, or how many when
    /// they're several.
    private func tagDeletionTitle(for deletion: TagDeletion) -> Text {
        if deletion.tags.count == 1, let tag = deletion.tags.first {
            Text(
                "Delete the tag “\(TagPath.shown(tag))”?",
                comment: "The title of the Cards window's question before it deletes a tag, with its whole name.")
        } else {
            Text(
                "Delete \(deletion.tags.count) tags?",
                comment: "The title of the Cards window's question before it deletes several tags, with how many.")
        }
    }

    /// What the question before Lucas deletes the tags of `deletion` says
    /// under its title, a sentence for each thing it does: the tags inside
    /// them that go too, the cards that lose them, which stay, those of them
    /// that come back to his reviews, and, under selective sync, those that
    /// stop syncing; and that it can't be undone. The sentences follow one
    /// another as the Mac's language joins them, with a space in English.
    private func tagDeletionMessage(for deletion: TagDeletion) -> String {
        let isOne = deletion.tags.count == 1
        var sentences: [String] = []
        if !deletion.tagsInside.isEmpty {
            sentences.append(
                isOne
                    ? String(
                        localized: "The \(deletion.tagsInside.count) tags inside it go with it.",
                        comment: "In the Cards window's question before it deletes a tag: the tags inside it.")
                    : String(
                        localized: "The \(deletion.tagsInside.count) tags inside them go with them.",
                        comment: "In the Cards window's question before it deletes several tags: the tags inside them."
                    ))
        }
        sentences.append(
            isOne
                ? String(
                    localized: "\(deletion.cards) cards lose it, and keep everything else.",
                    comment: "In the Cards window's question before it deletes a tag: the cards that carry it.")
                : String(
                    localized: "\(deletion.cards) cards lose them, and keep everything else.",
                    comment: "In the Cards window's question before it deletes several tags: the cards that carry them."
                ))
        if let stopSyncing = deletion.cardsThatStopSyncing, stopSyncing > 0 {
            sentences.append(
                String(
                    localized: "\(stopSyncing) of those cards stop syncing, left with no tag you chose to sync.",
                    comment: """
                        In the Cards window's question before it deletes tags, while only the cards with a tag Lucas \
                        chose sync: the cards that stop syncing.
                        """))
        }
        sentences.append(
            String(
                localized: "You can't undo this.",
                comment: "The last sentence of the Cards window's question before it deletes tags."))
        return sentences.reduce(into: "") { text, sentence in
            text =
                text.isEmpty
                ? sentence
                : String(
                    localized: "tag-deletion.next-sentence", defaultValue: "\(text) \(sentence)",
                    comment: """
                        Joins two sentences of the Cards window's question before it deletes tags: what it says so \
                        far, then the next sentence, as the language writes one sentence after another.
                        """)
        }
    }

    /// Back, which lists All Tags again in place of a tag's cards, as Lucas
    /// left it: ⌘[, as Back in Finder and Safari.
    private var backButton: some View {
        Button {
            state.goBack()
        } label: {
            Label(
                String(
                    localized: "Back",
                    comment: "A toolbar button of the Cards window, while it lists a tag's cards: back to All Tags."),
                systemImage: "chevron.left")
        }
        .keyboardShortcut("[", modifiers: .command)
        .disabled(!state.canGoBack)
        .help(Text("Back to All Tags (⌘[)", comment: "The tooltip of the Cards window's Back button."))
    }

    /// Reads Lucas's cards, as they are now, on the ladder he set in
    /// Settings.
    private func readCards() {
        state.read(on: model.settings.ladder)
    }

    /// Plays `playing`, the sound the window says plays, from the start, or
    /// stops the one that played when it's nil.
    private func play(_ playing: PlayingSound?) {
        guard let playing, case .success(let sound)? = state.sounds[playing.name] else {
            player.stop()
            return
        }
        player.play(sound.data) {
            state.soundEnded(playing)
        }
    }

    /// The card the window asks Lucas to flag, while the flag sheet asks for
    /// his note.
    private var cardToFlag: CardRow? {
        guard case .flag(let row) = state.question else { return nil }
        return row
    }

    /// The tag or the user type the window asks which emoji to give, while
    /// the emoji sheet asks.
    private var emojiSubject: SheetSubject? {
        switch state.question {
        case .emoji(let tag): .tag(tag)
        case .typeEmoji(let type): .type(type)
        default: nil
        }
    }

    /// The tag or the user type the window asks which name to give, while
    /// the rename sheet asks.
    private var renameSubject: SheetSubject? {
        switch state.question {
        case .renameTag(let tag): .tag(tag)
        case .renameType(let type): .type(type)
        default: nil
        }
    }

    /// The user type the window asks whether to delete, with how many cards
    /// have it, while it asks.
    private var typeToDelete: (type: UserType, cardCount: Int)? {
        guard case .deleteType(let type, let cardCount) = state.question else { return nil }
        return (type, cardCount)
    }

    /// The capture the window asks whether to discard, while it asks.
    private var captureToDiscard: Capture? {
        guard case .discard(let capture) = state.question else { return nil }
        return capture
    }

    /// The cards the window asks whether to delete, while it asks.
    private var cardsToDelete: [CardRow]? {
        guard case .delete(let rows) = state.question else { return nil }
        return rows
    }

    /// Where an alert says what failed: over the window, over one of its
    /// sheets, or over the New Type sheet, which opens over the card form.
    private enum AlertPlace {
        case window
        case sheet
        case newTypeSheet
    }

    /// Where the alert shows now: over the New Type sheet while it's open;
    /// over the flag sheet, the emoji sheet, the rename sheet, the Change Deck
    /// sheet, the card form or the Export sheet while one is open, since the
    /// window's own alert can't show over its sheet; and over the window
    /// otherwise.
    private var alertPlace: AlertPlace {
        if case .newType = state.question {
            return .newTypeSheet
        }
        let isSheetOpen =
            cardToFlag != nil || emojiSubject != nil || renameSubject != nil || state.deckChange != nil
            || state.cardForm != nil || state.exporting != nil
        return isSheetOpen ? .sheet : .window
    }

    /// What Lucas did that couldn't be saved, as an alert says it, which
    /// closing it clears, for the alert over a sheet, or over the window, as
    /// `overSheet` says.
    private func failure(overSheet: Bool) -> Binding<Failure?> {
        failure(over: overSheet ? .sheet : .window)
    }

    /// What Lucas did that couldn't be saved, as the alert at `place` says
    /// it while the alert shows there, which closing it clears.
    private func failure(over place: AlertPlace) -> Binding<Failure?> {
        Binding {
            guard place == alertPlace else { return nil }
            return state.failure.map(alert(for:))
        } set: {
            if $0 == nil {
                state.dismissFailure()
            }
        }
    }

    /// What the alert says when `failure` happened: what Lucas did that
    /// couldn't be saved, and why, in the window's words.
    private func alert(for failure: CardsWindowState.Failure) -> Failure {
        let error = failure.error
        switch failure.action {
        case .saveCard:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't save the card", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: 1))
        case .saveCapture:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't save the capture", comment: "An alert's title in the Cards window."),
                message: error.messageForCaptureInCardsWindow(
                    ifItLeft: String(
                        localized: """
                            This capture left the inbox outside this window meanwhile, approved or discarded in a \
                            refine session, so nothing was saved. To keep what you typed, copy it before you cancel.
                            """,
                        comment:
                            "An alert's message in the Cards window, when the capture Lucas saves already left the inbox."
                    )))
        case .discard:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't discard the capture", comment: "An alert's title in the Cards window."),
                message: error.messageForCaptureInCardsWindow(
                    ifItLeft: String(
                        localized: """
                            This capture left the inbox outside this window meanwhile, approved or discarded in a \
                            refine session, so there's nothing to discard. The window now shows the inbox as it is.
                            """,
                        comment:
                            "An alert's message in the Cards window, when the capture Lucas discards already left the inbox."
                    )))
        case .addCard:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't add the card", comment: "An alert's title over the Cards window's card form."),
                message: error.messageForCaptureInCardsWindow(
                    ifItLeft: String(
                        localized: """
                            The capture this form was opened from left the inbox outside this window meanwhile, \
                            approved or discarded in a refine session, so the card wasn't added. To keep what you \
                            typed, copy it before you close the form.
                            """,
                        comment:
                            "An alert's message over the Cards window's card form, when its capture already left the inbox."
                    )))
        case .approveCapture:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't take the capture out of the inbox",
                    comment: "An alert's title in the Cards window, after closing the card form opened from a capture."),
                message: error.messageForCaptureInCardsWindow(
                    ifItLeft: String(
                        localized: """
                            This capture left the inbox outside this window meanwhile, approved or discarded in a \
                            refine session. The cards you added from it are saved.
                            """,
                        comment: """
                            An alert's message in the Cards window, after closing the card form, when its capture \
                            already left the inbox.
                            """
                    )))
        case .putImage:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't add the image",
                    comment: "An alert's title in the Cards window, after dragging or pasting onto a side of a card."),
                error: error)
        case .putSound:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't add the sound",
                    comment:
                        "An alert's title in the Cards window, after dragging or pasting a file onto a side's sound."
                ),
                error: error)
        case .flag:
            return Failure(title: "Couldn't flag the card", message: error.messageInCardsWindow(actingOn: 1))
        case .bury(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't bury \(count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: count))
        case .unbury(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't unbury \(count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: count))
        case .turnOnBothWays(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't turn on Both ways for \(count) cards",
                    comment: "An alert's title in the Cards window, after Turn On Both Ways on several cards."),
                message: error.messageInCardsWindow(actingOn: count))
        case .turnOffBothWays(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't turn off Both ways for \(count) cards",
                    comment: "An alert's title in the Cards window, after Turn Off Both Ways on several cards."),
                message: error.messageInCardsWindow(actingOn: count))
        case .delete(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't delete \(count) cards", comment: "An alert's title in the Cards window."),
                message: error.messageInCardsWindow(actingOn: count))
        case .changeDeck(let count):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't move \(count) cards to another deck",
                    comment: "An alert's title in the Cards window's Change Deck sheet, after Move."),
                message: error.messageInCardsWindow(actingOn: count))
        case .setAside(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't set “\(Deck.shownName(deck))” aside",
                    comment: "An alert's title in the Cards window, after Set Aside in a deck's menu, with the deck."),
                error: error)
        case .stopSettingAside(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't untick Set Aside on “\(Deck.shownName(deck))”",
                    comment: """
                        An alert's title in the Cards window, after choosing a ticked Set Aside in a deck's menu, \
                        with the deck.
                        """),
                error: error)
        case .prioritize(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't make “\(Deck.shownName(deck))” a priority deck",
                    comment: "An alert's title in the Cards window, after Prioritize in a deck's menu, with the deck."),
                error: error)
        case .stopPrioritizing(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't untick Prioritize on “\(Deck.shownName(deck))”",
                    comment: """
                        An alert's title in the Cards window, after choosing a ticked Prioritize in a deck's menu, \
                        with the deck.
                        """),
                error: error)
        case .deleteTags(let tag):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't delete “\(TagPath.shown(tag))”",
                    comment: """
                        An alert's title in the Cards window, after Delete… in a tag's menu or its question, with \
                        the tag's whole name, the first when Lucas deletes several.
                        """),
                error: error)
        case .clearUnusedTags:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't clear the unused tags",
                    comment: "An alert's title in the Cards window, after Clear Unused Tags… or its question."),
                error: error)
        case .setColor(let tag):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't change the color of “\(TagPath.shown(tag))”",
                    comment: "An alert's title in the Cards window, after a color in a tag's menu, with the tag."),
                error: error)
        case .setEmoji(let tag):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't change the emoji of “\(TagPath.shown(tag))”",
                    comment: "An alert's title in the Cards window's emoji sheet, after OK, with the tag."),
                error: error)
        case .rename(let tag):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't rename “\(TagPath.shown(tag))”",
                    comment: "An alert's title in the Cards window's rename sheet, after OK, with the tag's whole name."
                ),
                error: error)
        case .move(let tag):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't move “\(TagPath.shown(tag))”",
                    comment: """
                        An alert's title in the Cards window, after dragging a tag in All Tags onto another or \
                        between two rows, with the tag's whole name, the first when Lucas drags several.
                        """),
                error: error)
        case .pin(let tag):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't pin “\(TagPath.shown(tag))” to the sidebar",
                    comment: """
                        An alert's title in the Cards window, after Pin to Sidebar in a tag's menu, its Pinned \
                        checkbox in All Tags or dragging a tag into the sidebar, with the tag's whole name.
                        """),
                error: error)
        case .unpin(let tag):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't unpin “\(TagPath.shown(tag))” from the sidebar",
                    comment: """
                        An alert's title in the Cards window, after Unpin from Sidebar in a tag's menu or unticking \
                        its Pinned checkbox in All Tags, with the tag's whole name.
                        """),
                error: error)
        case .reorderPinned(let tag):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't move “\(TagPath.shown(tag))” in the sidebar",
                    comment: """
                        An alert's title in the Cards window, after dragging a pinned tag to another place among the \
                        sidebar's pinned tags, with the tag's whole name.
                        """),
                error: error)
        case .export:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't export the cards",
                    comment: "An alert's title in the Cards window, after Export… or over its Export sheet."),
                error: error)
        case .makeType:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't make the type",
                    comment: "An alert's title in the Cards window's New Type sheet, after OK."),
                error: error)
        case .renameType(let name):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't rename the type “\(name)”",
                    comment: "An alert's title in the Cards window's rename sheet, after OK, with a card type's name."),
                error: error)
        case .setTypeEmoji(let name):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't change the emoji of the type “\(name)”",
                    comment: "An alert's title in the Cards window's emoji sheet, after OK, with a card type's name."),
                error: error)
        case .deleteType(let name):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't delete the type “\(name)”",
                    comment: "An alert's title in the Cards window, after Delete… in a card type's menu, with its name."
                ),
                error: error)
        }
    }

    /// What Lucas chooses from, in the sections the state lists, in its
    /// order. One is chosen at a time, always.
    private var sidebar: some View {
        List(selection: chosenItem) {
            ForEach(state.sidebarSections) { section in
                sidebarSection(section)
            }
        }
        .sheet(isPresented: Binding(get: { emojiSubject != nil }, set: { if !$0 { state.cancelQuestion() } })) {
            if let subject = emojiSubject {
                EmojiSheet(subject: subject, failure: failure(overSheet: true)) { text in
                    state.emojiEntry(text)
                } choose: { text in
                    state.chooseEmoji(text)
                }
            }
        }
        .sheet(isPresented: Binding(get: { renameSubject != nil }, set: { if !$0 { state.cancelQuestion() } })) {
            if let subject = renameSubject {
                RenameSheet(subject: subject, failure: failure(overSheet: true)) { text in
                    state.renameEntry(text)
                } choose: { text in
                    state.chooseNewName(text)
                }
            }
        }
    }

    /// The sidebar's section `section`: the cards by where they stand; the
    /// inbox, with how many things wait in it, as the menu counts them; the
    /// decks as a tree, each parent open or closed as Lucas left it, each
    /// deck with how many of its cards are due; the
    /// cards of each pinned tag, in Lucas's order, each with its context
    /// menu, which he drags into another order, or tags from All Tags in
    /// among them to pin them, then All Tags…, which pins tags dropped on it
    /// after them, the one place to drop them while none is pinned; or the
    /// cards by type, the user's types with their context menu.
    @ViewBuilder
    private func sidebarSection(_ section: CardsWindowState.SidebarSection) -> some View {
        switch section {
        case .cardGroups(let groups):
            Section {
                ForEach(groups, id: \.self) { group in
                    Label(group.title, systemImage: group.symbol)
                        .tag(SidebarItem.cards(group))
                }
            }
        case .inbox:
            Section {
                Label(
                    String(
                        localized: "Inbox", comment: "An item of the Cards window's sidebar: what waits to be refined."),
                    systemImage: "tray"
                )
                .badge(model.progress?.inInbox ?? 0)
                .tag(SidebarItem.inbox)
            }
        case .decks(let rows):
            Section {
                ForEach(rows) { row in
                    DeckBranch(row: row, state: $state)
                }
            } header: {
                Text("Decks", comment: "A section of the Cards window's sidebar: the decks, as a tree.")
            }
        case .tags(let pinned):
            Section {
                ForEach(pinned) { tag in
                    TagRow(tag: tag)
                        .tag(tag.item)
                        .contextMenu {
                            tagMenu(for: [tag.id])
                        }
                }
                // List's own move, with its insertion line, and its own
                // insert, for tags dragged in from All Tags, which the state
                // knows, as they come as text, as any text does. Its
                // insert's action comes as the tags are dropped, before All
                // Tags hears the drag ended, where `dropDestination`'s comes
                // once it read the text, which can be after.
                .onMove { offsets, destination in
                    state.movePinnedTags(fromOffsets: offsets, toOffset: destination)
                }
                .onInsert(of: [.utf8PlainText]) { offset, _ in
                    state.pinDraggedTags(at: offset)
                }
                Label {
                    Text(
                        "All Tags…",
                        comment: """
                            The last item of the Tags section of the Cards window's sidebar: it lists every tag, \
                            pinned or not.
                            """)
                } icon: {
                    Image(systemName: "ellipsis.circle")
                }
                .takingDraggedTags(while: state.draggedTags != nil) { state.dropDraggedTagsOnAllTags() }
                .tag(SidebarItem.allTags)
            } header: {
                Text(
                    "Tags",
                    comment: "A section of the Cards window's sidebar: the tags Lucas pinned, then All Tags….")
            }
        case .types(let groups):
            Section {
                ForEach(groups, id: \.self) { group in
                    TypeRow(group: group)
                        .tag(SidebarItem.cards(group))
                        .contextMenu {
                            typeMenu(for: group)
                        }
                }
            } header: {
                Text("Types", comment: "A section of the Cards window's sidebar: the card types.")
            }
        }
    }

    /// The context menu of the sidebar's type group `group`, as the state
    /// offers it, a user type's: Rename…, which opens the rename sheet;
    /// Emoji…, which opens the emoji sheet; and Delete…, which asks first,
    /// with how many cards have the type.
    @ViewBuilder
    private func typeMenu(for group: CardGroup) -> some View {
        if let type = state.typeMenu(for: group) {
            Button {
                state.askToRenameType(type.id)
            } label: {
                Text(
                    "Rename…",
                    comment:
                        "An item of the menu of a tag, in the Cards window's sidebar or its All Tags, or of a card type in its sidebar: it asks for its new name."
                )
            }
            Button {
                state.askForTypeEmoji(type.id)
            } label: {
                Text(
                    "Emoji…",
                    comment:
                        "An item of the menu of a tag, in the Cards window's sidebar or its All Tags, or of a card type in its sidebar: it asks for its emoji."
                )
            }
            Divider()
            Button {
                state.askToDeleteType(type.id)
            } label: {
                Text(
                    "Delete…",
                    comment:
                        "An item of a card type's menu in the Cards window's sidebar: it asks whether to delete the type."
                )
            }
        }
    }

    /// All Tags, where the table was: every tag as a tree, with its columns
    /// and checkboxes, each tag's context menu acting on the tags selected
    /// with it; or what it says while there's no tag, or the search finds
    /// none.
    private func allTags(_ rows: [CardsWindowState.AllTagsRow]) -> some View {
        AllTagsOutline(rows: rows, state: $state) { tags in
            NSHostingMenu(rootView: tagMenu(for: tags))
        }
        .overlay {
            if rows.isEmpty {
                if state.hasSearch {
                    ContentUnavailableView.search(text: state.search)
                } else {
                    ContentUnavailableView(
                        String(
                            localized: "No tags", comment: "In the Cards window's All Tags, when no card has a tag."),
                        systemImage: "tag",
                        description: Text(
                            "The tags you write on your cards show up here.",
                            comment: "In the Cards window's All Tags, when no card has a tag."))
                }
            }
        }
    }

    /// The context menu of the tags named `tags`, one in the sidebar, one or
    /// several in All Tags, as the state offers it, which the detail's
    /// Actions menu beside All Tags offers too: Pin to Sidebar, or Unpin from
    /// Sidebar while all are pinned; Rename…, which opens the rename sheet,
    /// for one tag; Color, with None and Finder's seven colors, each with a
    /// swatch, the one they all have ticked; Emoji…, which opens the emoji
    /// sheet, for one tag; and Delete…, which asks first. Set Aside and
    /// Prioritize are a deck's (`DeckMenu.swift`, ADR 0024).
    @ViewBuilder
    private func tagMenu(for tags: [String]) -> some View {
        if let menu = state.menu(for: tags) {
            Button {
                state.choosePin(on: menu.tags)
            } label: {
                if menu.isPinned {
                    Text(
                        "Unpin from Sidebar",
                        comment: """
                            An item of a tag's menu in the Cards window's sidebar or its All Tags, while the tag is \
                            pinned: it takes the tag out of the sidebar.
                            """)
                } else {
                    Text(
                        "Pin to Sidebar",
                        comment: """
                            An item of a tag's menu in the Cards window's All Tags, while the tag isn't pinned: it \
                            lists the tag in the sidebar, after the pinned ones.
                            """)
                }
            }
            Divider()
            Button {
                if let tag = menu.tags.first {
                    state.askToRename(tag)
                }
            } label: {
                Text(
                    "Rename…",
                    comment:
                        "An item of the menu of a tag, in the Cards window's sidebar or its All Tags, or of a card type in its sidebar: it asks for its new name."
                )
            }
            .disabled(!menu.isForOneTag)
            Menu {
                ForEach(menu.colorItems, id: \.color) { item in
                    Toggle(
                        isOn: Binding(
                            get: { item.isTicked }, set: { _ in state.chooseColor(item.color, on: menu.tags) })
                    ) {
                        if let color = item.color {
                            Label {
                                Text(verbatim: color.name)
                            } icon: {
                                color.swatch
                            }
                        } else {
                            Text("None", comment: "The first item of the Color submenu of a tag's menu: no color.")
                        }
                    }
                }
            } label: {
                Text(
                    "Color",
                    comment: "A submenu of a tag's menu in the Cards window's sidebar or its All Tags: the tag's color."
                )
            }
            Button {
                if let tag = menu.tags.first {
                    state.askForEmoji(on: tag)
                }
            } label: {
                Text(
                    "Emoji…",
                    comment:
                        "An item of the menu of a tag, in the Cards window's sidebar or its All Tags, or of a card type in its sidebar: it asks for its emoji."
                )
            }
            .disabled(!menu.isForOneTag)
            Divider()
            Button {
                state.askToDeleteTags(menu.tags)
            } label: {
                Text(
                    "Delete…",
                    comment: """
                        An item of a tag's menu in the Cards window's sidebar or its All Tags: it asks whether to \
                        delete the tag, or the tags selected with it.
                        """)
            }
        }
    }

    /// The sidebar's selection: what it chose, which Lucas can change but not
    /// clear.
    private var chosenItem: Binding<SidebarItem?> {
        Binding {
            state.sidebarItem
        } set: {
            if let item = $0 {
                state.choose(item)
            }
        }
    }

    /// The search field's text: what Lucas looks for.
    private var searchText: Binding<String> {
        Binding {
            state.search
        } set: {
            state.search(for: $0)
        }
    }

    /// What the table says when `group`, or the search in it, brings no
    /// cards.
    @ViewBuilder
    private func noCards(in group: CardGroup) -> some View {
        if state.hasSearch {
            ContentUnavailableView.search(text: state.search)
        } else if group == .all {
            ContentUnavailableView(
                group.emptyTitle, systemImage: group.symbol,
                description: Text(
                    "The cards you create with New Card show up here, and the ones you bury, in Buried.",
                    comment: "In the Cards window, when All cards is empty."))
        } else {
            ContentUnavailableView(group.emptyTitle, systemImage: group.symbol)
        }
    }

    /// What the table says when the inbox, or the search in it, brings
    /// nothing.
    @ViewBuilder
    private var emptyInbox: some View {
        if state.hasSearch {
            ContentUnavailableView.search(text: state.search)
        } else {
            ContentUnavailableView(
                String(localized: "Nothing in the inbox", comment: "In the Cards window, when the inbox is empty."),
                systemImage: "tray",
                description: Text(
                    "What you capture, and the cards you flag, wait here to be refined.",
                    comment: "In the Cards window, when the inbox is empty."))
        }
    }

    /// Whether the table's pane lists All Tags' tree, whose six columns want
    /// more room than the cards' table.
    private var listsAllTagsTree: Bool {
        if case .success(.allTags) = state.listing { true } else { false }
    }

    @ViewBuilder
    private var table: some View {
        switch state.listing {
        case .success(.cards(let rows)):
            VStack(spacing: 0) {
                if let menu = state.chosenDeckMenu {
                    DeckBar(menu: menu, state: $state)
                }
                cardTable(rows)
            }
        case .success(.inbox(let rows)):
            inboxTable(rows)
        case .success(.allTags(let rows)):
            allTags(rows)
        case .failure(let error):
            ContentUnavailableView {
                Label("Couldn't load your cards", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            }
        case nil:
            EmptyView()
        }
    }

    /// The cards of the group the sidebar chose, or of the tag Lucas opened
    /// in All Tags, one per row. A right click on
    /// the headers shows SwiftUI's menu of the columns, as in Finder, which
    /// adds or removes all of them but Front.
    private func cardTable(_ rows: [CardRow]) -> some View {
        Table(
            rows.sorted(using: sortOrder), selection: selectedCards, sortOrder: $sortOrder,
            columnCustomization: $columns
        ) {
            TableColumn(
                Text("Front", comment: "A column of the Cards window: the card's front."),
                sortUsing: CardRowOrder(.front)
            ) {
                row in
                FrontCell(card: row.card)
            }
            .width(min: 120)
            .customizationID(CardRowOrder.Column.front.rawValue)
            // Always there, as Finder's Name: it says which card a row is.
            .disabledCustomizationBehavior(.visibility)
            TableColumn(
                Text(
                    "Media", comment: "A column of the Cards window: whether the card's sides have an image or a sound."
                ),
                sortUsing: CardRowOrder(.media)
            ) { row in
                MediaCell(card: row.card)
            }
            .width(min: 48, ideal: 56, max: 80)
            .customizationID(CardRowOrder.Column.media.rawValue)
            // In a group, since a table's builder takes ten columns at most.
            Group {
                TableColumn(
                    Text("Step", comment: "A column of the Cards window: the card's step on the ladder, and its wait."),
                    sortUsing: CardRowOrder(.step)
                ) { row in
                    Text(stepText(row.frontFirst))
                }
                .width(min: 56, ideal: 64, max: 100)
                .customizationID(CardRowOrder.Column.step.rawValue)
                TableColumn(
                    Text("Due", comment: "A column of the Cards window: when the card is due."),
                    sortUsing: CardRowOrder(.due)
                ) { row in
                    Text(dueText(row.frontFirst, at: state.now))
                }
                .width(min: 60, ideal: 72, max: 110)
                .customizationID(CardRowOrder.Column.due.rawValue)
                TableColumn(
                    Text(
                        "Back-first step",
                        comment:
                            "A column of the Cards window: the step on the ladder of a card that goes both ways, back first, and its wait."
                    ),
                    sortUsing: CardRowOrder(.backFirstStep)
                ) { row in
                    // Blank for a card that goes one way.
                    Text(row.backFirst.map(stepText) ?? "")
                }
                .width(min: 56, ideal: 120, max: 150)
                .customizationID(CardRowOrder.Column.backFirstStep.rawValue)
                .defaultVisibility(.hidden)
                TableColumn(
                    Text(
                        "Back-first due",
                        comment: "A column of the Cards window: when a card that goes both ways is due back first."),
                    sortUsing: CardRowOrder(.backFirstDue)
                ) { row in
                    // Blank for a card that goes one way.
                    Text(row.backFirst.map { dueText($0, at: state.now) } ?? "")
                }
                .width(min: 60, ideal: 120, max: 150)
                .customizationID(CardRowOrder.Column.backFirstDue.rawValue)
                .defaultVisibility(.hidden)
            }
            TableColumn(
                Text("Type", comment: "A column of the Cards window: the card's type."),
                sortUsing: CardRowOrder(.type)
            ) { row in
                // Blank for a card with no type.
                Text(row.card.type?.title ?? "")
            }
            .width(min: 60, ideal: 76, max: 110)
            .customizationID(CardRowOrder.Column.type.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text("Tags", comment: "A column of the Cards window: the card's tags."),
                sortUsing: CardRowOrder(.tags)
            ) { row in
                HStack(spacing: 4) {
                    ForEach(row.tags, id: \.name) { tag in
                        TagCapsule(tag: tag)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .width(min: 60, ideal: 120)
            .customizationID(CardRowOrder.Column.tags.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text("Source", comment: "A column of the Cards window: where Lucas came across the card's content."),
                sortUsing: CardRowOrder(.source)
            ) { row in
                Text(row.card.source ?? "")
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 120)
            .customizationID(CardRowOrder.Column.source.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text(
                    "Last seen",
                    comment: "A column of the Cards window: when Lucas last saw the card, in a first view or a review."),
                sortUsing: CardRowOrder(.lastSeen)
            ) { row in
                // Without the time, as the inbox's Added column.
                Text(row.lastSeen?.formatted(date: .abbreviated, time: .omitted) ?? "")
            }
            .width(min: 80, ideal: 96, max: 140)
            .customizationID(CardRowOrder.Column.lastSeen.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text("Created", comment: "A column of the Cards window: when Lucas approved the card."),
                sortUsing: CardRowOrder(.created)
            ) { row in
                Text(row.card.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            .width(min: 80, ideal: 96, max: 140)
            .customizationID(CardRowOrder.Column.created.rawValue)
            .defaultVisibility(.hidden)
            TableColumn(
                Text("Edited", comment: "A column of the Cards window: when the card's front or back last changed."),
                sortUsing: CardRowOrder(.edited)
            ) { row in
                // Blank for a card never edited.
                Text(row.card.editedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
            }
            .width(min: 80, ideal: 96, max: 140)
            .customizationID(CardRowOrder.Column.edited.rawValue)
            .defaultVisibility(.hidden)
        }
        .focused($isTableFocused)
        // The card Show Card selected, which may be far down the list.
        .revealingRow(state.cardToReveal) { state.cardRevealed() }
        .overlay {
            if rows.isEmpty, let group = state.listedGroup {
                noCards(in: group)
            }
        }
        // The window opens the next time with the table as Lucas leaves it.
        .onChange(of: sortOrder) {
            Preferences.cardsSortOrder = sortOrder
        }
        .onChange(of: columns) {
            Preferences.cardsColumns = columns
        }
    }

    /// What waits in the inbox, one row each: the captures, the expansions,
    /// the follow-ups and the flagged cards, which Lucas selects one at a
    /// time.
    private func inboxTable(_ rows: [InboxRow]) -> some View {
        Table(rows.sorted(using: inboxSortOrder), selection: selectedInInbox, sortOrder: $inboxSortOrder) {
            TableColumn(
                Text(
                    "Text",
                    comment: "A column of the Cards window's inbox: a capture's text, or a flagged card's front."),
                sortUsing: InboxRowOrder(.text)
            ) { row in
                if let cardRow = row.flaggedCard {
                    FrontCell(card: cardRow.card)
                } else {
                    Text(row.text)
                        .lineLimit(1)
                }
            }
            .width(min: 120)
            TableColumn(
                Text(
                    "Kind",
                    comment:
                        "A column of the Cards window's inbox: whether a row is a capture, an expansion, a follow-up or a card."
                ),
                sortUsing: InboxRowOrder(.kind)
            ) { row in
                Text(row.kindName)
            }
            .width(min: 64, ideal: 76, max: 110)
            TableColumn(
                Text(
                    "Added",
                    comment: "A column of the Cards window's inbox: when Lucas captured it, or flagged the card."),
                sortUsing: InboxRowOrder(.added)
            ) { row in
                // Without the time, to leave the Text column its room.
                Text(row.addedAt.formatted(date: .abbreviated, time: .omitted))
            }
            .width(min: 80, ideal: 96, max: 140)
        }
        .focused($isTableFocused)
        .overlay {
            if rows.isEmpty {
                emptyInbox
            }
        }
    }

    /// The cards' table's selection: the cards Lucas selected.
    private var selectedCards: Binding<Set<CardRow.ID>> {
        Binding {
            state.selection
        } set: {
            state.select($0)
        }
    }

    /// The inbox's table's selection: the row Lucas selected, one at a time.
    private var selectedInInbox: Binding<InboxRow.ID?> {
        Binding {
            state.inboxSelection
        } set: {
            state.selectInInbox($0)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.editing {
        case .card(let card):
            CardEditor(
                card: card, images: state.editedImages, shownImages: state.images, sounds: state.editedSounds,
                bothWays: state.editedBothWays, type: state.editedType, types: state.pickerTypes,
                canSave: state.canSaveCard, isSearching: isSearchFocused
            ) { dropped, side in
                state.putImageInEditor(dropped, on: side)
            } removeImage: { side in
                state.removeImageFromEditor(on: side)
            } soundWell: { side in
                SoundWell(
                    sound: state.editedSounds[side], sounds: state.sounds,
                    isComingIn: state.isSoundComingInEditor(on: side), isPlaying: state.isPlaying(at: .editor(side))
                ) {
                    state.playOrStopSound(at: .editor(side))
                } put: { file in
                    convert(state.putSoundInEditor(file, on: side), for: $state)
                } remove: {
                    state.removeSoundFromEditor(on: side)
                }
            } setBothWays: { bothWays in
                state.setBothWaysInEditor(bothWays)
            } setType: { type in
                state.setTypeInEditor(type)
            } newType: {
                state.askForNewType(in: .editor)
            } save: { content in
                state.saveCard(content)
                focusTableOnceEditEnds()
            } cancel: {
                state.cancelEditing()
                focusTableOnceEditEnds()
            }
        case .capture(let capture):
            CaptureEditor(capture: capture, isSearching: isSearchFocused) { text, note, source in
                state.saveCapture(text: text, note: note, source: source)
                focusTableOnceEditEnds()
            } cancel: {
                state.cancelEditing()
                focusTableOnceEditEnds()
            }
        case nil:
            switch state.detail {
            case .capture(let capture):
                CaptureDetail(capture: capture, kind: InboxRow.Item.capture(capture).kindName, tie: nil)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actionBar
                    }
            case .expansion(let expansion):
                CaptureDetail(
                    capture: expansion.capture, kind: InboxRow.Item.expansion(expansion).kindName,
                    tie: .expands(expansion.card)
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actionBar
                }
            case .followUp(let followUp):
                CaptureDetail(
                    capture: followUp.capture, kind: InboxRow.Item.followUp(followUp).kindName,
                    tie: .followsUp(followUp.card)
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actionBar
                }
            case .cards(let rows):
                selectionSummary(rows)
            case .card(let row, let reviewLog):
                CardDetail(
                    row: row, images: state.images, now: state.now, reviewLog: reviewLog, ladder: state.ladder
                ) { side in
                    SoundControls(
                        sound: row.card.sound(on: side).flatMap { state.sounds[$0] },
                        isPlaying: state.isPlaying(at: .detail(cardID: row.id, side))
                    ) {
                        state.playOrStopSound(at: .detail(cardID: row.id, side))
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actionBar
                }
            case .nothingSelectedInInbox:
                ContentUnavailableView(
                    String(
                        localized: "Nothing selected",
                        comment: "In the Cards window's detail, when nothing in the inbox is selected."),
                    systemImage: "tray")
            case .noCardSelected:
                ContentUnavailableView("No card selected", systemImage: "rectangle.on.rectangle")
            case .allTags(let selected):
                tagsDetail(selected)
            }
        }
    }

    /// What the detail says beside All Tags about the tags Lucas selected
    /// there: with none, what he can do with a tag; with one, its name, with
    /// Show Cards, the Actions menu, which is the tag's context menu, and
    /// Delete…; with several, how many, with the Actions menu and Delete…;
    /// and Clear Unused Tags… at its foot, while some tag is unused.
    private func tagsDetail(_ selected: [CardTag]) -> some View {
        Group {
            if selected.isEmpty {
                ContentUnavailableView(
                    String(
                        localized: "No tag selected",
                        comment: "In the Cards window's detail, beside All Tags, when no tag is selected."),
                    systemImage: "tag",
                    description: Text(
                        """
                        Double-click a tag to see its cards, or right-click it for what you can do with it. Drag tags \
                        onto another to move them inside, between two rows to move them to that level, or into the \
                        sidebar to pin them.
                        """,
                        comment: "In the Cards window's detail, beside All Tags: what Lucas does with a tag there."))
            } else {
                ContentUnavailableView {
                    if selected.count == 1, let tag = selected.first {
                        Label {
                            Text(verbatim: tag.title)
                        } icon: {
                            tag.symbol
                        }
                    } else {
                        Label(
                            String(
                                localized: "\(selected.count) tags selected",
                                comment: "In the Cards window's detail, when Lucas selected several tags in All Tags."),
                            systemImage: "tag")
                    }
                } actions: {
                    // Side by side, or one above another while the pane is
                    // too narrow for that, as beside All Tags in the
                    // window's least width.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            tagButtons(for: selected)
                        }
                        VStack {
                            tagButtons(for: selected)
                        }
                        .fixedSize()
                    }
                }
            }
        }
        // The whole pane, so that the bar is at its foot.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if state.tagActions.contains(.clearUnused) {
                ActionBar {
                    clearUnusedTagsButton
                    Spacer()
                }
            }
        }
    }

    /// A button for each thing Lucas can do with the tags `selected` in All
    /// Tags, as the state offers them: Show Cards, for one; the Actions menu,
    /// whose items are the tags' context menu's, so that each has a keyboard
    /// path; and Delete…. Each calls the state, which reads the selection as
    /// it is when Lucas acts.
    @ViewBuilder
    private func tagButtons(for selected: [CardTag]) -> some View {
        let actions = state.tagActions
        if actions.contains(.showCards) {
            showCardsButton
        }
        Menu {
            tagMenu(for: selected.map(\.name))
        } label: {
            Text(
                "Actions",
                comment: """
                    A menu button of the Cards window, beside All Tags: the context menu of the tags selected there.
                    """)
        }
        .fixedSize()
        if actions.contains(.delete) {
            deleteTagsButton
        }
    }

    /// Show Cards, which lists the selected tag's cards in All Tags' place:
    /// Return, as in Finder's list, but while Lucas is in the search field,
    /// where Return is the field's.
    private var showCardsButton: some View {
        Button(
            String(
                localized: "Show Cards",
                comment:
                    "A button of the Cards window, beside All Tags, that lists the selected tag's cards in its place."
            )
        ) {
            state.showCardsOfSelectedTag()
        }
        .keyboardShortcut(isSearchFocused ? nil : .defaultAction)
        .help(Text("Show Cards (↩)", comment: "The tooltip of the Cards window's button that lists a tag's cards."))
    }

    /// Delete…, which asks whether to delete the tags selected in All Tags:
    /// ⌘⌫, as Delete… for cards, since the two never show together, but
    /// while Lucas is in the search field, where ⌘⌫ deletes what he typed.
    private var deleteTagsButton: some View {
        Button(
            String(
                localized: "Delete…",
                comment: "A button of the Cards window, beside All Tags, that deletes the selected tags, asking first."
            )
        ) {
            state.askToDeleteSelectedTags()
        }
        .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.deleteKey, modifiers: .command))
        .help(Text("Delete… (⌘⌫)", comment: "The tooltip of the Cards window's button that deletes the tags."))
    }

    /// Clear Unused Tags…, which asks whether to delete the tags no card
    /// carries. It has no shortcut: given ⇧⌘⌫, as Empty Trash in Finder, it
    /// took ⌘⌫ too, in `make render`, before Delete… did.
    private var clearUnusedTagsButton: some View {
        Button(
            String(
                localized: "Clear Unused Tags…",
                comment:
                    "A button of the Cards window, beside All Tags: it asks whether to delete the tags no card carries."
            )
        ) {
            state.askToClearUnusedTags()
        }
    }

    /// Gives the table the keyboard back once Lucas's edit ended, saved or
    /// not. A save that failed goes on with the edit, and the keyboard stays
    /// in its fields.
    private func focusTableOnceEditEnds() {
        if state.editing == nil {
            isTableFocused = true
        }
    }

    /// Edit, which turns the detail of the selected card or capture into
    /// fields: ⌘L for either, since only one detail shows at a time.
    private var editButton: some View {
        Button(
            String(
                localized: "Edit",
                comment:
                    "A button of the Cards window that turns the card's or the capture's detail into fields to edit it."
            )
        ) {
            state.startEditing()
        }
        .keyboardShortcut("l", modifiers: .command)
        .help(
            Text(
                "Edit (⌘L)", comment: "The tooltip of the Cards window's button that edits the card or the capture."))
    }

    /// What Lucas can do with the capture or the card the detail shows, at
    /// its foot, always in sight.
    private var actionBar: some View {
        ActionBar {
            actionButtons
            Spacer()
        }
    }

    /// What the detail says when Lucas selected several cards: how many, with
    /// what he can do with all of them, one button under another, since four
    /// in a row don't fit the detail.
    private func selectionSummary(_ rows: [CardRow]) -> some View {
        ContentUnavailableView {
            Label(
                String(
                    localized: "\(rows.count) cards selected",
                    comment: "In the Cards window's detail, when Lucas selected several cards in the table."),
                systemImage: "rectangle.stack")
        } actions: {
            VStack {
                actionButtons
            }
        }
    }

    /// A button for each thing Lucas can do with what the detail shows, as
    /// the state offers them: Edit, Convert to Card, Flag…, Bury or Unbury,
    /// Turn On or Turn Off Both Ways, Change Deck…, Delete… and Discard…, in
    /// that order.
    /// Each button calls the state, which reads the
    /// selection as it is when Lucas acts, never as the button had it: SwiftUI
    /// keeps the action a keyboard shortcut had when its button first showed,
    /// so ⌘E would bury the cards selected back then.
    @ViewBuilder
    private var actionButtons: some View {
        let actions = state.actions
        if actions.contains(.edit) {
            editButton
        }
        if actions.contains(.convertToCard) {
            ConvertToCardButton {
                state.convertToCard()
            }
        }
        if actions.contains(.flag) {
            flagButton
        }
        if actions.contains(.bury) {
            buryButton
        }
        if actions.contains(.unbury) {
            unburyButton
        }
        if actions.contains(.turnOnBothWays) {
            turnOnBothWaysButton
        }
        if actions.contains(.turnOffBothWays) {
            turnOffBothWaysButton
        }
        if actions.contains(.changeDeck) {
            changeDeckButton
        }
        if actions.contains(.delete) {
            deleteButton
        }
        if actions.contains(.discard) {
            discardButton
        }
    }

    /// Flag…, which asks for Lucas's note on what to fix in the selected
    /// card.
    private var flagButton: some View {
        Button(
            String(
                localized: "Flag…",
                comment: "A button of the Cards window that flags the card, asking for a note on what to fix."
            )
        ) {
            state.askToFlag()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .help(Text("Flag… (⇧⌘L)", comment: "The tooltip of the Cards window's button that flags the card."))
    }

    /// Discard…, which asks whether to discard the capture selected in the
    /// inbox: ⌘⌫, as Delete… for cards, since a card's detail and a
    /// capture's never show together. While Lucas is in the search field, ⌘⌫
    /// is the field's, as in any text field: it deletes what he typed.
    private var discardButton: some View {
        Button(
            String(
                localized: "Discard…",
                comment: "A button of the Cards window that discards the capture, asking first."
            )
        ) {
            state.askToDiscard()
        }
        .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.deleteKey, modifiers: .command))
        .help(Text("Discard… (⌘⌫)", comment: "The tooltip of the Cards window's button that discards the capture."))
    }

    /// Delete…, which asks whether to delete the selected cards for good:
    /// ⌘⌫, as Discard… for a capture, since a card's detail and a capture's
    /// never show together. While Lucas is in the search field, ⌘⌫ is the
    /// field's, as in any text field: it deletes what he typed.
    private var deleteButton: some View {
        Button(
            String(
                localized: "Delete…",
                comment: "A button of the Cards window that deletes the selected cards for good, asking first."
            )
        ) {
            state.askToDelete()
        }
        .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.deleteKey, modifiers: .command))
        .help(Text("Delete… (⌘⌫)", comment: "The tooltip of the Cards window's button that deletes the cards."))
    }

    /// Bury, which takes the selected cards out of Lucas's reviews: ⌘E, as
    /// Unbury, since the two never show together.
    private var buryButton: some View {
        Button(
            String(
                localized: "Bury",
                comment: "A button of the Cards window that buries the selected cards: they leave Lucas's reviews."
            )
        ) {
            state.bury()
        }
        .keyboardShortcut("e", modifiers: .command)
        .help(Text("Bury (⌘E)", comment: "The tooltip of the Cards window's button that buries the cards."))
    }

    /// Unbury, which puts each selected card back where it was: ⌘E, as Bury.
    private var unburyButton: some View {
        Button(
            String(
                localized: "Unbury",
                comment:
                    "A button of the Cards window that unburies the selected cards: each goes back where it was."
            )
        ) {
            state.unbury()
        }
        .keyboardShortcut("e", modifiers: .command)
        .help(Text("Unbury (⌘E)", comment: "The tooltip of the Cards window's button that unburies the cards."))
    }

    /// Turn On Both Ways, which has the selected cards also reviewed back
    /// first: ⌘B, as Turn Off Both Ways, since the two never show together.
    private var turnOnBothWaysButton: some View {
        Button(
            String(
                localized: "Turn On Both Ways",
                comment:
                    "A button of the Cards window that has the selected cards also reviewed back first: their back, then their front."
            )
        ) {
            state.turnOnBothWays()
        }
        .keyboardShortcut("b", modifiers: .command)
        .help(
            Text(
                "Turn On Both Ways (⌘B)",
                comment: "The tooltip of the Cards window's button that turns Both ways on for the cards."))
    }

    /// Turn Off Both Ways, which has the selected cards reviewed front first
    /// alone again: ⌘B, as Turn On Both Ways.
    private var turnOffBothWaysButton: some View {
        Button(
            String(
                localized: "Turn Off Both Ways",
                comment:
                    "A button of the Cards window that has the selected cards reviewed front first only, no longer back first too."
            )
        ) {
            state.turnOffBothWays()
        }
        .keyboardShortcut("b", modifiers: .command)
        .help(
            Text(
                "Turn Off Both Ways (⌘B)",
                comment: "The tooltip of the Cards window's button that turns Both ways off for the cards."))
    }

    /// Change Deck…, which asks which deck the selected cards move to, in the
    /// Change Deck sheet: ⌘D, as Change Deck in Anki's browser.
    private var changeDeckButton: some View {
        Button(
            String(
                localized: "Change Deck…",
                comment: "A button of the Cards window that moves the selected cards to another deck, asking which."
            )
        ) {
            state.askToChangeDeck()
        }
        .keyboardShortcut("d", modifiers: .command)
        .help(
            Text(
                "Change Deck… (⌘D)",
                comment: "The tooltip of the Cards window's button that moves the cards to another deck."))
    }

    /// The title of the question before Lucas deletes the cards in `rows`:
    /// the card's front when it's one, or how many when they're several.
    private func deletionTitle(for rows: [CardRow]) -> Text {
        if rows.count == 1, let row = rows.first {
            Text(
                "Delete “\(row.card.front)”?",
                comment: "The title of the Cards window's question before it deletes a card, with its front.")
        } else {
            Text(
                "Delete \(rows.count) cards?",
                comment: "The title of the Cards window's question before it deletes several cards, with how many.")
        }
    }

    /// What the question before Lucas deletes the cards in `rows` says under
    /// its title: that their review logs go too, and for good.
    private func deletionMessage(for rows: [CardRow]) -> Text {
        if rows.count == 1 {
            Text(
                "Its review log goes too, and you can't bring it back.",
                comment: "Under the title of the Cards window's question before it deletes a card.")
        } else {
            Text(
                "Their review logs go too, and you can't bring them back.",
                comment: "Under the title of the Cards window's question before it deletes several cards.")
        }
    }
}

private typealias SidebarItem = CardsWindowState.SidebarItem

/// A deck's row in the sidebar, its title with how many of its cards are
/// due, grayed while its cards are out of Lucas's reviews, as it's set aside
/// on its own or sits inside a deck that is, with the deck's menu on a right
/// click; and the decks inside it under a disclosure triangle, open or closed
/// as the window remembers it.
private struct DeckBranch: View {
    let row: CardsWindowState.DeckRow
    @Binding var state: CardsWindowState

    var body: some View {
        if row.children.isEmpty {
            label
        } else {
            DisclosureGroup(
                isExpanded: Binding(get: { state.isDeckOpen(row.id) }, set: { state.setDeckOpen($0, row.id) })
            ) {
                ForEach(row.children) { child in
                    DeckBranch(row: child, state: $state)
                }
            } label: {
                label
            }
        }
    }

    /// Its own row, which choosing lists its cards.
    private var label: some View {
        Label(row.shownTitle, systemImage: CardGroup.deck(row.id).symbol)
            .badge(row.counts.due)
            .opacity(row.isGrayed ? 0.5 : 1)
            .tag(row.item)
            .contextMenu {
                if let menu = state.menu(forDeck: row.id) {
                    DeckMenuItems(menu: menu, state: $state)
                }
            }
    }
}

/// A type's row in the sidebar: its name, after a user type's emoji, when it
/// has one, or else the type's symbol.
private struct TypeRow: View {
    let group: CardGroup

    var body: some View {
        Label {
            Text(verbatim: group.title)
        } icon: {
            if case .type(.user(let type)) = group, let emoji = type.emoji {
                Text(verbatim: emoji)
            } else {
                Image(systemName: group.symbol)
            }
        }
    }
}

/// A pinned tag's row in the sidebar: its emoji, its own or else the tags'
/// it sits inside, before its whole name, and the tag symbol, filled with its
/// color, found the same way, when it has one. Its tooltip says its whole
/// name.
private struct TagRow: View {
    let tag: CardsWindowState.PinnedTagRow

    var body: some View {
        Label {
            Text(verbatim: tag.tag.title)
        } icon: {
            tag.tag.symbol
        }
        // Its whole name, which a narrow sidebar may cut short.
        .help(Text(verbatim: tag.tag.title))
    }
}

/// Where Lucas drops tags he drags from All Tags in the sidebar's All
/// Tags…, as wide as the list, highlighted while he holds them over it. They
/// come as text, as any text does, so it takes the tags the state knows he
/// drags, as they're dropped, before All Tags hears the drag ended.
private struct DraggedTags: ViewModifier {
    /// Whether Lucas drags tags from All Tags, which it highlights.
    let isDragging: Bool
    /// Takes the dragged tags, and says whether it took the drop.
    let drop: () -> Bool
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background(
                isTargeted && isDragging ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.clear),
                in: .rect(cornerRadius: 4)
            )
            .onDrop(of: [.utf8PlainText], isTargeted: $isTargeted) { _ in
                drop()
            }
    }
}

extension KeyEquivalent {
    /// The Delete key, ⌫, as macOS says it types: U+007F. A button's shortcut
    /// takes a key only as its event spells it, and SwiftUI's own `.delete` is
    /// U+0008, so ⌘⌫ never reached Discard with it in `make render`, which
    /// makes keys as the keyboard does.
    static let deleteKey = KeyEquivalent("\u{7F}")
}

extension View {
    /// The view as a place where Lucas drops tags he drags from All Tags,
    /// highlighted while he holds them over it, which `drop` takes, saying
    /// whether it took the drop.
    fileprivate func takingDraggedTags(while isDragging: Bool, _ drop: @escaping () -> Bool) -> some View {
        modifier(DraggedTags(isDragging: isDragging, drop: drop))
    }

    /// The view, dimmed and taking no clicks while `isWaiting`: the sidebar
    /// and the table, while Lucas edits a card or a capture.
    fileprivate func waiting(while isWaiting: Bool) -> some View {
        disabled(isWaiting)
            .opacity(isWaiting ? 0.5 : 1)
    }
}
