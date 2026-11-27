import FichaCore
import FichaData
import SwiftUI

/// The Cards window's content, in three panes as Mail lays out its own: a
/// sidebar to choose the inbox, a deck or one of Ficha's decks, a grid of
/// the chosen cards as tiles (`CardGrid.swift`), or a table with one row per
/// capture and flagged card in the inbox, narrowed by the toolbar's search
/// field, and the selected card or row whole beside it, with what Lucas can
/// do with it at its foot. The window opens on the first deck of the queue
/// new cards come from, the one Lucas is meeting, or else on the first deck
/// Your Decks lists, and on nothing while it lists none. The sidebar's Your
/// Decks section lists every deck as a tree, in the order the state lists them
/// (`CardsWindowDecks.swift`): Default first while it holds cards or has a
/// switch on, then those at the top of the tree with cards in Lucas's
/// reviews in the order of the queue new cards come from, a deck listed
/// first for its priority cards alone first and one met in full at its
/// place, then the rest alphabetically, and those set aside last; each with
/// how many of its cards are due, grayed while its cards are out of Lucas's
/// reviews, and with its emoji and color, and each at the top of the tree
/// with a line under its title, in up to two lines, of how far it is and when
/// it's all met (#491); a deck's context menu, and the Actions menu above the
/// grid while the sidebar chose it (`DeckMenu.swift`), set it aside or
/// prioritize it, give it a color and an emoji, rename it, in the rename sheet
/// (`RenameSheet.swift`), which moves it too, and delete it, with its cards,
/// asking first. A card shows its deck alone: the database keeps its tags and
/// its type, which the window shows nowhere (#538). Change
/// Deck… moves the selected cards to the deck Lucas picks in its sheet, or
/// names there with New Deck… (`ChangeDeckSheet.swift`), and so does dragging
/// them onto a deck in the sidebar, where a deck dragged onto another goes
/// inside it, or onto the Your Decks title to the top (`SidebarDrops.swift`).
/// The card form and the editor have a Deck field, whose New Deck… names a
/// deck in the New Deck sheet (`NewDeckSheet.swift`), which New Deck… in a
/// deck's menu or the Your Decks title's opens too, to make the deck. As a
/// deck comes in, made there or brought by an import, How fast? asks for the
/// pace and where the deck goes in the queue new cards come from
/// (`HowFastSheet.swift`). The sidebar's Ficha's Decks section, after Your
/// Decks, lists the decks that come with Ficha that Lucas hasn't added, each
/// with how many cards it brings, which the window reads from the app as it
/// opens: one chosen shows in the grid's place, with Add Deck…, which asks
/// How fast? before Start adds it, and its first card, front and back, in the
/// detail's (#458). The grid lists the cards in the order they came in. He
/// edits a card or a capture right there, in fields that take the detail's
/// place while the sidebar and the grid or the inbox wait. He selects several
/// tiles with ⌘ or Shift, as in the Finder, or all of them with Select All,
/// ⌘A, and then the detail says how many, with what he can do with all of
/// them. New Card in the toolbar, or ⌘N, and Convert to Card on a capture
/// open the card form, a sheet of its own (`CardFormSheet.swift`), Import…
/// in the toolbar opens the Import sheet (`ImportSheet.swift`), which imports
/// a text file of cards, and Export… opens the Export sheet (`ExportSheet.swift`),
/// which saves cards to one. `CardsWindowState` decides what the window lists,
/// shows, offers and asks, and what happens when Lucas acts, and the view
/// draws it. It reads the cards again whenever the engine says they changed,
/// from the app or the `ficha` CLI, when Lucas changes the scheduling
/// settings or the active hours, and every minute, since cards come due as
/// time passes, or at once when Ficha Dev's debug menu moves the time.
struct CardsView: View {
    let model: AppModel
    /// What the sidebar chose, what Lucas looks for and selected, and so what
    /// the grid lists, the detail shows and its actions offer, and what he
    /// edits, what the window asks and what failed.
    @State private var state: CardsWindowState
    @FocusState private var isSearchFocused: Bool
    /// The inbox's order: the latest added first, until Lucas clicks a
    /// column's header.
    @State private var inboxSortOrder = [InboxRowOrder(.added, order: .reverse)]
    /// Whether the grid, or the inbox's table, has the keyboard, which it
    /// gets back once Lucas saves or cancels an edit, for him to go on with
    /// the arrow keys.
    @FocusState private var isListingFocused: Bool
    /// Plays the sound the window says plays, in the form, the editor or the
    /// detail.
    @State private var player = SoundPlayer()

    /// The content for the user's cards in `model`, opening with `state` when
    /// it's given, as `make render` opens it partway through an import, and
    /// otherwise on the deck the state opens on, once it reads the cards.
    init(model: AppModel, state: CardsWindowState? = nil) {
        self.model = model
        _state = State(initialValue: state ?? model.openCardsWindow())
    }

    var body: some View {
        askingAboutDecks(panes)
            .creatingCards($state, failure: failure(overSheet: true))
            .changeDeckSheet($state, failure: failure(overSheet: true))
            .howFastSheet($state, failure: failure(overSheet: true))
            // The card form's opens over the form.
            .newDeckSheet(for: .editor, $state)
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
            .task {
                // Away from the main actor, since reading them takes a while:
                // nil when `make render` gives the window its own.
                if let read = await model.readFichaDecks() {
                    state.offerFichaDecks(read)
                }
            }
            // The review panel's "You've met them all" asks for one of
            // Ficha's decks as it opens the window, or while it's open.
            .onChange(of: model.fichaDeckToAdd, initial: true) {
                if let deck = model.fichaDeckToAdd {
                    model.fichaDeckToAdd = nil
                    state.askToAddFichaDeck(deck)
                }
            }
            .onChange(of: model.settings.scheduler) {
                readCards()
            }
            .onChange(of: model.settings.activeHours) {
                readCards()
            }
            .onChange(of: model.debugTools?.timeShift) {
                readCards()
            }
            .onChange(of: state.playingSound) {
                play(state.playingSound)
            }
            // This Mac's own, for the next window to start a new card there.
            .onChange(of: state.lastDeckAddedTo) {
                Preferences.lastDeckAddedTo = state.lastDeckAddedTo
            }
            .onDisappear {
                player.stop()
            }
    }

    /// The window's three panes, with the toolbar's search field, Import…
    /// and Export…, ⌘F, and the keys that change the card size, which only the
    /// detail's card or capture shows at. A pane's ideal width counts only as
    /// the window first opens, and only for a pane whose content is there by
    /// then, which is why the window opens with the cards already read
    /// (`AppModel.openCardsWindow()`): the middle pane opens wide enough for
    /// three tiles a row. The sidebar opens wide enough for the sample
    /// decks' names to read whole beside their counts, after their emoji, two
    /// levels down too, like Idiomas › Español › Rioplatense. The panes'
    /// least widths fit in the window's.
    private var panes: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 260, max: 280)
                .waiting(while: state.editing != nil)
        } content: {
            middlePane
                .navigationSplitViewColumnWidth(min: 380, ideal: 440)
                .waiting(while: state.editing != nil)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        }
        .searchable(text: searchText, placement: .toolbar)
        .searchFocused($isSearchFocused)
        .navigationTitle(String(localized: "Cards", comment: "The Cards window's title."))
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
            CardSizeKeys(model: model)
        }
    }

    /// `content` with Delete…'s question about a deck, which says what
    /// deleting it does, on this Mac and on Lucas's other devices, since the
    /// Cards window has no undo. Its button acts on what the dialog presents.
    private func askingAboutDecks(_ content: some View) -> some View {
        content
            .confirmationDialog(
                deckToDelete.map {
                    Text(
                        "Delete the deck “\(Deck.shownName($0.deck))”?",
                        comment:
                            "The title of the Cards window's question before it deletes a deck, with its whole name."
                    )
                } ?? Text(verbatim: ""),
                isPresented: Binding(get: { deckToDelete != nil }, set: { if !$0 { state.cancelQuestion() } }),
                titleVisibility: .visible,
                presenting: deckToDelete
            ) { deletion in
                Button(role: .destructive) {
                    state.deleteDeck(deletion)
                } label: {
                    Text("Delete", comment: "The button that deletes the deck the Cards window asks about.")
                }
            } message: { deletion in
                Text(verbatim: deckDeletionMessage(for: deletion))
            }
    }

    /// The deck the window asks whether to delete, with what that deletes on
    /// this Mac, while it asks.
    private var deckToDelete: DeckDeletion? {
        guard case .deleteDeck(let deletion) = state.question else { return nil }
        return deletion
    }

    /// What the question before Lucas deletes the deck of `deletion` says
    /// under its title, a sentence for each thing it does: the decks inside
    /// it that go too, and the cards in them, counted on this Mac, which go
    /// here and on his other devices, whether or not they sync, as he
    /// decided on 2026-10-31 (`DeckChanges.swift`); and that it can't be
    /// undone, though the daily backups hold them. The sentences follow one
    /// another as the String Catalog joins them (`joinedSentences(_:)`).
    private func deckDeletionMessage(for deletion: DeckDeletion) -> String {
        var sentences: [String] = []
        if !deletion.decksInside.isEmpty {
            sentences.append(
                String(
                    localized: "The \(deletion.decksInside.count) decks inside it go with it.",
                    comment: "In the Cards window's question before it deletes a deck: the decks inside it."))
        }
        sentences.append(
            String(
                localized:
                    "\(deletion.cards) cards go too, with their review logs, here and on your other devices.",
                comment: """
                    In the Cards window's question before it deletes a deck: the cards in it and in the decks inside \
                    it, counted on this Mac.
                    """))
        sentences.append(
            String(
                localized: "You can't undo this, but the daily backups, in Settings › Advanced, hold what it deletes.",
                comment: "The last sentence of the Cards window's question before it deletes a deck."))
        return joinedSentences(sentences)
    }

    /// `sentences`, which the question before Lucas deletes a deck says
    /// under its title, one after another, as the String Catalog's
    /// `deletion.next-sentence` joins them, with a space. Each sentence after
    /// the first comes with what goes before it, rather than the whole
    /// question so far going into the next join: Foundation wraps a text it
    /// puts into another in Unicode's directional isolates, and an isolate
    /// holding only isolates reads left to right, which put Arabic's
    /// sentences in the wrong order.
    private func joinedSentences(_ sentences: [String]) -> String {
        sentences.reduce(into: "") { text, sentence in
            text +=
                text.isEmpty
                ? sentence
                : String(
                    localized: "deletion.next-sentence", defaultValue: " \(sentence)",
                    comment: """
                        A sentence of the Cards window's question before it deletes a deck, after the one before it: \
                        with what the language writes between two sentences, a space in English.
                        """)
        }
    }

    /// Reads Lucas's cards, as they are now, with the scheduling settings and
    /// the active hours he set.
    private func readCards() {
        state.read(with: model.settings.scheduler, activeHours: model.settings.activeHours)
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

    /// The deck the window asks which emoji to give, while the emoji sheet
    /// asks.
    private var deckForEmoji: Deck? {
        guard case .deckEmoji(let deck) = state.question else { return nil }
        return deck
    }

    /// The deck the window asks which name to give, while the rename sheet
    /// asks.
    private var deckToRename: Deck? {
        guard case .renameDeck(let deck) = state.question else { return nil }
        return deck
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

    /// Where an alert says what failed: over the window, or over one of its
    /// sheets.
    private enum AlertPlace {
        case window
        case sheet
    }

    /// Where the alert shows now: over the flag sheet, the emoji sheet, the
    /// rename sheet, the Change Deck sheet, the card form, the Export sheet,
    /// How fast? or the New Deck sheet the sidebar opened while one is open,
    /// since the window's own alert can't show over its sheet; and over the
    /// window otherwise.
    private var alertPlace: AlertPlace {
        let isSheetOpen =
            cardToFlag != nil || deckForEmoji != nil || deckToRename != nil || state.deckChange != nil
            || state.cardForm != nil || state.exporting != nil || state.question == .makeDeck
            || state.howFast != nil
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
        case .setDeckColor(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't change the color of “\(Deck.shownName(deck))”",
                    comment: "An alert's title in the Cards window, after a color in a deck's menu, with the deck."),
                error: error)
        case .setDeckEmoji(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't change the emoji of “\(Deck.shownName(deck))”",
                    comment: "An alert's title in the Cards window's emoji sheet, after OK, with the deck."),
                error: error)
        case .renameDeck(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't rename “\(Deck.shownName(deck))”",
                    comment:
                        "An alert's title in the Cards window's rename sheet, after OK, with the deck's whole name."),
                error: error)
        case .moveDeck(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't move “\(Deck.shownName(deck))”",
                    comment: """
                        An alert's title in the Cards window, after dragging a deck in the sidebar onto another or \
                        onto the Your Decks section's title, with the deck's whole name.
                        """),
                error: error)
        case .deleteDeck(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't delete “\(Deck.shownName(deck))”",
                    comment: """
                        An alert's title in the Cards window, after Delete… in a deck's menu or its question, with \
                        the deck's whole name.
                        """),
                error: error)
        case .export:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't export the cards",
                    comment: "An alert's title in the Cards window, after Export… or over its Export sheet."),
                error: error)
        case .makeDeck:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't make the deck",
                    comment:
                        "An alert's title in the Cards window's New Deck sheet, after New Deck… in the sidebar and OK."
                ),
                error: error)
        case .startHowFast:
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't save the pace or the deck's place in the queue",
                    comment: "An alert's title over How fast?, the Cards window's sheet as a deck comes in, on Start."
                ),
                error: error)
        case .addFichaDeck(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't add “\(deck.name)”",
                    comment: """
                        An alert's title in the Cards window, after Add Deck… or How fast?'s Start on one of Ficha's \
                        decks, with its name.
                        """),
                error: error)
        case .readFichaDeck(let deck):
            return Failure(
                title: LocalizedStringResource(
                    "Couldn't read Ficha's deck “\(deck.name)”",
                    comment: """
                        An alert's title in the Cards window as it opens, when the file of one of the decks that \
                        come with Ficha couldn't be read, with the deck's name.
                        """),
                error: error)
        }
    }

    /// What Lucas chooses from, in the sections the state lists, in its
    /// order. One is chosen at a time: the deck the state opens on as the
    /// window opens, and none while Your Decks lists none.
    private var sidebar: some View {
        List(selection: chosenItem) {
            ForEach(state.sidebarSections) { section in
                sidebarSection(section)
            }
        }
        .sheet(isPresented: Binding(get: { deckForEmoji != nil }, set: { if !$0 { state.cancelQuestion() } })) {
            if let deck = deckForEmoji {
                EmojiSheet(deck: deck, failure: failure(overSheet: true)) { text in
                    state.emojiEntry(text)
                } choose: { text in
                    state.chooseEmoji(text)
                }
            }
        }
        .sheet(isPresented: Binding(get: { deckToRename != nil }, set: { if !$0 { state.cancelQuestion() } })) {
            if let deck = deckToRename {
                RenameSheet(deck: deck, failure: failure(overSheet: true)) { text in
                    state.renameEntry(text)
                } choose: { text in
                    state.chooseNewName(text)
                }
            }
        }
        .makeDeckSheet($state, failure: failure(overSheet: true))
    }

    /// The sidebar's section `section`: the inbox, with how many things wait
    /// in it, as the menu counts them; the decks as a tree, each parent open
    /// or closed as Lucas left it, each deck with how many of its cards are
    /// due; or Ficha's decks he hasn't added, each with how many cards it
    /// brings.
    @ViewBuilder
    private func sidebarSection(_ section: CardsWindowState.SidebarSection) -> some View {
        switch section {
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
                Text("Your Decks", comment: "A section of the Cards window's sidebar: the user's decks, as a tree.")
                    // A deck dropped here goes to the top.
                    .takingSidebarDrops { state.dropOnDecksTitle($0) }
                    .contextMenu {
                        NewDeckItem(state: $state)
                    }
            }
        case .fichaDecks(let files):
            Section {
                ForEach(files, id: \.deck) { file in
                    FichaDeckRow(file: file)
                        .tag(SidebarItem.fichaDeck(file.deck))
                }
            } header: {
                Text(
                    "Ficha's Decks",
                    comment: """
                        A section of the Cards window's sidebar, after Your Decks: the decks that come with Ficha, \
                        which the user hasn't added.
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

    /// What the middle pane says when `group`, or the search in it, brings
    /// no cards.
    @ViewBuilder
    private func noCards(in group: CardGroup) -> some View {
        if state.hasSearch {
            ContentUnavailableView.search(text: state.search)
        } else {
            ContentUnavailableView(group.emptyTitle, systemImage: group.symbol)
        }
    }

    /// What the middle pane says while the sidebar chose nothing, since Your
    /// Decks lists no deck: that the cards show up here, with New Card and
    /// Import… in plain sight, which do what the toolbar's do, while the
    /// state offers them.
    @ViewBuilder
    private var nothingChosen: some View {
        if state.hasSearch {
            ContentUnavailableView.search(text: state.search)
        } else {
            ContentUnavailableView {
                Label(
                    String(
                        localized: "No cards",
                        comment: "In the Cards window, while it has no deck to show, since the user has no cards."),
                    systemImage: "rectangle.portrait.on.rectangle.portrait")
            } description: {
                Text(
                    "The cards you create with New Card show up here, each in its deck.",
                    comment: "In the Cards window, while it has no deck to show, since the user has no cards.")
            } actions: {
                if state.offersFirstCards {
                    Button {
                        state.openNewCardForm()
                    } label: {
                        Text("New Card", comment: "A button in the Cards window while the user has no cards.")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        state.startImport()
                    } label: {
                        Text("Import…", comment: "A button in the Cards window while the user has no cards.")
                    }
                }
            }
        }
    }

    /// What the inbox's table says when the inbox, or the search in it,
    /// brings nothing.
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

    /// What the middle pane lists: what the state lists, or the one of
    /// Ficha's decks the sidebar chose, in its place.
    @ViewBuilder
    private var middlePane: some View {
        if let file = state.shownFichaDeck {
            fichaDeckHead(file)
        } else {
            listing
        }
    }

    /// One of Ficha's decks, in the grid's place while the sidebar chose it,
    /// as the mock draws it: its emoji and name, with "40 cards · one of
    /// Ficha's decks" under them, and Add Deck…, on Return while the search
    /// field doesn't have it, which asks How fast? for the deck before it
    /// comes in. The detail shows its first card.
    private func fichaDeckHead(_ file: FichaDeckFile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(verbatim: file.deck.emoji)
                    .font(.system(size: 32))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: file.deck.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(verbatim: CardsWindowState.HowFast.Line.fichaDeck(cardCount: file.cardCount).text)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                state.askToAddFichaDeck()
            } label: {
                Text(
                    "Add Deck…",
                    comment: """
                        A button of the Cards window, beside one of Ficha's decks the user hasn't added: it asks how \
                        fast new cards come, and Start adds the deck.
                        """)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(isSearchFocused ? nil : .defaultAction)
            .help(
                Text(
                    "Add Deck… (↩)",
                    comment: "The tooltip of the Cards window's button that adds one of Ficha's decks."))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// What the middle pane lists, as the state lists it: the cards of the
    /// deck the sidebar chose, in the grid, under the deck's Actions menu; or
    /// the inbox.
    @ViewBuilder
    private var listing: some View {
        switch state.listing {
        case .success(.cards(let rows)):
            VStack(spacing: 0) {
                if let menu = state.chosenDeckMenu {
                    DeckBar(menu: menu, state: $state)
                }
                if !rows.isEmpty {
                    CardGrid(state: $state, isFocused: $isListingFocused)
                } else if case .cards(let group)? = state.sidebarItem {
                    noCards(in: group)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    nothingChosen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case .success(.inbox(let rows)):
            inboxTable(rows)
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

    /// What waits in the inbox, one row each: the captures, the expansions,
    /// the follow-ups and the flagged cards, which Lucas selects one at a
    /// time.
    private func inboxTable(_ rows: [InboxRow]) -> some View {
        // Each column's header and widths, fitted to its texts in the app's
        // language.
        let fitted = InboxTableColumns(now: state.now)
        return Table(rows.sorted(using: inboxSortOrder), selection: selectedInInbox, sortOrder: $inboxSortOrder) {
            TableColumn(Text(fitted.text.header), sortUsing: InboxRowOrder(.text)) { row in
                if let cardRow = row.flaggedCard {
                    FrontCell(card: cardRow.card)
                } else {
                    TextAsItReads(row.text)
                        .lineLimit(1)
                }
            }
            // Narrows below its texts, the user's: `InboxTableColumns` says
            // why.
            .width(fitting: fitted.text)
            TableColumn(Text(fitted.kind.header), sortUsing: InboxRowOrder(.kind)) { row in
                Text(row.kindName)
            }
            .width(fitting: fitted.kind)
            TableColumn(Text(fitted.added.header), sortUsing: InboxRowOrder(.added)) { row in
                Text(row.addedAt.formatted(.tableDay))
            }
            .width(fitting: fitted.added)
        }
        .focused($isListingFocused)
        .overlay {
            if rows.isEmpty {
                emptyInbox
            }
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
                bothWays: state.editedBothWays, deck: state.editedDeck, decks: state.deckFieldChoices(.editor),
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
            } setDeck: { deck in
                state.setDeckInEditor(deck)
            } newDeck: {
                state.askForNewDeck(in: .editor)
            } save: { content in
                state.saveCard(content)
                focusListingOnceEditEnds()
            } cancel: {
                state.cancelEditing()
                focusListingOnceEditEnds()
            }
        case .capture(let capture):
            CaptureEditor(capture: capture, isSearching: isSearchFocused) { text, note, source in
                state.saveCapture(text: text, note: note, source: source)
                focusListingOnceEditEnds()
            } cancel: {
                state.cancelEditing()
                focusListingOnceEditEnds()
            }
        case nil:
            Group {
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
                        row: row, wording: state.wording(of: row), images: state.images, now: state.now,
                        reviewLog: reviewLog,
                        isDetailsOpen: Binding(get: { state.isDetailsOpen }, set: { state.setDetailsOpen($0) })
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
                    if let card = state.shownFichaDeck?.firstCard {
                        FichaDeckCard(card: card, images: state.images)
                    } else {
                        ContentUnavailableView("No card selected", systemImage: "rectangle.on.rectangle")
                    }
                }
            }
            .environment(\.cardSize, model.cardSize)
        }
    }

    /// Gives the grid, or the inbox's table, the keyboard back once Lucas's
    /// edit ended, saved or not. A save that failed goes on with the edit,
    /// and the keyboard stays in its fields.
    private func focusListingOnceEditEnds() {
        if state.editing == nil {
            isListingFocused = true
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
    /// its foot, always in sight, in a second line when the detail is too
    /// narrow for all of them in one, as in German.
    private var actionBar: some View {
        ActionBar {
            WrappingRow {
                actionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    comment: "In the Cards window's detail, when Lucas selected several cards in the grid."),
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

/// A deck's row in the sidebar, its title, after its emoji and its symbol in
/// its color, with how many of its cards are
/// due, grayed while its cards are out of Lucas's reviews, as it's set aside
/// on its own or sits inside a deck that is, with the deck's menu on a right
/// click, and, at the top of the tree, a line under its title that says how
/// far it is and when it's all met (#491); and the decks inside it under a
/// disclosure triangle, open or closed as the window remembers it. Lucas
/// drags it, unless it's Default, onto another deck's row, and drops cards
/// and decks on it, as the state takes them.
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

    /// Its own row, which choosing lists its cards: its emoji before its
    /// title, and its symbol in its color, its own or else the decks' it sits
    /// inside, and, for a deck at the
    /// top of the tree, its line under its title, smaller and secondary, on
    /// up to two lines.
    private var label: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.shownTitle)
                if let line = row.line {
                    // Its finish date is what the line is for: a second line,
                    // not an ellipsis, in a narrow sidebar.
                    Text(verbatim: line.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            row.deck.symbol
        }
        .badge(row.counts.due)
        .opacity(row.isGrayed ? 0.5 : 1)
        .takingSidebarDrops { state.drop($0, onDeck: row.id) }
        .dragging(row.isDraggable ? .deck(row.id) : nil)
        .tag(row.item)
        .contextMenu {
            if let menu = state.menu(forDeck: row.id) {
                DeckMenuItems(menu: menu, state: $state)
            }
        }
    }
}

extension CardsWindowState.DeckRow.Line {
    /// What a deck's row says under its title in the sidebar, as the state
    /// words it, and as the mock's `deckStatus` does: "9 of 14 · on track for
    /// early December", "Next · on track for mid-December", "Met them all ·
    /// 14 cards in 9 days".
    var text: String {
        switch self {
        case .noCards:
            Deck.noCardsYet
        case .setAside(let met, let total):
            String(
                localized: "Set aside · \(met) of \(total) met",
                comment: "Under a set-aside deck's name in the Cards window's sidebar: how many of its cards are met.")
        case .metThemAll(let cards, let days?):
            String(
                localized: "Met them all · \(cards) cards in \(days) days",
                comment: """
                    Under a deck's name in the Cards window's sidebar: every card of the deck is met, with how many \
                    cards it has, and in how many days, from the day its first card came in to the day its last was \
                    met.
                    """)
        case .metThemAll(_, nil):
            String(
                localized: "Met them all",
                comment: "Under a deck's name in the Cards window's sidebar: every card of the deck is met.")
        case .first(let met, let total, let finish):
            String(
                localized: "\(met) of \(total) · on track for \(finish.text)",
                comment: """
                    Under the name of the deck new cards come from now, in the Cards window's sidebar: how many of \
                    its cards are met, and when they'll all be.
                    """)
        case .next(let finish):
            String(
                localized: "Next · on track for \(finish.text)",
                comment: """
                    Under the name of a deck that waits its turn in the queue of new cards, in the Cards window's \
                    sidebar: when its cards will all be met.
                    """)
        case .progress(let met, let total):
            String(
                localized: "\(met) of \(total)",
                comment: "Under a deck's name in the Cards window's sidebar: how many of its cards are met.")
        }
    }
}

/// The row of one of Ficha's decks in the sidebar's Ficha's Decks section:
/// its emoji before its name, and the deck symbol, as a deck's row in Your
/// Decks, with how many cards it brings under its name, smaller and secondary.
private struct FichaDeckRow: View {
    let file: FichaDeckFile

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(file.deck.emoji) \(file.deck.name)")
                Text(
                    "\(file.cardCount) cards",
                    comment: """
                        Under the name of one of Ficha's decks in the Cards window's sidebar: how many cards it \
                        brings.
                        """
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: CardGroup.deck(file.deck.name).symbol)
        }
    }
}

/// The first card of one of Ficha's decks, in the detail's place while the
/// window shows the deck, as the mock draws it, in a box of its own: its
/// front, its image above its text when it has both, then a line, and its
/// back the same way, at the card size.
private struct FichaDeckCard: View {
    let card: CardContent
    /// The images the window shows, the card's among them.
    let images: ShownImages
    @Environment(\.cardSize) private var cardSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let image = card.frontImage {
                    SideImage(image: images[image], maximumHeight: cardSize.scaled(320))
                }
                if !card.front.isEmpty {
                    TextAsItReads(card.front)
                        .cardFont(.title3)
                }
                Divider()
                if let image = card.backImage {
                    SideImage(image: images[image], maximumHeight: cardSize.scaled(320))
                }
                TextAsItReads(card.back)
                    .cardFont(.body)
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    /// The view, dimmed and taking no clicks while `isWaiting`: the sidebar
    /// and the middle pane, while Lucas edits a card or a capture.
    fileprivate func waiting(while isWaiting: Bool) -> some View {
        disabled(isWaiting)
            .opacity(isWaiting ? 0.5 : 1)
    }
}
