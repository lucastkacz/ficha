import FichaCore
import Foundation

/// The Cards window while it's open: what its sidebar chose, the first deck
/// of the queue new cards come from as it opens (`deckToOpenOn`), or nothing
/// while Your Decks lists none, what Lucas looks for and what he selected,
/// what the grid lists, a tile for each card
/// (`CardsWindowGrid.swift`), read from his cards with the scheduling
/// settings in Settings, and so what the detail shows, a card in words, with
/// its numbers under Details (`CardWording.swift`), and what Lucas can do
/// with it. It reads his cards whenever the window asks: once
/// the window listens for the reasons to read them again, and then for each
/// of them, the engine's changes, the passing of time, new scheduling
/// settings, and Ficha Dev moving the time. What Lucas does in the window goes through it too,
/// on what he selected as he acts: he edits the card the detail shows, the
/// window asks before it deletes or flags, it sets cards aside and puts them
/// back at once, turns Both ways on or off for
/// several cards at once, and moves them to the deck Lucas picks in the Change Deck sheet,
/// whose tree the sidebar lists too, where a deck's menu sets it aside,
/// prioritizes it, and gives it a color or asks for its emoji
/// (`CardsWindowDecks.swift`), and renames and deletes it, as dropping cards
/// or a deck on a deck there moves them (`CardsWindowDeckEdits.swift`), and it
/// records what couldn't be saved, for the window to say. A card shows its
/// deck alone: the database keeps each card's tags and type, which editing
/// it keeps, but the window shows neither (#538). It also holds the
/// form that creates cards while it's open, which `CardForm.swift` decides,
/// with its Deck field and the editor's (`CardsWindowDeckField.swift`), runs
/// the Import sheet, from a file's preview, with the decks its cards go to,
/// to what the import did (`CardsWindowImport.swift`), and the Export sheet,
/// from what it offers to export to the file it writes. As a deck at the top
/// of the tree comes in, made by New Deck… in the sidebar, with the deck it
/// names or one inside it, or by an import, it asks How fast? new cards
/// come, and where the deck goes in the queue new cards come from
/// (`HowFast.swift`), and each deck at the top of the tree says under its
/// title how far it is and when it's all met (`CardsWindowDecks.swift`). It
/// offers Ficha's decks the user hasn't added, each with its first card, which
/// Add Deck… adds after How fast? (`CardsWindowFichaDecks.swift`).
public struct CardsWindowState: Sendable {
    /// What the sidebar offers, one at a time: a deck's cards, or one of
    /// Ficha's decks.
    public enum SidebarItem: Sendable, Hashable {
        case cards(CardGroup)
        /// One of Ficha's decks the user hasn't added, which the window shows
        /// in the grid's and the detail's place, with Add Deck…:
        /// `CardsWindowFichaDecks.swift`.
        case fichaDeck(FichaDeck)
    }

    /// A section of the sidebar, as `sidebarSections` lists them, with what
    /// it offers.
    public enum SidebarSection: Sendable, Equatable, Identifiable {
        /// The Your Decks section: every deck as a tree, as `deckRows` lists
        /// them (`CardsWindowDecks.swift`).
        case decks([DeckRow])
        /// The Ficha's Decks section: the decks of Ficha's the user hasn't
        /// added, in `FichaDeck`'s order (`CardsWindowFichaDecks.swift`).
        case fichaDecks([FichaDeckFile])

        /// Which section it is, whatever it lists.
        public enum ID: Sendable, Hashable {
            case decks
            case fichaDecks
        }

        public var id: ID {
            switch self {
            case .decks: .decks
            case .fichaDecks: .fichaDecks
            }
        }

        /// What it offers, in its order.
        public var items: [SidebarItem] {
            switch self {
            case .decks(let rows): rows.flatMap(\.flattened).map(\.item)
            case .fichaDecks(let files): files.map(\.deck).map(SidebarItem.fichaDeck)
            }
        }
    }

    /// What the window lists between the sidebar and the detail: the cards of
    /// a deck, which the grid shows as tiles; no card while one of Ficha's
    /// decks shows in the grid's place, or while the sidebar chose nothing.
    public enum Listing: Sendable, Equatable {
        case cards([CardRow])
    }

    /// What the detail shows.
    public enum Detail: Sendable, Equatable {
        /// The selected card, whole, while it's the only one selected, with
        /// its review log, oldest first, or why it couldn't be read: nil only
        /// until it's read.
        case card(CardRow, reviewLog: Result<[ReviewLogRow], EngineError>?)
        /// The cards Lucas selected, when they're several, which the detail
        /// counts.
        case cards([CardRow])
        /// That no card is selected.
        case noCardSelected
    }

    /// What Lucas can do with what the detail shows.
    public enum Action: Sendable, Hashable {
        /// Edit the card, in fields that take the detail's place.
        case edit
        /// Move the cards to another deck, which the Change Deck sheet asks
        /// for: `CardsWindowDecks.swift`.
        case changeDeck
        /// Flag the card, with a note on what to fix.
        case flag
        /// Set the cards aside, out of the user's reviews until they're put
        /// back, each listed in its deck all the same (ADR 0041).
        case setAside
        /// Put the cards back, each where it stood before it was set aside.
        case putBack
        /// Turn Both ways on for the cards.
        case turnOnBothWays
        /// Turn Both ways off for the cards.
        case turnOffBothWays
        /// Delete the cards for good, asking first.
        case delete
    }

    /// What Lucas edits, in fields that take the detail's place, as it was
    /// when he started: a card.
    public enum Editing: Sendable, Equatable {
        case card(Card)
    }

    /// An item of the Color submenu in a deck's menu.
    public struct ColorItem: Sendable, Equatable {
        /// The color it gives the deck, or nil for None, which takes its own
        /// color away.
        public let color: TagColor?
        /// Whether it's ticked: the deck has this color of its own, or none
        /// for None.
        public let isTicked: Bool

        /// The Color submenu's items for what the menu acts on, which has
        /// `colors` of its own, one each: None, then Finder's seven colors in
        /// Finder's order, with the one they all have ticked, or None when
        /// none has one, and none ticked when they differ.
        static func items(forOwn colors: Set<TagColor?>) -> [ColorItem] {
            ([nil] + TagColor.allCases).map { ColorItem(color: $0, isTicked: colors == [$0]) }
        }
    }

    /// The fields a card is written in, each with a Deck field, whose New
    /// Deck… gives them the deck its sheet names.
    public enum CardFields: Sendable, Equatable {
        /// The card form's.
        case form
        /// The editor's, while Lucas edits a card.
        case editor
    }

    /// What the window asks before it acts, until Lucas confirms or cancels.
    public enum Question: Sendable, Equatable {
        /// Whether to delete these cards for good.
        case delete([CardRow])
        /// What needs fixing in this card, to flag it with that note.
        case flag(CardRow)
        /// Which deck these cards move to, in the Change Deck sheet:
        /// `CardsWindowDecks.swift`.
        case changeDeck(DeckChange)
        /// A new deck's whole name, in the New Deck sheet, for the Deck field
        /// of the fields New Deck… was chosen in, which takes it:
        /// `CardsWindowDeckField.swift`.
        case newDeck(CardFields)
        /// A new deck's whole name, in the New Deck sheet, after New Deck… in
        /// the sidebar, whose OK makes the deck: `CardsWindowDecks.swift`.
        case makeDeck
        /// Which emoji this deck gets, Default too, in the emoji sheet, whose
        /// field starts with the one it has of its own:
        /// `CardsWindowDecks.swift`.
        case deckEmoji(Deck)
        /// Which name this deck gets, in the rename sheet, whose field starts
        /// with its whole name, written with `::`:
        /// `CardsWindowDeckEdits.swift`.
        case renameDeck(Deck)
        /// Whether to delete this deck, with every deck inside it and every
        /// card in them, which does what the deletion says:
        /// `CardsWindowDeckEdits.swift`.
        case deleteDeck(DeckDeletion)
        /// How fast new cards come, and where a deck goes in the queue, as
        /// it comes in: `HowFast.swift`.
        case howFast(HowFast)
    }

    /// What OK in the emoji sheet makes of what its field holds.
    public enum EmojiEntry: Sendable, Equatable {
        /// One emoji, which the deck gets.
        case emoji(Emoji)
        /// Nothing but spaces, if any, which takes the deck's own emoji away.
        case removal
        /// Something that isn't one emoji, which OK refuses, and why, for
        /// the sheet to say.
        case refused(EngineError)

        /// The emoji OK gives, or nil for none: for a removal, and a refusal,
        /// which gives nothing.
        var emoji: Emoji? {
            guard case .emoji(let emoji) = self else { return nil }
            return emoji
        }

        /// Whether OK refuses it.
        var isRefused: Bool {
            guard case .refused = self else { return false }
            return true
        }
    }

    /// What OK in the rename sheet makes of what its field holds.
    public enum RenameEntry: Sendable, Equatable {
        /// The deck's new whole name, its levels cleaned up.
        case name(String)
        /// A name OK refuses, and why, for the sheet to say: a blank one, one
        /// inside the deck itself, or one whose top level is one of
        /// Default's.
        case refused(EngineError)
    }

    /// What Lucas did in the window that couldn't be saved, and why, which
    /// the window says until he closes it.
    public struct Failure: Sendable, Equatable {
        /// What he did.
        public let action: FailedAction
        /// Why the engine couldn't do it.
        public let error: EngineError
    }

    /// What Lucas did that couldn't be saved, on how many cards.
    public enum FailedAction: Sendable, Equatable {
        /// He saved the card he edited.
        case saveCard
        /// He added a card in the card form.
        case addCard
        /// He dragged or pasted something onto a side of the card he makes
        /// or edits, as its image.
        case putImage
        /// He dragged or pasted something onto a side of the card he makes
        /// or edits, as its sound.
        case putSound
        /// He flagged a card.
        case flag
        /// He moved this many cards to another deck, in the Change Deck
        /// sheet.
        case changeDeck(cardCount: Int)
        /// He set this many cards aside.
        case setCardsAside(cardCount: Int)
        /// He put this many cards back.
        case putCardsBack(cardCount: Int)
        /// He turned Both ways on for this many cards.
        case turnOnBothWays(cardCount: Int)
        /// He turned Both ways off for this many cards.
        case turnOffBothWays(cardCount: Int)
        /// He deleted this many cards.
        case delete(cardCount: Int)
        /// He set this deck aside, from its menu, by its whole name, or
        /// Default by `Deck.defaultName`.
        case setAside(deck: String)
        /// He undid setting this deck aside.
        case stopSettingAside(deck: String)
        /// He made this deck a priority deck, from its menu.
        case prioritize(deck: String)
        /// He made this deck no longer a priority deck.
        case stopPrioritizing(deck: String)
        /// He gave this deck a color, or took its own away, from its menu.
        case setDeckColor(deck: String)
        /// He gave this deck an emoji, or took its own away, in the emoji
        /// sheet.
        case setDeckEmoji(deck: String)
        /// He renamed this deck, in the rename sheet.
        case renameDeck(deck: String)
        /// He dragged this deck, in the sidebar, onto another or onto the
        /// Your Decks section's title, to move it.
        case moveDeck(deck: String)
        /// He deleted this deck, or chose Delete… on it, which counts what
        /// goes first.
        case deleteDeck(deck: String)
        /// He made a deck, in the New Deck sheet, after New Deck… in the
        /// sidebar.
        case makeDeck
        /// He chose Start in How fast?, which saves the pace and, when Put it
        /// first is ticked, puts the deck first in the queue.
        case startHowFast
        /// He exported cards, which couldn't be read or saved to the file.
        case export
        /// He chose Add Deck… on this one of Ficha's decks, which reads the
        /// queue for How fast?, or Start in How fast?, which adds it.
        case addFichaDeck(FichaDeck)
        /// He opened the window, which reads Ficha's decks from the app, and
        /// the file of this one couldn't be read.
        case readFichaDeck(FichaDeck)
    }

    /// What the sidebar chose: the deck the window opens on (`deckToOpenOn`),
    /// the first of the queue new cards come from, until Lucas picks another,
    /// or one of Ficha's decks; or nothing, while Your Decks
    /// lists no deck and Lucas picked nothing else, as before the window
    /// first reads the cards, and when a new user opens it.
    public internal(set) var sidebarItem: SidebarItem?
    /// What Lucas looks for in what the sidebar chose, from the search field.
    public internal(set) var search = ""
    /// The cards Lucas selected, which can include cards the grid no longer
    /// lists: the detail and the actions take only those it lists.
    public private(set) var selection: Set<CardRow.ID> = []
    /// The card Shift-click, and Shift with an arrow key, extend the grid's
    /// selection from: the last one clicked, alone or with ⌘, or moved to
    /// with an arrow key alone, or selected alone, and none once a click
    /// between the tiles selects none (`CardsWindowGrid.swift`).
    var anchorCard: CardRow.ID?
    /// The card the arrow keys move the grid's selection from: the last one
    /// clicked, moved to or selected alone, and none once a click between
    /// the tiles selects none.
    var currentCard: CardRow.ID?
    /// The card the grid scrolls to, until it has: the one Show Card or Add
    /// selected, or an arrow key moved to, which may be far down the grid.
    public internal(set) var cardToReveal: CardRow.ID?
    /// The review log of the card the detail shows, while it shows one: read
    /// with the cards, and again when Lucas selects another card.
    private var reviewLog: CardReviewLog?
    /// Whether the detail of a card opens Details, with FSRS's numbers and
    /// the review log, under the card in words: closed as the window opens,
    /// and kept from card to card while it's open (`CardWording.swift`).
    public internal(set) var isDetailsOpen = false
    /// What the window lists, or why it couldn't be read: nil until the
    /// window first reads Lucas's cards.
    public private(set) var listing: Result<Listing, EngineError>?
    /// Whether the window offers New Card and Import… in plain sight, in the
    /// grid's place: while the sidebar chose nothing, with no search, and the
    /// user has no cards at all, set-aside ones included, as when they just
    /// started.
    public private(set) var offersFirstCards = false
    /// Every deck the sidebar's Your Decks section lists, with what each has of
    /// its own and its counts, in the order a tree lists them, Default first
    /// while it holds cards or has a switch on: `CardsWindowDecks.swift`.
    public private(set) var decks: [CountedDeck] = []
    /// What the row of each of those decks at the top of the tree says under
    /// its title, by its whole name, read with them (#491).
    var deckLines: [String: DeckRow.Line] = [:]
    /// The decks at the top of the tree that hold cards in the user's
    /// reviews, by their whole names, in the order of the queue new cards
    /// come from, as `CardsInReviews.topDecksInQueueOrder` gives them, those
    /// met in full at their places, read with them, which the sidebar lists
    /// in that order (#491).
    var placedTopDecks: [String] = []
    /// The sidebar's decks Lucas closed, which each start open, and the
    /// window remembers while it's open.
    var closedDecks: Set<String> = []
    /// The row id of the last change to decks the window followed, or nil
    /// until it first reads the cards: it follows those after it each time
    /// it reads them again (`CardsWindowDeckEdits.swift`).
    var lastDeckChangeFollowed: Int64?
    /// The engine's time when the cards were read, which the tiles' marks,
    /// the detail's words for when a card is back and its Due rows count
    /// from.
    public private(set) var now: Date
    /// The scheduling settings in Settings, which the cards stand by, and
    /// which give the intervals of a card's review log.
    public private(set) var scheduler: Scheduler
    /// The active hours in Settings, this device's own, which the queue new
    /// cards come from counts today's new cards by, as the review panel's
    /// settings count them: the decks' finish dates and How fast?'s.
    public private(set) var activeHours: ActiveHours
    /// What Lucas edits, until he saves or cancels.
    public private(set) var editing: Editing?
    /// The form that creates cards, while it's open: `CardForm.swift`.
    public internal(set) var cardForm: CardForm?
    /// The deck the user last added a card to in the form, by its whole
    /// name, or Default's, which a new card's form starts in while the
    /// sidebar chose no deck (`CardsWindowDeckField.swift`): as the window
    /// opened with it, from this device's preferences, which the app keeps
    /// it in whenever it changes, until they add one.
    public internal(set) var lastDeckAddedTo: String
    /// The form Show Card set aside, as it was, until it's opened the same
    /// way again, or closes for good: `CardForm.swift`.
    var setAsideCardForm: CardForm?
    /// The cards' fronts, which the form's front is looked up in as it's
    /// typed, or why they couldn't be read: read with the cards while the
    /// form is open, and nil otherwise.
    var frontsInUse: Result<FrontsInUse, EngineError>?
    /// The images on the sides of the card the user edits, as Save would give
    /// them to it, while they edit one: `CardsWindowImages.swift`.
    public internal(set) var editedImages = SideImages()
    /// The images the window shows in the detail, the editor and the form,
    /// each read, or held until it's saved: `CardsWindowImages.swift`. The
    /// grid's tiles read theirs on their own (`TileImages`).
    public internal(set) var images = ShownImages()
    /// The sounds on the sides of the card the user edits, as Save would give
    /// them to it, while they edit one: `CardsWindowSounds.swift`.
    public internal(set) var editedSounds = SideSounds()
    /// The work converting a sound dropped or pasted on a side of the card
    /// the user edits, by side, while it converts.
    var editedSoundsComingIn: [CardSide: UUID] = [:]
    /// The sounds the window shows, in the detail, the editor and the form,
    /// each read with its length, or held until it's saved:
    /// `CardsWindowSounds.swift`.
    public internal(set) var sounds = ShownSounds()
    /// Whether the card the user edits goes both ways, as Save would set it,
    /// while they edit one: the card's own until they switch it.
    public private(set) var editedBothWays = false
    /// The deck of the card the user edits, as Save would move it to, by its
    /// whole name, or Default's, while they edit one: the card's own until
    /// they pick another in the Deck field, or name one with New Deck…
    /// (`CardsWindowDeckField.swift`).
    public internal(set) var editedDeck = Deck.defaultName
    /// The sound that plays, while one does, which the app's player plays:
    /// `CardsWindowSounds.swift`.
    public internal(set) var playingSound: PlayingSound?
    /// What the window asks before it acts, while it asks.
    public internal(set) var question: Question?
    /// What Lucas did that couldn't be saved, while the window says so.
    public private(set) var failure: Failure?
    /// The Import sheet, while it's open, which `CardsWindowImport.swift`
    /// runs.
    public internal(set) var importing: Importing?
    /// The Export sheet, while it's open, which `CardsWindowExport.swift`
    /// runs.
    public internal(set) var exporting: Exporting?
    /// Ficha's decks as the app read them from its bundle, in `FichaDeck`'s
    /// order: none until it gives them (`CardsWindowFichaDecks.swift`).
    var fichaDeckFiles: [FichaDeckFile] = []
    /// Those of them the user hasn't added, as last read, which the sidebar's
    /// Ficha's Decks section lists.
    var fichaDecksNotAdded: [FichaDeckFile] = []
    /// The one of Ficha's decks the review panel asked to add, while the
    /// window waits to ask How fast? for it: until the app gives it Ficha's
    /// decks, and until what's open closes
    /// (`askForTheFichaDeckAskedToAdd()`).
    var fichaDeckAskedToAdd: FichaDeck?
    /// Internal, for the window's parts in files of their own.
    let engine: Engine

    init(engine: Engine, scheduler: Scheduler, activeHours: ActiveHours, lastDeckAddedTo: String) {
        self.engine = engine
        self.scheduler = scheduler
        self.activeHours = activeHours
        self.lastDeckAddedTo = lastDeckAddedTo
        now = engine.now
    }

    /// The sidebar's sections, in its order: the decks as a tree, and Ficha's
    /// decks the user hasn't added, while there are some. No group of cards by
    /// where they stand, such as every card, the new ones or those set aside: a
    /// deck's cards show where each stands on its tile (ADR 0041). Nor by what
    /// labels them: the cards' tags and types stay in the database, which the
    /// sidebar no longer lists (#538).
    public var sidebarSections: [SidebarSection] {
        var sections: [SidebarSection] = [.decks(deckRows)]
        if !fichaDecksNotAdded.isEmpty {
            sections.append(.fichaDecks(fichaDecksNotAdded))
        }
        return sections
    }

    /// The deck the sidebar chose, by its whole name, or Default by
    /// `Deck.defaultName`, whose cards the grid lists, those of the decks
    /// inside it too: nil while it chose something else, or nothing.
    public var selectedDeck: String? {
        guard case .cards(.deck(let deck))? = sidebarItem else { return nil }
        return deck
    }

    /// Whether Lucas is looking for something, which narrows the grid: a
    /// search that isn't blank.
    public var hasSearch: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The selected cards the grid lists, which the detail shows and the
    /// actions act on.
    public var selectedRows: [CardRow] {
        guard case .success(.cards(let rows))? = listing else {
            return []
        }
        return rows.filter { selection.contains($0.id) }
    }

    /// The selected card the grid lists, while it's the only one.
    private var shownCard: CardRow? {
        let rows = selectedRows
        return rows.count == 1 ? rows.first : nil
    }

    /// What the detail shows: the selected cards the grid lists, or that
    /// none is selected.
    public var detail: Detail {
        let rows = selectedRows
        if rows.count > 1 {
            return .cards(rows)
        } else if let row = shownCard {
            // Never another card's review log.
            return .card(row, reviewLog: reviewLog?.cardID == row.id ? reviewLog?.rows : nil)
        }
        return .noCardSelected
    }

    /// What the user can do with what the detail shows: with one card, edit
    /// it, flag it while it's in the user's reviews, set it aside or put it
    /// back, move it to another deck, and delete it; with several, set them
    /// aside or put them back, turn Both ways on or off for them, move them
    /// to another deck, and delete them.
    public var actions: Set<Action> {
        switch detail {
        case .card(let row, _):
            return Self.actions(for: row.cardStanding).union([.edit, .changeDeck, .delete])
        case .cards(let rows):
            return setAsideOrPutBack(rows).union([Self.bothWaysAction(for: rows), .changeDeck, .delete])
        case .noCardSelected:
            return []
        }
    }

    /// What Lucas can do with one card standing where `standing` says, beyond
    /// editing and deleting it: flag it while it's in his reviews, as in the
    /// review panel; set it aside unless it's set aside on its own, which the
    /// engine keeps as its burial, also when it's set aside with its deck;
    /// and put it back when it's set aside on its own.
    private static func actions(for standing: CardStanding) -> Set<Action> {
        switch standing {
        case .inReviews, .setAside: [.flag, .setAside]
        case .flagged: [.setAside]
        case .buried: [.putBack]
        }
    }

    /// Set Aside, when every card in `rows` can be set aside, or Put Back,
    /// when every one can be put back, or neither, so that one action never
    /// does half its job.
    private func setAsideOrPutBack(_ rows: [CardRow]) -> Set<Action> {
        let actions = rows.map { Self.actions(for: $0.cardStanding) }
        return Set([Action.setAside, .putBack].filter { action in actions.allSatisfy { $0.contains(action) } })
    }

    /// Turn On Both Ways while any card in `rows` goes one way, so that one
    /// click sets them all alike, or Turn Off Both Ways once they all go both
    /// ways.
    private static func bothWaysAction(for rows: [CardRow]) -> Action {
        rows.allSatisfy(\.card.bothWays) ? .turnOffBothWays : .turnOnBothWays
    }

    /// Lists what Lucas chose in the sidebar.
    public mutating func choose(_ item: SidebarItem) {
        guard item != sidebarItem else { return }
        sidebarItem = item
        readAgain()
    }

    /// Narrows what the window lists to what mentions `search`. A blank
    /// search narrows nothing.
    public mutating func search(for search: String) {
        guard search != self.search else { return }
        self.search = search
        readAgain()
    }

    /// Selects the cards in `selection`, in a group of cards. A card selected
    /// alone is where a Shift-click and the arrow keys go from, as a click
    /// on it would make it, and none selected leaves them nothing to go
    /// from, so they start afresh (`CardsWindowGrid.swift`).
    public mutating func select(_ selection: Set<CardRow.ID>) {
        if selection.count == 1 {
            anchorCard = selection.first
            currentCard = selection.first
        } else if selection.isEmpty {
            anchorCard = nil
            currentCard = nil
        }
        guard selection != self.selection else { return }
        self.selection = selection
        readReviewLog()
    }

    /// Starts editing the card the detail shows, while Edit is offered.
    public mutating func startEditing() {
        guard actions.contains(.edit), case .card(let row, _) = detail else { return }
        editing = .card(row.card)
        editedImages = SideImages(front: row.card.frontImage, back: row.card.backImage)
        editedSounds = SideSounds(front: row.card.frontSound, back: row.card.backSound)
        editedBothWays = row.card.bothWays
        editedDeck = row.card.deck
        // The editor takes the detail's place, and its sound's.
        showFiles()
    }

    /// Turns Both ways on for the card the user edits, or off when `bothWays`
    /// is false, as Save will set it.
    public mutating func setBothWaysInEditor(_ bothWays: Bool) {
        guard case .card = editing else { return }
        editedBothWays = bothWays
    }

    /// Whether the fields `fields` are there: the card form's while it's
    /// open, and the editor's while Lucas edits a card.
    func areOpen(_ fields: CardFields) -> Bool {
        switch fields {
        case .form: cardForm != nil
        case .editor: editing != nil
        }
    }

    /// Saves the card the user edits with `content`, its images and sounds as
    /// `editedImages` and `editedSounds` hold them, going both ways as
    /// `editedBothWays` says, in the deck `editedDeck` says, and ends the
    /// edit, while Save is on, or records why it couldn't and goes on with
    /// it. The card keeps its progress and its review log, and its tags and
    /// its type as the database holds them, whatever `content` says, since
    /// the editor shows neither (#538); a flagged one is fixed, back in the
    /// reviews unless it's set aside. The detail shows it as saved at once,
    /// without waiting for the engine to say it changed.
    public mutating func saveCard(_ content: CardContent) {
        guard case .card(let card) = editing, canSaveCard else { return }
        let files = heldFiles(of: content)
        let bothWays = editedBothWays
        let deck = editedDeck
        let saved = perform(.saveCard) { engine throws(EngineError) in
            try engine.edit(card.id, keeping: files, with: content, deck: deck, bothWays: bothWays)
        }
        if saved {
            endEditing()
            readAgain()
            askForTheFichaDeckAskedToAdd()
        }
    }

    /// Ends the edit without saving it, nor the images and sounds the user
    /// put on it.
    public mutating func cancelEditing() {
        endEditing()
        showFiles()
        askForTheFichaDeckAskedToAdd()
    }

    /// Ends the edit, with the images and sounds it put on the card, and the
    /// sounds still converting for it, which are let go once they come in.
    private mutating func endEditing() {
        editing = nil
        editedImages = SideImages()
        editedSounds = SideSounds()
        editedSoundsComingIn = [:]
        editedBothWays = false
        editedDeck = Deck.defaultName
    }

    /// Asks what needs fixing in the card the detail shows, to flag it, while
    /// Flag is offered.
    public mutating func askToFlag() {
        guard actions.contains(.flag), case .card(let row, _) = detail else { return }
        question = .flag(row)
    }

    /// Flags the card the window asks about with Lucas's note on what to
    /// fix: it leaves his reviews and waits in its deck, with its flag on its
    /// tile (`Tile.Mark.flagged`) and its note in the detail, until it's
    /// fixed. When it can't, it records why and goes on asking, so the note
    /// he wrote stays.
    public mutating func flag(note: FlagNote) {
        guard case .flag(let row) = question else { return }
        let flagged = perform(.flag) { engine throws(EngineError) in try engine.flag(row.id, note: note) }
        if flagged {
            question = nil
            askForTheFichaDeckAskedToAdd()
        }
    }

    /// Sets the selected cards the window lists aside, all at once, while Set
    /// Aside is offered, or records why it couldn't: each leaves the user's
    /// reviews, flagged or not, until it's put back, and its deck still lists
    /// it, its tile dimmed (`Tile.Mark.setAside`). The engine buries them, as
    /// the database keeps a card set aside on its own, with no migration
    /// (ADR 0041).
    public mutating func setAside() {
        guard actions.contains(.setAside) else { return }
        let cardIDs = Set(selectedRows.map(\.id))
        perform(.setCardsAside(cardCount: cardIDs.count)) { engine throws(EngineError) in try engine.bury(cardIDs) }
    }

    /// Puts the selected cards the window lists back, all at once, while Put
    /// Back is offered, or records why it couldn't: each goes back where it
    /// stood, in the user's reviews with the progress it had, flagged when
    /// it has a flag, or set aside with its deck when that deck is, as the
    /// engine unburies it.
    public mutating func putBack() {
        guard actions.contains(.putBack) else { return }
        let cardIDs = Set(selectedRows.map(\.id))
        perform(.putCardsBack(cardCount: cardIDs.count)) { engine throws(EngineError) in try engine.unbury(cardIDs) }
    }

    /// Turns Both ways on for the selected cards the window lists, all at
    /// once, while Turn On Both Ways is offered, and reads them again, so
    /// that the window offers Turn Off at once; or records why it couldn't.
    public mutating func turnOnBothWays() {
        guard actions.contains(.turnOnBothWays) else { return }
        setBothWays(true)
    }

    /// Turns Both ways off for the selected cards the window lists, all at
    /// once, while Turn Off Both Ways is offered, and reads them again, so
    /// that the window offers Turn On at once; or records why it couldn't.
    public mutating func turnOffBothWays() {
        guard actions.contains(.turnOffBothWays) else { return }
        setBothWays(false)
    }

    /// Turns Both ways on or off for the selected cards the window lists, as
    /// `bothWays` says, and reads them again, or records why it couldn't.
    private mutating func setBothWays(_ bothWays: Bool) {
        let cardIDs = Set(selectedRows.map(\.id))
        let action: FailedAction =
            bothWays ? .turnOnBothWays(cardCount: cardIDs.count) : .turnOffBothWays(cardCount: cardIDs.count)
        let done = perform(action) { engine throws(EngineError) in try engine.setBothWays(bothWays, of: cardIDs) }
        if done {
            readAgain()
        }
    }

    /// Asks whether to delete the selected cards the window lists, while Delete
    /// is offered.
    public mutating func askToDelete() {
        guard actions.contains(.delete) else { return }
        question = .delete(selectedRows)
    }

    /// Deletes the cards in `rows` for good, which the window asked about and
    /// Lucas confirmed, all at once, or records why it couldn't. The dialog
    /// that asked hands `rows` back, since SwiftUI may close it, which drops
    /// the question, before its button acts.
    public mutating func delete(_ rows: [CardRow]) {
        question = nil
        let cardIDs = Set(rows.map(\.id))
        perform(.delete(cardCount: cardIDs.count)) { engine throws(EngineError) in try engine.delete(cardIDs) }
        askForTheFichaDeckAskedToAdd()
    }

    /// What OK in the emoji sheet makes of `text`, what its field holds: one
    /// emoji for the deck, none when the field is empty, or a refusal of
    /// anything else.
    public func emojiEntry(_ text: String) -> EmojiEntry {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .removal
        }
        do throws(EngineError) {
            return .emoji(try Emoji(text))
        } catch {
            return .refused(error)
        }
    }

    /// Chooses OK in the emoji sheet, whose field holds `text`: gives the
    /// deck the window asks about that emoji, or takes its emoji away when
    /// the field is empty, and reads the cards again, or records why it
    /// couldn't and goes on asking. While OK refuses `text`, it does nothing,
    /// and the sheet says why.
    public mutating func chooseEmoji(_ text: String) {
        let entry = emojiEntry(text)
        guard !entry.isRefused, case .deckEmoji(let deck) = question else { return }
        if setEmoji(entry.emoji, of: deck) {
            question = nil
            askForTheFichaDeckAskedToAdd()
        }
    }

    /// What OK in the rename sheet makes of `text`, what its field holds, for
    /// the deck the window asks about: the deck's new whole name, or a
    /// refusal of a blank name, one whose top level is one of Default's, or
    /// one inside the deck itself, as the engine refuses them. Nil while the
    /// window asks about no name.
    public func renameEntry(_ text: String) -> RenameEntry? {
        guard case .renameDeck(let deck) = question else { return nil }
        return deckNameEntry(text, renaming: deck.name)
    }

    /// Chooses OK in the rename sheet, whose field holds `text`: renames the
    /// deck the window asks about, and every deck inside it, as
    /// `Engine.renameDeck(_:to:)` does, and reads the cards again, the
    /// sidebar following the deck it chose to its new name; or records why
    /// it couldn't and goes on asking. While OK refuses `text`, it does
    /// nothing, and the sheet says why.
    public mutating func chooseNewName(_ text: String) {
        guard case .name(let name)? = renameEntry(text), case .renameDeck(let deck) = question else { return }
        if renameDeck(deck.name, to: name, as: .renameDeck(deck: deck.name)) {
            question = nil
            askForTheFichaDeckAskedToAdd()
        }
    }

    /// Drops what the window asks, which Lucas cancelled.
    public mutating func cancelQuestion() {
        question = nil
        askForTheFichaDeckAskedToAdd()
    }

    /// Clears what failed, once the window said so and Lucas closed it.
    public mutating func dismissFailure() {
        failure = nil
    }

    /// Does the engine's part of `action` with `work`, or records why it
    /// couldn't: whether it did.
    @discardableResult
    mutating func perform(_ action: FailedAction, _ work: (Engine) throws(EngineError) -> Void) -> Bool {
        do throws(EngineError) {
            try work(engine)
            return true
        } catch {
            record(error, for: action)
            return false
        }
    }

    /// Records that `action` couldn't be done, and why, which the window says
    /// until Lucas closes it.
    mutating func record(_ error: EngineError, for action: FailedAction) {
        failure = Failure(action: action, error: error)
    }

    /// Reads the decks, with what each one's row says under its title, and
    /// what the sidebar chose, as they are now, with `scheduler`, the
    /// settings in Settings, which may have changed since the last read, and
    /// the review log of the card the detail shows.
    /// It follows each deck renamed or deleted since it last read, whoever
    /// did it (`follow(_:)`). While the sidebar chose nothing, as the window
    /// opens, it chooses the deck it opens on (`deckToOpenOn`), as soon as
    /// Your Decks lists one. When the chosen deck is gone, as Default once its
    /// last card moved out, the sidebar goes back to that deck, or to nothing
    /// while Your Decks lists none. It finds which of
    /// Ficha's decks the user has added, as `Engine.hasAdded(_:)` says, and
    /// when the one the sidebar chose is added, by Start or meanwhile from
    /// another device, the sidebar chooses the deck, or the deck the window
    /// opens on while Your Decks doesn't list it.
    /// Then, while nothing's open, it asks How fast? for the one of Ficha's
    /// decks the review panel asked for meanwhile, which chooses it in the
    /// sidebar (`askForTheFichaDeckAskedToAdd()`). This is the app's read,
    /// as the cards change and every minute: the window's own operations
    /// read with `readAgain()`, which asks nothing, so the ask never comes
    /// partway through one, and each asks once it's over, all but Show Card,
    /// which leaves the window on the card it shows, so that this read asks.
    public mutating func read(with scheduler: Scheduler) {
        read(with: scheduler, activeHours: activeHours)
    }

    /// Reads the window as `read(with:)` does, with `activeHours` too,
    /// Settings', which may have changed since the last read.
    public mutating func read(with scheduler: Scheduler, activeHours: ActiveHours) {
        self.activeHours = activeHours
        self.scheduler = scheduler
        readAgain()
        askForTheFichaDeckAskedToAdd()
    }

    /// Reads the window as `read(with:)` does, with the settings it last
    /// read with, but asks nothing for one of Ficha's decks: how the
    /// window's own operations read the cards again, partway through, so
    /// that the sidebar stays where they leave it.
    mutating func readAgain() {
        now = engine.now
        offersFirstCards = false
        do throws(EngineError) {
            let deckChanges = try engine.deckChanges(after: lastDeckChangeFollowed)
            decks = try engine.countedDecks(with: scheduler)
            try readDeckLines()
            follow(deckChanges)
            if case .cards(let group) = sidebarItem, !offers(group) {
                sidebarItem = nil
            }
            fichaDecksNotAdded = try fichaDeckFiles.isEmpty ? [] : engine.fichaDecks(among: fichaDeckFiles)
            if case .fichaDeck(let deck) = sidebarItem, !fichaDecksNotAdded.contains(where: { $0.deck == deck }) {
                sidebarItem = listedDeck(deck.name) != nil ? .cards(.deck(deck.name)) : nil
            }
            if sidebarItem == nil {
                // As the window opens, and once what it chose is gone, as
                // soon as Your Decks lists a deck.
                sidebarItem = deckToOpenOn?.item
            }
            if case .cards(let group) = sidebarItem {
                listing = .success(.cards(try engine.cardRows(in: group, matching: search, with: scheduler)))
            } else {
                // One of Ficha's decks shows in the grid's place
                // (`shownFichaDeck`), and while the sidebar chose nothing,
                // New Card and Import… may.
                listing = .success(.cards([]))
                if sidebarItem == nil, !hasSearch {
                    offersFirstCards = try engine.cards().isEmpty
                }
            }
        } catch {
            listing = .failure(error)
        }
        readFrontsInUse()
        readReviewLog()
    }

    /// Whether the sidebar offers `group`, as last read: a deck while the
    /// Your Decks section lists it. It never offers every card, which only
    /// the engine's counts read.
    private func offers(_ group: CardGroup) -> Bool {
        switch group {
        case .deck(let deck): listedDeck(deck) != nil
        case .all: false
        }
    }

    /// Reads the review log of the card the detail shows, while it shows one,
    /// and the images and sounds the window shows.
    private mutating func readReviewLog() {
        showFiles()
        guard let row = shownCard else {
            reviewLog = nil
            return
        }
        reviewLog = CardReviewLog(
            cardID: row.id,
            rows: Result { () throws(EngineError) in try engine.reviewLogRows(of: row.id, with: scheduler) })
    }
}

/// A card's review log, as the Cards window's detail shows it under the
/// card's Details, or why it couldn't be read.
private struct CardReviewLog: Sendable {
    let cardID: Int64
    let rows: Result<[ReviewLogRow], EngineError>
}

extension Engine {
    /// Opens the Cards window, which chooses the deck it opens on, the first
    /// of the queue new cards come from, once it reads the cards, with
    /// nothing searched or selected, for Lucas's cards standing by
    /// `scheduler`, the settings in Settings, which it reads once the window
    /// asks, with `activeHours`, Settings' too, or Ficha's own while it's
    /// given none, remembering
    /// `lastDeckAddedTo`, the deck he last added a card to, as this device's
    /// preferences keep it: Default when they keep none.
    public func openCardsWindow(
        with scheduler: Scheduler, activeHours: ActiveHours = ReviewSettings.defaults.activeHours,
        lastDeckAddedTo: String = Deck.defaultName
    ) -> CardsWindowState {
        CardsWindowState(
            engine: self, scheduler: scheduler, activeHours: activeHours, lastDeckAddedTo: lastDeckAddedTo)
    }
}
