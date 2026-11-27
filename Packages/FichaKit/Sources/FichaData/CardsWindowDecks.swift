import FichaCore
import Foundation

// The Cards window's decks (ADR 0024): the sidebar's Your Decks section, after
// Inbox and before Tags, lists every deck as a tree, Default first while it
// holds cards or has a switch on, where it always was, then the decks at the
// top of the tree with cards in the user's reviews, in the order of the
// queue new cards come from, a deck listed first for its priority cards
// alone first, and a deck met in full at its place among them, as the mock's
// Your Decks lists them, then the others in alphabetical order, and those
// set aside last, each with the decks inside it in alphabetical order, and
// each with how many of its cards are due, those of the decks inside it
// counted, and each at the top of the tree, Default too, with a line under
// its title that says how far it is and when it's all met, from the queue
// new cards come from (ADR 0034, #491). Each parent starts open, as in
// Anki's deck list, and the window remembers the ones Lucas closes while
// it's open. Choosing a deck lists its cards and those of every deck inside
// it. A deck's menu,
// Default's too, the same in its row's context menu and in the Actions menu
// above the grid while the sidebar chose it, which is its keyboard
// path, sets it aside or prioritizes it (`DeckSwitches.swift`), and gives it
// a color or an emoji (`DeckColorAndEmoji.swift`), which its row shows, as
// the decks inside it that have none do; a set-aside deck is grayed, with
// the decks inside it, last when it's at the top of the tree and in its
// place inside another. Every deck's but Default's also renames it and deletes
// it, and in the sidebar cards and decks dropped on a deck move there
// (`CardsWindowDeckEdits.swift`). Every deck's menu and the Your Decks title's
// have New Deck…, whose OK makes a deck with no card, where its name says, and
// then asks How fast? for a new deck at the top of the tree (`HowFast.swift`).
// A chosen deck's tags line up above its cards (`CardsWindowDeckTags.swift`).
// Change Deck… moves the selected cards to the deck Lucas picks in its sheet,
// from the same tree with Default always in it, or to one he names there with
// New Deck…, which the move makes. The Deck field, in the card form and the
// editor (`CardsWindowDeckField.swift`), offers that tree too, and its New
// Deck… names a deck in the New Deck sheet with the same name field and the
// same checks, for the field to hold; and so does the Import sheet's choice of
// deck (`CardsWindowImport.swift`), which names one in its preview's place.

extension CardsWindowState {
    /// A deck in the sidebar's tree, or in the Change Deck sheet's, with the
    /// decks right inside it, which a disclosure triangle shows.
    public struct DeckRow: Sendable, Equatable, Identifiable {
        /// The deck, with what it has of its own and takes from the decks it
        /// sits inside.
        public let deck: Deck
        /// What its row says: its last level under its parent, or nothing for
        /// Default, which the window names from the app's String Catalog.
        public let title: String
        /// How many cards it lists and how many of those are due, counting
        /// the decks inside it: none for a deck New Deck… named, which the
        /// move makes.
        public let counts: DeckCounts
        /// Whether its row is grayed: while its cards are out of Lucas's
        /// reviews, as it's set aside on its own or sits inside a deck that
        /// is.
        public let isGrayed: Bool
        /// What its row says under its title, in the sidebar's Your Decks
        /// section, for a deck at the top of the tree, Default included
        /// (#491): nil for a deck inside another, and in the Change Deck
        /// sheet's tree.
        public let line: Line?
        /// The decks right inside it, in the order a tree lists them.
        public let children: [DeckRow]

        /// What a deck's row says under its title (#491), from where it
        /// stands and the queue new cards come from (ADR 0034): "9 of 14"
        /// counts the cards met (`CardsInReviews.metCards(in:)`), those whose
        /// front-first way has an entry in the review log, of every card of
        /// the deck and the decks inside it, whatever its standing. A deck
        /// with no card says so, and a deck set aside so, before anything
        /// else; a deck met in full says so exactly when the review panel
        /// would say "You've met them all" of it, by the same rule, also with
        /// a buried card still to meet; a deck in the queue says where it
        /// is, also when its cards are all met but some of their back-first
        /// ways are still to come; and any other, how far it is.
        public enum Line: Sendable, Equatable {
            /// "No cards yet": the deck, with the decks inside it, has no
            /// card.
            case noCards
            /// "Set aside · 9 of 14 met": the deck is set aside.
            case setAside(met: Int, of: Int)
            /// "Met them all · 14 cards in 9 days": the deck is met in full,
            /// out of the queue, as `CardsInReviews.decksMetInFull` says,
            /// with its cards, all of them, whatever their standing, and the
            /// calendar days from the one its first card came in to the one
            /// its last way was met, both counted; or "Met them all" alone
            /// without them, as when an import's reviews from Anki come
            /// before its cards came in.
            case metThemAll(cards: Int, days: Int?)
            /// "9 of 14 · on track for early December": the deck is first in
            /// the queue, the one new cards come from now, with its finish
            /// date.
            case first(met: Int, of: Int, finish: FinishDate.Wording)
            /// "Next · on track for mid-December": the deck waits in the
            /// queue after the first, with its finish date.
            case next(finish: FinishDate.Wording)
            /// "9 of 14": how far the deck is, with no finish date, as when
            /// the pace brings no new card, or none of its cards is in the
            /// user's reviews, as when they're all buried.
            case progress(met: Int, of: Int)
        }

        public var id: String {
            deck.name
        }

        /// What choosing it in the sidebar lists: its cards, and those of
        /// every deck inside it.
        public var item: SidebarItem {
            .cards(.deck(deck.name))
        }
    }

    /// What Change Deck… asks, in its sheet, while it asks: which deck the
    /// selected cards move to.
    public struct DeckChange: Sendable, Equatable {
        /// The cards it moves, as the grid listed them when Lucas chose
        /// Change Deck….
        public let cards: [CardRow]
        /// The deck the sheet has chosen, which Move moves the cards to: the
        /// one they all live in, as the sheet opens, or nil when they live in
        /// several, until Lucas picks one.
        public internal(set) var chosenDeck: String?
        /// Whether Move is offered: once the sheet has chosen a deck.
        public var canMove: Bool { chosenDeck != nil }
        /// The decks Lucas named with New Deck… in the sheet, which it lists
        /// in its tree, and Move makes when it moves the cards to one.
        public internal(set) var newDecks: [String]
        /// Whether the sheet asks for a new deck's name, after New Deck…, in
        /// place of its tree.
        public internal(set) var isNamingNewDeck: Bool
    }

    /// What a deck's menu offers, Default's too: in the sidebar, as its row's
    /// context menu, and above the grid while the sidebar chose it, as the
    /// Actions menu, which is how the keyboard reaches it. The same menu
    /// in both places, which acts on the one deck: Set Aside, Prioritize,
    /// Color and Emoji…, and Rename… and Delete… while it offers them
    /// (`offersRenameAndDelete`). New Deck…, always above them, acts on no
    /// deck (`askToMakeDeck()`).
    public struct DeckMenu: Sendable, Equatable {
        /// The deck it acts on, with what it has of its own and takes from
        /// the decks it sits inside.
        public let deck: Deck
        /// Whether Prioritize is on: unless the deck is set aside, on its own
        /// or inside a deck that is, since a deck is never both (ADR 0011),
        /// but for a priority deck, which it unticks.
        public let canPrioritize: Bool
        /// The Color submenu's items: None, then Finder's seven colors in
        /// Finder's order, with the deck's own color ticked, or None while it
        /// has none of its own, whatever it takes from the decks it sits
        /// inside.
        public let colorItems: [ColorItem]

        /// Whether Set Aside is ticked: the deck is set aside on its own, and
        /// choosing it again undoes it.
        public var isSetAsideTicked: Bool {
            deck.isSetAside
        }

        /// Whether Prioritize is ticked: the deck is a priority deck, and
        /// choosing it again undoes it.
        public var isPriorityTicked: Bool {
            deck.isPriority
        }
    }

    /// What OK makes of what a deck's name field holds: the Change Deck
    /// sheet's, the New Deck sheet's, whichever New Deck… opened it, or the
    /// Import sheet's, after New Deck…, or one of the Import sheet's deck
    /// fields.
    public enum NewDeckEntry: Sendable, Equatable {
        /// The deck's whole name, its levels cleaned up.
        case name(String)
        /// A name with no level, blank or only `::`, as the field starts,
        /// which keeps OK off, and which the sheet doesn't call a mistake.
        case blankName
        /// A name OK refuses, and why, for the sheet to say: one whose top
        /// level is one of Default's names.
        case refused(EngineError)

        /// What OK makes of `text`: the deck's whole name, its levels
        /// cleaned up; a blank name; or a refusal of a name whose top level
        /// is one of Default's, as the engine refuses it.
        init(checking text: String) {
            do throws(EngineError) {
                self = .name(try checkedDeckName(text))
            } catch .blankDeckName {
                self = .blankName
            } catch {
                self = .refused(error)
            }
        }
    }

    /// The sidebar's Your Decks section, as last read: every deck as a tree,
    /// Default first while it holds cards or has a switch on, wherever the
    /// queue has it, then the other decks at the top of the tree with cards
    /// in the user's reviews, in the order of the queue new cards come from,
    /// as FichaCore keeps it (`CardsInReviews.topDecksInQueueOrder`): those
    /// listed first for their priority cards alone, in the queue's order,
    /// and then the others in the order of their places, those met in full
    /// at theirs too; then the rest in alphabetical order, and those set
    /// aside last, each with its counts, and each at the top of the tree
    /// with its line.
    public var deckRows: [DeckRow] {
        let places = Dictionary(placedTopDecks.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = Self.deckRows(of: decks, lines: deckLines)
        // Default, the decks in the queue's order, the rest, and those set
        // aside, each group in its order: the queue's, or the tree's.
        func rank(of index: Int) -> (Int, Int, Int) {
            let deck = rows[index].deck
            if deck.isDefault {
                return (0, 0, index)
            }
            if let place = places[deck.name] {
                return (1, place, index)
            }
            return (deck.isSetAside ? 3 : 2, 0, index)
        }
        return rows.indices.sorted { rank(of: $0) < rank(of: $1) }.map { rows[$0] }
    }

    /// The deck the window opens on, and goes back to once what the sidebar
    /// chose is gone, as the desktop mock opens on the first of its Your
    /// Decks: the first deck of the queue new cards come from that Your
    /// Decks lists, the one the user is meeting, in the order
    /// `CardsInReviews.topDecksInQueueOrder` gives, Default too when it's
    /// first there; or else, while no deck holds cards in the user's
    /// reviews, the first deck Your Decks lists; or nil while it lists none.
    var deckToOpenOn: DeckRow? {
        let rows = deckRows
        let inQueue = placedTopDecks.lazy.compactMap { deck in rows.first { $0.deck.name == deck } }
        return inQueue.first ?? rows.first
    }

    /// Whether the sidebar's deck `deck` is open, showing the decks inside
    /// it. Each starts open.
    public func isDeckOpen(_ deck: String) -> Bool {
        !closedDecks.contains(deck)
    }

    /// Opens the sidebar's deck `deck`, or closes it when `isOpen` is false.
    public mutating func setDeckOpen(_ isOpen: Bool, _ deck: String) {
        if isOpen {
            closedDecks.remove(deck)
        } else {
            closedDecks.insert(deck)
        }
    }

    /// What the menu of the deck `deck` offers, by its whole name, or
    /// Default's by `Deck.defaultName`, while the sidebar lists it; nil
    /// otherwise.
    public func menu(forDeck deck: String) -> DeckMenu? {
        guard let listed = listedDeck(deck) else { return nil }
        return DeckMenu(
            deck: listed, canPrioritize: listed.canBePrioritized(amongSetAside: decks.map(\.deck).setAsideNames),
            colorItems: ColorItem.items(forOwn: [listed.color]))
    }

    /// The deck `deck`, by its whole name, or Default by
    /// `Deck.defaultName`, as the sidebar lists it, with what it has of its
    /// own and takes from the decks it sits inside; nil while it doesn't
    /// list it.
    func listedDeck(_ deck: String) -> Deck? {
        decks.first { $0.deck.name == deck }?.deck
    }

    /// The menu of the deck the sidebar chose, which the Actions menu above
    /// the grid offers, the keyboard's way to a deck's menu: nil while the
    /// sidebar chose something else. While Lucas edits a card, it stays,
    /// waiting with the grid, so the grid doesn't move.
    public var chosenDeckMenu: DeckMenu? {
        guard case .cards(.deck(let deck)) = sidebarItem else { return nil }
        return menu(forDeck: deck)
    }

    /// Chooses Set Aside in the menu of the deck `deck`: sets it aside, or
    /// undoes it while it's ticked, and reads the cards again, or records why
    /// it couldn't.
    public mutating func chooseSetAside(onDeck deck: String) {
        guard let menu = menu(forDeck: deck) else { return }
        if menu.isSetAsideTicked {
            changeOwnDeck(as: .stopSettingAside(deck: deck)) { engine throws(EngineError) in
                try engine.stopSettingAside(deck: deck)
            }
        } else {
            changeOwnDeck(as: .setAside(deck: deck)) { engine throws(EngineError) in try engine.setAside(deck: deck) }
        }
    }

    /// Chooses Prioritize in the menu of the deck `deck`, while it's on:
    /// makes it a priority deck, or no longer while it's ticked, and reads
    /// the cards again, or records why it couldn't, as when another device
    /// set it aside meanwhile.
    public mutating func choosePriority(onDeck deck: String) {
        guard let menu = menu(forDeck: deck), menu.canPrioritize else { return }
        let isPriority = !menu.isPriorityTicked
        changeOwnDeck(as: isPriority ? .prioritize(deck: deck) : .stopPrioritizing(deck: deck)) {
            engine throws(EngineError) in try engine.setPriority(isPriority, ofDeck: deck)
        }
    }

    /// Chooses `color` in the Color submenu of the deck `deck`'s menu, or
    /// None when it's nil: gives the deck that color, or takes its own away,
    /// and reads the cards again, or records why it couldn't.
    public mutating func chooseColor(_ color: TagColor?, onDeck deck: String) {
        guard listedDeck(deck) != nil else { return }
        changeOwnDeck(as: .setDeckColor(deck: deck)) { engine throws(EngineError) in
            try engine.setColor(color, ofDeck: deck)
        }
    }

    /// Asks which emoji the deck `deck` gets, in the emoji sheet, after
    /// Emoji… in its menu, while the sidebar lists it.
    public mutating func askForEmoji(onDeck deck: String) {
        guard let listed = listedDeck(deck) else { return }
        question = .deckEmoji(listed)
    }

    /// Gives `deck`, the deck the window asks about, `emoji`, or takes its
    /// own away when it's nil, and reads the cards again; or records why it
    /// couldn't. Whether it did.
    mutating func setEmoji(_ emoji: Emoji?, of deck: Deck) -> Bool {
        changeOwnDeck(as: .setDeckEmoji(deck: deck.name)) { engine throws(EngineError) in
            try engine.setEmoji(emoji, ofDeck: deck.name)
        }
    }

    /// Does `work`, the engine's part of an action on what a deck has of its
    /// own, its switch, color or emoji, and reads the cards again, or records
    /// why it couldn't, as `action`. Whether it did.
    @discardableResult
    private mutating func changeOwnDeck(as action: FailedAction, _ work: (Engine) throws(EngineError) -> Void)
        -> Bool
    {
        guard perform(action, work) else { return false }
        readAgain()
        return true
    }

    /// What Change Deck… asks, while it asks.
    public var deckChange: DeckChange? {
        guard case .changeDeck(let change) = question else { return nil }
        return change
    }

    /// The tree the Change Deck sheet offers, while it asks: Default first,
    /// always, then every deck the sidebar lists, and those Lucas named with
    /// New Deck… there, with the decks they sit inside. Empty while the
    /// window asks no such thing.
    public var deckChoices: [DeckRow] {
        guard case .changeDeck(let change) = question else { return [] }
        return decksToChoose(adding: change.newDecks)
    }

    /// The decks the Change Deck sheet and the Deck field offer, as a tree,
    /// in the order a tree lists them: Default first, always, then every
    /// deck the sidebar lists, and `named`, decks New Deck… may have named,
    /// with the decks they sit inside, each with nothing of its own and no
    /// cards.
    func decksToChoose(adding named: [String]) -> [DeckRow] {
        let listed = decks.map(\.deck.name)
        let others = TagPath.lineages(of: named).subtracting(listed + [Deck.defaultName])
        let defaultDeck = listed.contains(Deck.defaultName) ? [] : [CountedDeck.empty(Deck.defaultName)]
        return Self.deckRows(of: defaultDeck + decks + others.map(CountedDeck.empty), lines: [:])
    }

    /// The decks a pop-up of decks offers while it holds `held`, before New
    /// Deck…, in the order a tree lists them, as `decksToChoose(adding:)`
    /// lists them with `held`, which New Deck… may have named: a card's Deck
    /// field's, and the Import sheet's choice of deck.
    func decksToPick(holding held: String) -> [Deck] {
        decksToChoose(adding: [held]).flatMap(\.flattened).map(\.deck)
    }

    /// Asks which deck the selected cards the grid lists move to, in the
    /// Change Deck sheet, which starts on the deck they all live in, while
    /// Change Deck… is offered.
    public mutating func askToChangeDeck() {
        guard actions.contains(.changeDeck) else { return }
        let rows = selectedRows
        let decks = Set(rows.map(\.card.deck))
        question = .changeDeck(
            DeckChange(
                cards: rows, chosenDeck: decks.count == 1 ? decks.first : nil, newDecks: [], isNamingNewDeck: false))
    }

    /// Chooses the deck `deck` in the Change Deck sheet's tree, while it
    /// offers it, which Move then moves the cards to.
    public mutating func chooseInDeckChange(_ deck: String) {
        guard case .changeDeck(var change) = question,
            deckChoices.flatMap(\.flattened).contains(where: { $0.id == deck })
        else { return }
        change.chosenDeck = deck
        question = .changeDeck(change)
    }

    /// Asks for a new deck's name, in the Change Deck sheet, after New
    /// Deck… there.
    public mutating func askForNewDeck() {
        guard case .changeDeck(var change) = question else { return }
        change.isNamingNewDeck = true
        question = .changeDeck(change)
    }

    /// What OK makes of `text`, what the name field holds after New Deck…,
    /// in the Change Deck sheet, in the New Deck sheet a Deck field opens
    /// (`CardsWindowDeckField.swift`) or the sidebar does, or in the Import
    /// sheet's preview's place (`CardsWindowImport.swift`): the deck's whole
    /// name, its levels cleaned up; a blank name, as the field starts, which
    /// keeps OK off; or a refusal of a name whose top level is one of
    /// Default's, as the engine refuses it. Nil while the window asks for no
    /// new deck's name.
    public func newDeckEntry(_ text: String) -> NewDeckEntry? {
        switch question {
        case .changeDeck(let change): guard change.isNamingNewDeck else { return nil }
        case .newDeck, .makeDeck: break
        default: guard importing?.isNamingNewDeck == true else { return nil }
        }
        return NewDeckEntry(checking: text)
    }

    /// Asks for a new deck's name, in the New Deck sheet, after New Deck… in
    /// the sidebar: in the menu of any deck, Default's too, or of the Your
    /// Decks title. The deck goes where its name says, not inside the one
    /// Lucas right-clicked.
    public mutating func askToMakeDeck() {
        question = .makeDeck
    }

    /// Chooses OK after New Deck…, whose name field holds `text`: the
    /// sheet's tree lists the deck, with the decks it sits inside, and
    /// chooses it, for Move to make it as it moves the cards there; in the
    /// New Deck sheet, the Deck field it was asked from holds the deck
    /// (`CardsWindowDeckField.swift`), or, when the sidebar asked, the deck
    /// is made at once (`makeDeck(named:)`); and in the Import sheet, its
    /// choice of deck holds it, for Import to make it as the cards come into
    /// it, and the sheet shows the preview again. A deck already listed is
    /// chosen. While OK doesn't take `text`, as `newDeckEntry(_:)` says, it
    /// does nothing, and the sheet says why.
    public mutating func chooseNewDeck(_ text: String) {
        guard case .name(let name)? = newDeckEntry(text) else { return }
        switch question {
        case .newDeck(let fields):
            question = nil
            putInDeckField(name, fields)
        case .makeDeck:
            makeDeck(named: name)
        case .changeDeck(var change):
            if !change.newDecks.contains(name) {
                change.newDecks.append(name)
            }
            change.chosenDeck = name
            change.isNamingNewDeck = false
            question = .changeDeck(change)
        default:
            importing?.chosenDeck = name
            importing?.isNamingNewDeck = false
        }
        askForTheFichaDeckAskedToAdd()
    }

    /// Makes the deck `name`, a name OK takes, with no card, which the sidebar
    /// asked for: it opens the decks it sits inside, so it shows, leaves the
    /// sidebar where it was, and reads the cards again, and How fast? then
    /// asks about the deck at the top of the tree it made, the deck or one
    /// it sits inside, while the sidebar didn't list it before
    /// (`HowFast.swift`); or records why it couldn't and goes on asking. One
    /// of Ficha's decks the review panel asked for meanwhile waits until the
    /// deck is made, as `chooseNewDeck(_:)` asks for it then, and, while How
    /// fast? asks, until it closes.
    private mutating func makeDeck(named name: String) {
        let top = TagPath.top(of: name)
        let isNewAtTheTop = listedDeck(top) == nil
        let done = perform(.makeDeck) { engine throws(EngineError) in
            try engine.makeDeck(named: name)
        }
        guard done else { return }
        question = nil
        closedDecks.subtract(TagPath.ancestors(of: name))
        readAgain()
        if isNewAtTheTop {
            askHowFast(about: [top], cameInFrom: .newDeck)
        }
    }

    /// Goes back from the name New Deck… asked for, which Lucas cancelled,
    /// to the Change Deck sheet's tree, or to the Import sheet's preview.
    public mutating func cancelNewDeck() {
        if case .changeDeck(var change) = question {
            change.isNamingNewDeck = false
            question = .changeDeck(change)
        } else {
            importing?.isNamingNewDeck = false
        }
    }

    /// Chooses Move in the Change Deck sheet: moves the cards it asks about
    /// to the deck it has chosen, making a deck New Deck… named, and reads
    /// the cards again; or records why it couldn't and goes on asking. While
    /// no deck is chosen, it does nothing.
    public mutating func changeDeck() {
        guard case .changeDeck(let change) = question, let deck = change.chosenDeck else { return }
        let cardIDs = Set(change.cards.map(\.id))
        let done = perform(.changeDeck(cardCount: cardIDs.count)) { engine throws(EngineError) in
            try engine.changeDeck(of: cardIDs, to: deck)
        }
        if done {
            question = nil
            readAgain()
        }
        askForTheFichaDeckAskedToAdd()
    }

    /// Reads what the row of each deck at the top of the tree the sidebar
    /// lists says under its title, as last read, from where it stands now and
    /// the queue new cards come from, with the pace the database holds and
    /// the window's active hours, and the decks' order in it, which the
    /// sidebar lists them in.
    mutating func readDeckLines() throws(EngineError) {
        let settings = try engine.cardsWindowQueueSettings(activeHours: activeHours)
        let lines = try engine.deckLines(of: listedTopDecks, with: settings)
        deckLines = lines.lines
        placedTopDecks = lines.places
    }

    /// The decks at the top of the tree the sidebar lists, as last read, in
    /// the order a tree lists them.
    var listedTopDecks: [Deck] {
        decks.map(\.deck).filter { TagPath.parent(of: $0.name) == nil }
    }

    /// The rows of `decks`, as a tree, in the order a tree lists them, each
    /// named by its last level under its parent, grayed while it's set
    /// aside, on its own or inside one of `decks` that is, and with its line
    /// in `lines`, by its whole name, if any.
    private static func deckRows(of decks: [CountedDeck], lines: [String: DeckRow.Line]) -> [DeckRow] {
        let setAside = decks.map(\.deck).setAsideNames
        return deckTree(of: decks, named: \.deck.name) { counted, title, children in
            DeckRow(
                deck: counted.deck, title: title, counts: counted.counts,
                isGrayed: deckSettingAside(counted.deck.name, amongSetAside: setAside) != nil,
                line: lines[counted.deck.name], children: children)
        }
    }
}

extension Engine {
    /// The settings the Cards window reads the queue new cards come from
    /// with: those that decide progress, the pace among them, as the
    /// database holds them, `activeHours`, Settings' on this device, as the
    /// review panel's settings hold them, so today's new cards end when they
    /// do, and Ficha's own for the rest, which the queue doesn't read.
    func cardsWindowQueueSettings(activeHours: Range<Int>) throws(EngineError) -> ReviewSettings {
        var settings = ReviewSettings.defaults
        settings.progress = try progressSettings()
        settings.activeHours = activeHours
        return settings
    }

    /// What the rows of `decks`, decks at the top of the tree, say under
    /// their titles in the Cards window's sidebar (#491), by their whole
    /// names, now, in one read: out of every card, whatever its standing, how
    /// many of each deck's are met, as `CardsInReviews.metCards(in:)` says;
    /// which decks are met in full, as `CardsInReviews.decksMetInFull` says,
    /// each with the days from when its first card came in to when its last
    /// way was met, each way met at its first entry; and the queue new cards
    /// come from, with `settings`' pace, as `queue(_:)` reads it, with its
    /// finish dates as they read by the engine's calendar; and the decks at
    /// the top of the tree with cards in the user's reviews, by their whole
    /// names, in that queue's order, those met in full at their places, as
    /// `CardsInReviews.topDecksInQueueOrder` says.
    fileprivate func deckLines(of decks: [Deck], with settings: ReviewSettings) throws(EngineError)
        -> (lines: [String: CardsWindowState.DeckRow.Line], places: [String])
    {
        let now = time.now
        return try read { db in
            let log = try logEntries(in: db)
            let met = CardsInReviews.metCards(in: log)
            var metAt: [CardWay: Date] = [:]
            for entry in log {
                let way = CardWay(cardID: entry.cardID, way: entry.way)
                metAt[way] = min(metAt[way] ?? entry.answeredAt, entry.answeredAt)
            }
            var counts: [String: (met: Int, of: Int)] = [:]
            var cameIn: [String: Date] = [:]
            var lastMet: [String: Date] = [:]
            for card in try allCards(in: db) {
                let top = TagPath.top(of: card.deck)
                counts[top, default: (0, 0)].of += 1
                counts[top, default: (0, 0)].met += met.contains(card.id) ? 1 : 0
                cameIn[top] = min(cameIn[top] ?? card.createdAt, card.createdAt)
                for way in [Way.frontFirst, .backFirst] {
                    if let at = metAt[CardWay(cardID: card.id, way: way)] {
                        lastMet[top] = max(lastMet[top] ?? at, at)
                    }
                }
            }
            /// The calendar days `deck` took to be met in full, counting the
            /// day its first card came in and the day its last way was met:
            /// nil without both, or when the log's last first entry comes
            /// before the first card, as an import's reviews from Anki can.
            func daysToMeet(_ deck: String) -> Int? {
                guard let first = cameIn[deck], let last = lastMet[deck] else {
                    return nil
                }
                let start = calendar.startOfDay(for: first)
                guard let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: last)).day,
                    days >= 0
                else {
                    return nil
                }
                return days + 1
            }
            let inReviews = try cardsThatShowUp(in: db).inReviews
            let metInFull = inReviews.decksMetInFull
            let queue = settings.queue(of: inReviews, now: now, calendar: calendar)
            var lines: [String: CardsWindowState.DeckRow.Line] = [:]
            for deck in decks {
                let count = counts[deck.name, default: (0, 0)]
                let place = queue.firstIndex { $0.deck == deck.name }
                let finish = place.flatMap { queue[$0].finish }?.wording(now: now, calendar: calendar)
                let line: CardsWindowState.DeckRow.Line =
                    if count.of == 0 {
                        .noCards
                    } else if deck.isSetAside {
                        .setAside(met: count.met, of: count.of)
                    } else if metInFull.contains(deck.name) {
                        .metThemAll(cards: count.of, days: daysToMeet(deck.name))
                    } else if let finish {
                        place == 0 ? .first(met: count.met, of: count.of, finish: finish) : .next(finish: finish)
                    } else {
                        .progress(met: count.met, of: count.of)
                    }
                lines[deck.name] = line
            }
            return (lines: lines, places: inReviews.topDecksInQueueOrder)
        }
    }
}

extension CardsWindowState.DeckRow: DeckInTree {}

extension CountedDeck {
    /// The deck `name`, with nothing of its own, which counts no card.
    fileprivate static func empty(_ name: String) -> CountedDeck {
        CountedDeck(deck: Deck(name: name), counts: DeckCounts(cards: 0, due: 0))
    }
}
