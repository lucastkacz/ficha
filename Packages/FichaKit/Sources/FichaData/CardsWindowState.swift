import FichaCore
import Foundation

/// The Cards window while it's open: what its sidebar chose, what Lucas looks
/// for and what he selected, what the table lists, read from his cards on the
/// ladder he set in Settings, and so what the detail shows and what Lucas can
/// do with it. It reads his cards whenever the window asks: once the window
/// listens for the reasons to read them again, and then for each of them, the
/// engine's changes, the passing of time, a new ladder in Settings, and Ficha
/// Dev moving the time. What Lucas does in the window goes through it too,
/// on what he selected as he acts: he edits the card or the capture the
/// detail shows, the window asks before it discards, deletes or flags, it
/// buries and unburies at once, and turns Both ways on or off for several
/// cards at once, as it sets a tag aside or gives it a color
/// from the tag's context menu, it asks which emoji the tag gets and which
/// name, and moves a tag Lucas drags onto another or onto the Tags section's
/// title (`CardsWindowTags.swift`), it makes, renames, gives an emoji to and
/// deletes card types of the user's own (`CardsWindowTypes.swift`), and it
/// records what couldn't be saved, for the window to say. It also holds the
/// form that creates cards while it's open, which `CardForm.swift` decides,
/// runs the Import sheet, from a file's preview to what the import did, and
/// the Export sheet, from what it offers to export to the file it writes.
public struct CardsWindowState: Sendable {
    /// What the sidebar offers, one at a time: a group of cards, or the
    /// inbox.
    public enum SidebarItem: Sendable, Hashable {
        case cards(CardGroup)
        case inbox
    }

    /// What the table lists: the cards of a group, or what waits in the
    /// inbox.
    public enum Listing: Sendable, Equatable {
        case cards([CardRow])
        case inbox([InboxRow])
    }

    /// What the detail shows.
    public enum Detail: Sendable, Equatable {
        /// The capture selected in the inbox, whole.
        case capture(Capture)
        /// The expansion selected in the inbox, whole, with the card it
        /// expands.
        case expansion(Expansion)
        /// The follow-up selected in the inbox, whole, with the card it
        /// follows up.
        case followUp(FollowUp)
        /// The selected card, whole, while it's the only one selected, with
        /// its review log, oldest first, or why it couldn't be read: nil only
        /// until it's read.
        case card(CardRow, reviewLog: Result<[ReviewLogRow], EngineError>?)
        /// The cards Lucas selected, when they're several, which the detail
        /// counts.
        case cards([CardRow])
        /// That nothing in the inbox is selected.
        case nothingSelectedInInbox
        /// That no card is selected.
        case noCardSelected
    }

    /// What Lucas can do with what the detail shows.
    public enum Action: Sendable, Hashable {
        /// Edit the card or the capture, in fields that take the detail's
        /// place.
        case edit
        /// Turn the capture into cards, in the card form opened from it.
        case convertToCard
        /// Flag the card, with a note on what to fix.
        case flag
        /// Bury the cards.
        case bury
        /// Unbury the cards.
        case unbury
        /// Turn Both ways on for the cards.
        case turnOnBothWays
        /// Turn Both ways off for the cards.
        case turnOffBothWays
        /// Delete the cards for good, asking first.
        case delete
        /// Discard the capture, asking first.
        case discard
    }

    /// What Lucas edits, in fields that take the detail's place, as it was
    /// when he started: a card, or a capture in the inbox.
    public enum Editing: Sendable, Equatable {
        case card(Card)
        case capture(Capture)
    }

    /// What the context menu of a tag in the sidebar offers.
    public struct TagMenu: Sendable, Equatable {
        /// Whether Set Aside is ticked: the tag is set aside, and choosing it
        /// again undoes it.
        public let isSetAsideTicked: Bool
        /// The Color submenu's items: None, then Finder's seven colors in
        /// Finder's order, with the tag's own ticked, or None when it has
        /// none.
        public let colorItems: [ColorItem]
    }

    /// An item of the Color submenu in a tag's context menu.
    public struct ColorItem: Sendable, Equatable {
        /// The color it gives the tag, or nil for None, which takes its color
        /// away.
        public let color: TagColor?
        /// Whether it's ticked: the tag has this color, or none for None.
        public let isTicked: Bool
    }

    /// What the window asks before it acts, until Lucas confirms or cancels.
    public enum Question: Sendable, Equatable {
        /// Whether to discard this capture in the inbox.
        case discard(Capture)
        /// Whether to delete these cards for good.
        case delete([CardRow])
        /// What needs fixing in this card, to flag it with that note.
        case flag(CardRow)
        /// Which emoji this tag gets, in the emoji sheet, whose field starts
        /// with the one it has.
        case emoji(CardTag)
        /// Which name this tag gets, in the rename sheet, whose field starts
        /// with its whole name, written with `::`: `CardsWindowTags.swift`.
        case renameTag(CardTag)
        /// A new type's name and emoji, in the New Type sheet, for the type
        /// picker New Type… was chosen in, which takes it:
        /// `CardsWindowTypes.swift`.
        case newType(TypePicker)
        /// Which name this user type gets, in the rename sheet, whose field
        /// starts with its name.
        case renameType(UserType)
        /// Which emoji this user type gets, in the emoji sheet, whose field
        /// starts with the one it has.
        case typeEmoji(UserType)
        /// Whether to delete this user type, which this many cards have,
        /// buried ones too.
        case deleteType(UserType, cardCount: Int)
    }

    /// What OK in the emoji sheet, or in the New Type sheet, makes of what an
    /// emoji field holds.
    public enum EmojiEntry: Sendable, Equatable {
        /// One emoji, which the tag or the user type gets.
        case emoji(Emoji)
        /// Nothing but spaces, if any, which takes the tag's or the user
        /// type's emoji away, or makes the type with none.
        case removal
        /// Something that isn't one emoji, which OK refuses, and why, for
        /// the sheet to say.
        case refused(EngineError)
    }

    /// What OK in the rename sheet, or the New Type sheet's name, makes of
    /// what the name field holds.
    public enum RenameEntry: Sendable, Equatable {
        /// The tag's new whole name, its levels cleaned up, or the type's
        /// name, without the spaces around it.
        case name(String)
        /// A name OK refuses, and why, for the sheet to say: a blank one, or
        /// one inside the tag itself; or a type's name of one of the four
        /// Ficha comes with, or another user type's.
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
        /// He saved the capture he edited.
        case saveCapture
        /// He discarded a capture.
        case discard
        /// He added a card in the card form.
        case addCard
        /// He closed the card form opened from a capture, after adding cards
        /// from it, which approves the capture.
        case approveCapture
        /// He dragged or pasted something onto a side of the card he makes
        /// or edits, as its image.
        case putImage
        /// He dragged or pasted something onto a side of the card he makes
        /// or edits, as its sound.
        case putSound
        /// He flagged a card.
        case flag
        /// He buried this many cards.
        case bury(cardCount: Int)
        /// He unburied this many cards.
        case unbury(cardCount: Int)
        /// He turned Both ways on for this many cards.
        case turnOnBothWays(cardCount: Int)
        /// He turned Both ways off for this many cards.
        case turnOffBothWays(cardCount: Int)
        /// He deleted this many cards.
        case delete(cardCount: Int)
        /// He set this tag aside.
        case setAside(tag: String)
        /// He undid setting this tag aside.
        case stopSettingAside(tag: String)
        /// He gave this tag a color, or took its color away.
        case setColor(tag: String)
        /// He gave this tag an emoji, or took its emoji away.
        case setEmoji(tag: String)
        /// He renamed this tag, in the rename sheet.
        case rename(tag: String)
        /// He dragged this tag onto another, or onto the Tags section's
        /// title, to move it.
        case move(tag: String)
        /// He made a type, in the New Type sheet.
        case makeType
        /// He renamed the user type with this name, in the rename sheet.
        case renameType(name: String)
        /// He gave the user type with this name an emoji, or took its emoji
        /// away, in the emoji sheet.
        case setTypeEmoji(name: String)
        /// He deleted the user type with this name, or chose Delete… on it,
        /// which counts its cards first.
        case deleteType(name: String)
        /// He exported cards, which couldn't be read or saved to the file.
        case export
    }

    /// What the sidebar chose: All cards, until Lucas picks another group or
    /// the inbox.
    public internal(set) var sidebarItem = SidebarItem.cards(.all)
    /// What Lucas looks for in what the sidebar chose, from the search field.
    public private(set) var search = ""
    /// The cards Lucas selected, which can include cards the table no longer
    /// lists: the detail and the actions take only those it lists.
    public private(set) var selection: Set<CardRow.ID> = []
    /// The row Lucas selected in the inbox, one at a time, which the table
    /// may no longer list, as with the cards.
    public private(set) var inboxSelection: InboxRow.ID?
    /// The card the table scrolls to, until it has: the one Show Card
    /// selected, which may be far down the list.
    public internal(set) var cardToReveal: CardRow.ID?
    /// The review log of the card the detail shows, while it shows one: read
    /// with the cards, and again when Lucas selects another card.
    private var reviewLog: CardReviewLog?
    /// What the table lists, or why it couldn't be read: nil until the window
    /// first reads Lucas's cards.
    public private(set) var listing: Result<Listing, EngineError>?
    /// The tags the sidebar offers, with what each has of its own and takes
    /// from the tags it sits inside: those of the cards that aren't buried,
    /// with every tag they sit inside, and the set-aside ones, in the order a
    /// tree lists them, in either section.
    public private(set) var tags: [CardTag] = []
    /// The sidebar's Tags section: the tags it offers that aren't set aside,
    /// neither on their own nor inside a tag that is, as a tree:
    /// `CardsWindowTags.swift`.
    public private(set) var tagsSection: [SidebarTag] = []
    /// The sidebar's Set Aside section, below Tags: each set-aside tag with
    /// every tag inside it, as a tree: `CardsWindowTags.swift`.
    public private(set) var setAsideSection: [SidebarTag] = []
    /// The type groups the sidebar offers: one for each of the four types
    /// Ficha comes with, then one for each of the user's types, in
    /// alphabetical order, and No Type after them while a card that isn't
    /// buried has no type.
    public private(set) var typeGroups = CardType.builtIn.map(CardGroup.type)
    /// The engine's time when the cards were read, which the Due and
    /// Back-first due columns count from.
    public private(set) var now: Date
    /// The ladder Lucas set in Settings, which the cards stand on, and whose
    /// steps a card's review log spans.
    public private(set) var ladder: Ladder
    /// What Lucas edits, until he saves or cancels.
    public private(set) var editing: Editing?
    /// The form that creates cards, while it's open: `CardForm.swift`.
    public internal(set) var cardForm: CardForm?
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
    /// The images the window shows, in the detail, the editor and the form,
    /// each read, or held until it's saved: `CardsWindowImages.swift`.
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
    /// The type of the card the user edits, as Save would give it, while they
    /// edit one: the card's own until they pick another, or make one with New
    /// Type… (`CardsWindowTypes.swift`).
    public internal(set) var editedType: CardType?
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
    /// Internal, for the window's parts in files of their own.
    let engine: Engine

    init(engine: Engine, ladder: Ladder) {
        self.engine = engine
        self.ladder = ladder
        now = engine.now
    }

    /// Whether Lucas is looking for something, which narrows the table: a
    /// search that isn't blank.
    public var hasSearch: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The selected cards the table lists, which the detail shows and the
    /// actions act on: those Lucas selected in a group of cards, or the
    /// flagged card he selected in the inbox.
    public var selectedRows: [CardRow] {
        switch listing {
        case .success(.cards(let rows)):
            rows.filter { selection.contains($0.id) }
        case .success(.inbox):
            selectedInboxRow?.flaggedCard.map { [$0] } ?? []
        case .failure, nil:
            []
        }
    }

    /// The row Lucas selected in the inbox, while the table lists it.
    private var selectedInboxRow: InboxRow? {
        guard case .success(.inbox(let rows))? = listing else {
            return nil
        }
        return rows.first { $0.id == inboxSelection }
    }

    /// The capture the detail shows, on its own, as an expansion or as a
    /// follow-up.
    private var shownCapture: Capture? {
        switch detail {
        case .capture(let capture):
            capture
        case .expansion(let expansion):
            expansion.capture
        case .followUp(let followUp):
            followUp.capture
        case .card, .cards, .nothingSelectedInInbox, .noCardSelected:
            nil
        }
    }

    /// The selected card the table lists, while it's the only one.
    private var shownCard: CardRow? {
        let rows = selectedRows
        return rows.count == 1 ? rows.first : nil
    }

    /// What the detail shows: the capture, the expansion or the follow-up
    /// selected in the inbox, the selected cards the table lists, or that
    /// nothing is selected.
    public var detail: Detail {
        switch selectedInboxRow?.item {
        case .capture(let capture):
            return .capture(capture)
        case .expansion(let expansion):
            return .expansion(expansion)
        case .followUp(let followUp):
            return .followUp(followUp)
        case .flaggedCard, nil:
            // A flagged card shows as a card, below.
            break
        }
        let rows = selectedRows
        if rows.count > 1 {
            return .cards(rows)
        } else if let row = shownCard {
            // Never another card's review log.
            return .card(row, reviewLog: reviewLog?.cardID == row.id ? reviewLog?.rows : nil)
        } else if case .inbox = sidebarItem {
            return .nothingSelectedInInbox
        } else {
            return .noCardSelected
        }
    }

    /// What the user can do with what the detail shows: with a capture or a
    /// follow-up, edit it, convert it to cards and discard it; with an
    /// expansion, edit it and discard it; with one card, edit it, flag it
    /// while it's in the user's reviews, bury or unbury it, and delete it;
    /// with several, bury or unbury them, turn Both ways on or off for them,
    /// and delete them.
    public var actions: Set<Action> {
        switch detail {
        case .capture, .followUp:
            return [.edit, .convertToCard, .discard]
        case .expansion:
            return [.edit, .discard]
        case .card(let row, _):
            return Self.actions(for: row.cardStanding).union([.edit, .delete])
        case .cards(let rows):
            return buryOrUnbury(rows).union([Self.bothWaysAction(for: rows), .delete])
        case .nothingSelectedInInbox, .noCardSelected:
            return []
        }
    }

    /// What Lucas can do with one card standing where `standing` says, beyond
    /// editing and deleting it: flag it while it's in his reviews, as in the
    /// review panel, bury it unless it's buried, and unbury it when it is.
    private static func actions(for standing: CardStanding) -> Set<Action> {
        switch standing {
        case .inReviews, .setAside: [.flag, .bury]
        case .inInbox: [.bury]
        case .buried: [.unbury]
        }
    }

    /// Bury, when every card in `rows` can be buried, or Unbury, when every
    /// one can be unburied, or neither, so that one action never does half
    /// its job.
    private func buryOrUnbury(_ rows: [CardRow]) -> Set<Action> {
        let actions = rows.map { Self.actions(for: $0.cardStanding) }
        return Set([Action.bury, .unbury].filter { action in actions.allSatisfy { $0.contains(action) } })
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
        read(on: ladder)
    }

    /// Narrows what the table lists to what mentions `search`. A blank search
    /// narrows nothing.
    public mutating func search(for search: String) {
        guard search != self.search else { return }
        self.search = search
        read(on: ladder)
    }

    /// Selects the cards in `selection`, in a group of cards.
    public mutating func select(_ selection: Set<CardRow.ID>) {
        guard selection != self.selection else { return }
        self.selection = selection
        readReviewLog()
    }

    /// Selects the row with `id` in the inbox, or none.
    public mutating func selectInInbox(_ id: InboxRow.ID?) {
        guard id != inboxSelection else { return }
        inboxSelection = id
        readReviewLog()
    }

    /// Starts editing the card or the capture the detail shows, while Edit is
    /// offered.
    public mutating func startEditing() {
        guard actions.contains(.edit) else { return }
        if let capture = shownCapture {
            editing = .capture(capture)
        } else if case .card(let row, _) = detail {
            editing = .card(row.card)
            editedImages = SideImages(front: row.card.frontImage, back: row.card.backImage)
            editedSounds = SideSounds(front: row.card.frontSound, back: row.card.backSound)
            editedBothWays = row.card.bothWays
            editedType = row.card.type
            // The editor takes the detail's place, and its sound's.
            showFiles()
        }
    }

    /// Turns Both ways on for the card the user edits, or off when `bothWays`
    /// is false, as Save will set it.
    public mutating func setBothWaysInEditor(_ bothWays: Bool) {
        guard case .card = editing else { return }
        editedBothWays = bothWays
    }

    /// Saves the card the user edits with `content`, its images and sounds as
    /// `editedImages` and `editedSounds` hold them, going both ways as
    /// `editedBothWays` says, and ends the edit, while Save is on, or records
    /// why it couldn't and goes on with it. The card keeps its step and its
    /// review log, and a flagged one is fixed, back in the reviews unless
    /// it's buried. The detail shows it as saved at once, without waiting for
    /// the engine to say it changed.
    public mutating func saveCard(_ content: CardContent) {
        guard case .card(let card) = editing, canSaveCard else { return }
        let files = heldFiles(of: content)
        let bothWays = editedBothWays
        let saved = perform(.saveCard) { engine throws(EngineError) in
            try engine.edit(card.id, keeping: files, with: content, bothWays: bothWays)
        }
        if saved {
            endEditing()
            read(on: ladder)
        }
    }

    /// Saves the capture Lucas edits with its text, note and source, as its
    /// fields hold them, and ends the edit, or records why it couldn't and
    /// goes on with it. An expansion stays attached to its card, and a
    /// follow-up tied to its own. As with a card, the detail shows it as
    /// saved at once.
    public mutating func saveCapture(text: String, note: String, source: String) {
        guard case .capture(let capture) = editing else { return }
        let saved = perform(.saveCapture) { engine throws(EngineError) in
            try engine.editCapture(capture.id, text: text, note: note, source: source)
        }
        if saved {
            editing = nil
            read(on: ladder)
        }
    }

    /// Ends the edit without saving it, nor the images and sounds the user
    /// put on it.
    public mutating func cancelEditing() {
        endEditing()
        showFiles()
    }

    /// Ends the edit, with the images and sounds it put on the card, and the
    /// sounds still converting for it, which are let go once they come in.
    private mutating func endEditing() {
        editing = nil
        editedImages = SideImages()
        editedSounds = SideSounds()
        editedSoundsComingIn = [:]
        editedBothWays = false
        editedType = nil
    }

    /// Asks what needs fixing in the card the detail shows, to flag it, while
    /// Flag is offered.
    public mutating func askToFlag() {
        guard actions.contains(.flag), case .card(let row, _) = detail else { return }
        question = .flag(row)
    }

    /// Flags the card the window asks about with Lucas's note on what to
    /// fix: it leaves his reviews and waits in the inbox. When it can't, it
    /// records why and goes on asking, so the note he wrote stays.
    public mutating func flag(note: FlagNote) {
        guard case .flag(let row) = question else { return }
        let flagged = perform(.flag) { engine throws(EngineError) in try engine.flag(row.id, note: note) }
        if flagged {
            question = nil
        }
    }

    /// Buries the selected cards the table lists, all at once, while Bury is
    /// offered, or records why it couldn't.
    public mutating func bury() {
        guard actions.contains(.bury) else { return }
        let cardIDs = Set(selectedRows.map(\.id))
        perform(.bury(cardCount: cardIDs.count)) { engine throws(EngineError) in try engine.bury(cardIDs) }
    }

    /// Unburies the selected cards the table lists, all at once, while
    /// Unbury is offered, or records why it couldn't.
    public mutating func unbury() {
        guard actions.contains(.unbury) else { return }
        let cardIDs = Set(selectedRows.map(\.id))
        perform(.unbury(cardCount: cardIDs.count)) { engine throws(EngineError) in try engine.unbury(cardIDs) }
    }

    /// Turns Both ways on for the selected cards the table lists, all at
    /// once, while Turn On Both Ways is offered, and reads them again, so
    /// that the window offers Turn Off at once; or records why it couldn't.
    public mutating func turnOnBothWays() {
        guard actions.contains(.turnOnBothWays) else { return }
        setBothWays(true)
    }

    /// Turns Both ways off for the selected cards the table lists, all at
    /// once, while Turn Off Both Ways is offered, and reads them again, so
    /// that the window offers Turn On at once; or records why it couldn't.
    public mutating func turnOffBothWays() {
        guard actions.contains(.turnOffBothWays) else { return }
        setBothWays(false)
    }

    /// Turns Both ways on or off for the selected cards the table lists, as
    /// `bothWays` says, and reads them again, or records why it couldn't.
    private mutating func setBothWays(_ bothWays: Bool) {
        let cardIDs = Set(selectedRows.map(\.id))
        let action: FailedAction =
            bothWays ? .turnOnBothWays(cardCount: cardIDs.count) : .turnOffBothWays(cardCount: cardIDs.count)
        let done = perform(action) { engine throws(EngineError) in try engine.setBothWays(bothWays, of: cardIDs) }
        if done {
            read(on: ladder)
        }
    }

    /// Asks whether to delete the selected cards the table lists, while Delete
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
    }

    /// Asks whether to discard the capture, the expansion or the follow-up
    /// the detail shows, while Discard is offered.
    public mutating func askToDiscard() {
        guard actions.contains(.discard), let capture = shownCapture else { return }
        question = .discard(capture)
    }

    /// Discards `capture`, which the window asked about and Lucas confirmed,
    /// so it leaves the inbox without becoming cards, or records why it
    /// couldn't. The dialog hands `capture` back, as Delete's hands its cards.
    public mutating func discard(_ capture: Capture) {
        question = nil
        perform(.discard) { engine throws(EngineError) in try engine.discard(capture.id) }
    }

    /// What the context menu of the sidebar's tag named `tag` offers, or nil
    /// when the sidebar doesn't list it.
    public func menu(for tag: String) -> TagMenu? {
        tags.first { $0.name == tag }.map { tag in
            TagMenu(
                isSetAsideTicked: tag.isSetAside,
                colorItems: ([nil] + TagColor.allCases).map { ColorItem(color: $0, isTicked: $0 == tag.color) })
        }
    }

    /// Chooses Set Aside in the context menu of the sidebar's tag named
    /// `tag`: sets it aside, or undoes it while it's ticked, and reads the
    /// cards again, or records why it couldn't.
    public mutating func chooseSetAside(on tag: String) {
        guard let menu = menu(for: tag) else { return }
        let done =
            if menu.isSetAsideTicked {
                perform(.stopSettingAside(tag: tag)) { engine throws(EngineError) in try engine.stopSettingAside(tag) }
            } else {
                perform(.setAside(tag: tag)) { engine throws(EngineError) in try engine.setAside(tag) }
            }
        if done {
            read(on: ladder)
        }
    }

    /// Chooses `color` in the Color submenu of the sidebar's tag named `tag`,
    /// or None when it's nil: gives the tag that color, or takes its color
    /// away, and reads the cards again, or records why it couldn't.
    public mutating func chooseColor(_ color: TagColor?, on tag: String) {
        guard menu(for: tag) != nil else { return }
        let done = perform(.setColor(tag: tag)) { engine throws(EngineError) in try engine.setColor(color, of: tag) }
        if done {
            read(on: ladder)
        }
    }

    /// Asks which emoji the sidebar's tag named `tag` gets, in the emoji
    /// sheet, after Emoji… in its context menu.
    public mutating func askForEmoji(on tag: String) {
        guard let tag = tags.first(where: { $0.name == tag }) else { return }
        question = .emoji(tag)
    }

    /// Gives `tag`, the tag the window asks about, `emoji`, or takes its
    /// emoji away when it's nil, and reads the cards again; or records why it
    /// couldn't. Whether it did.
    private mutating func setEmoji(_ emoji: Emoji?, of tag: CardTag) -> Bool {
        let done = perform(.setEmoji(tag: tag.name)) { engine throws(EngineError) in
            try engine.setEmoji(emoji, of: tag.name)
        }
        if done {
            read(on: ladder)
        }
        return done
    }

    /// What OK in the emoji sheet, or in the New Type sheet, makes of `text`,
    /// what an emoji field holds: one emoji for the tag or the user type,
    /// none when the field is empty, or a refusal of anything else.
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

    /// Chooses OK in the emoji sheet, whose field holds `text`: gives the tag
    /// or the user type the window asks about that emoji, or takes its emoji
    /// away when the field is empty, and reads the cards again, or records
    /// why it couldn't and goes on asking. While OK refuses `text`, it does
    /// nothing, and the sheet says why.
    public mutating func chooseEmoji(_ text: String) {
        let entry = emojiEntry(text)
        guard !entry.isRefused else { return }
        let done: Bool
        switch question {
        case .emoji(let tag): done = setEmoji(entry.emoji, of: tag)
        case .typeEmoji(let type): done = setEmoji(entry.emoji, of: type)
        default: return
        }
        if done {
            question = nil
        }
    }

    /// What OK in the rename sheet makes of `text`, what its field holds: for
    /// the tag the window asks about, the tag's new whole name, or a refusal
    /// of a blank name or one inside the tag itself; for the user type it
    /// asks about, the type's name, or a refusal of a blank name, a name of
    /// one of the four Ficha comes with, or another user type's; each as the
    /// engine refuses them. Nil while the window asks about no name.
    public func renameEntry(_ text: String) -> RenameEntry? {
        switch question {
        case .renameTag(let tag): tagNameEntry(text, renaming: tag.name)
        case .renameType(let type): typeNameEntry(text, renaming: type.id)
        default: nil
        }
    }

    /// Chooses OK in the rename sheet, whose field holds `text`: renames the
    /// tag the window asks about, and every tag inside it, as
    /// `Engine.renameTag(_:to:)` does, or the user type it asks about, and
    /// reads the cards again, the sidebar following the tag or the type it
    /// chose to its new name; or records why it couldn't and goes on asking.
    /// While OK refuses `text`, it does nothing, and the sheet says why.
    public mutating func chooseNewName(_ text: String) {
        guard case .name(let name)? = renameEntry(text) else { return }
        let done: Bool
        switch question {
        case .renameTag(let tag): done = renameTag(tag.name, to: name, as: .rename(tag: tag.name))
        case .renameType(let type): done = renameType(type, to: name)
        default: return
        }
        if done {
            question = nil
        }
    }

    /// Drops what the window asks, which Lucas cancelled.
    public mutating func cancelQuestion() {
        question = nil
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

    /// Reads the tags and what the sidebar chose, as they are now, on
    /// `ladder`, the one Lucas set in Settings, which he may have changed
    /// since the last read, and the review log of the card the detail shows.
    /// When the chosen tag is gone, because its last card was buried, edited
    /// or deleted while it isn't set aside, the sidebar goes back to All
    /// cards, and so it does when No Type is gone, once every card that
    /// isn't buried has a type, and when the chosen user type is deleted. A
    /// user type renamed, or given another emoji, stays chosen.
    public mutating func read(on ladder: Ladder) {
        self.ladder = ladder
        now = engine.now
        do throws(EngineError) {
            tags = try engine.sidebarTags()
            (tagsSection, setAsideSection) = Self.sections(of: tags)
            typeGroups = try engine.sidebarTypeGroups()
            followUserTypes()
            if case .cards(let group) = sidebarItem, !offers(group) {
                sidebarItem = .cards(.all)
            }
            switch sidebarItem {
            case .cards(let group):
                listing = .success(.cards(try engine.cardRows(in: group, matching: search, on: ladder)))
            case .inbox:
                listing = .success(.inbox(try engine.inboxRows(matching: search, on: ladder)))
            }
        } catch {
            listing = .failure(error)
        }
        readFrontsInUse()
        readReviewLog()
    }

    /// Whether the sidebar offers `group`, as last read: a tag while it lists
    /// it, No Type while some card has none, a user type while it lists it,
    /// and every other group always.
    private func offers(_ group: CardGroup) -> Bool {
        switch group {
        case .tag(let tag): tags.contains { $0.name == tag }
        case .noType: typeGroups.contains(.noType)
        case .type(let type): offersType(type)
        case .all, .new, .due, .learned, .flagged, .buried: true
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
            cardID: row.id, rows: Result { () throws(EngineError) in try engine.reviewLogRows(of: row.id, on: ladder) })
    }
}

/// A card's review log, as the Cards window's detail shows it under the
/// card, or why it couldn't be read.
private struct CardReviewLog: Sendable {
    let cardID: Int64
    let rows: Result<[ReviewLogRow], EngineError>
}

extension Engine {
    /// Opens the Cards window on All cards, with nothing searched or
    /// selected, for Lucas's cards standing on `ladder`, the one he set in
    /// Settings, which it reads once the window asks.
    public func openCardsWindow(on ladder: Ladder) -> CardsWindowState {
        CardsWindowState(engine: self, ladder: ladder)
    }
}
