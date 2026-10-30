import FichaCore
import Foundation

// The Cards window's decks (ADR 0024): the sidebar's Decks section, after
// Inbox and before Tags, lists every deck as a tree, Default first while it
// holds cards, then the others in alphabetical order, each with how many of
// its cards are due, those of the decks inside it counted. Each parent starts
// open, as in Anki's deck list, and the window remembers the ones Lucas
// closes while it's open. Choosing a deck lists its cards and those of every
// deck inside it. Change Deck… moves the selected cards to the deck Lucas
// picks in its sheet, from the same tree with Default always in it, or to one
// he names there with New Deck…, which the move makes. The Deck field, in the
// card form and the editor (`CardsWindowDeckField.swift`), offers that tree
// too, and its New Deck… names a deck in the New Deck sheet with the same
// name field and the same checks, for the field to hold.

extension CardsWindowState {
    /// A deck in the sidebar's tree, or in the Change Deck sheet's, with the
    /// decks right inside it, which a disclosure triangle shows.
    public struct DeckRow: Sendable, Equatable, Identifiable {
        /// The deck, with what it has of its own and takes from the decks it
        /// sits inside.
        public let deck: Deck
        /// What its row says: its last level under its parent, or nothing for
        /// Default, which the window names in the Mac's language.
        public let title: String
        /// How many cards it lists and how many of those are due, counting
        /// the decks inside it: none for a deck New Deck… named, which the
        /// move makes.
        public let counts: DeckCounts
        /// The decks right inside it, in the order a tree lists them.
        public let children: [DeckRow]

        public var id: String {
            deck.name
        }

        /// What choosing it in the sidebar lists: its cards, and those of
        /// every deck inside it.
        public var item: SidebarItem {
            .cards(.deck(deck.name))
        }

        /// It, and every row inside it, in the order a tree lists them.
        var flattened: [DeckRow] {
            [self] + children.flatMap(\.flattened)
        }
    }

    /// What Change Deck… asks, in its sheet, while it asks: which deck the
    /// selected cards move to.
    public struct DeckChange: Sendable, Equatable {
        /// The cards it moves, as the table listed them when Lucas chose
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

    /// What OK makes of what the Change Deck sheet's name field holds, after
    /// New Deck….
    public enum NewDeckEntry: Sendable, Equatable {
        /// The deck's whole name, its levels cleaned up.
        case name(String)
        /// A name with no level, blank or only `::`, as the field starts,
        /// which keeps OK off, and which the sheet doesn't call a mistake.
        case blankName
        /// A name OK refuses, and why, for the sheet to say: one whose top
        /// level is one of Default's names.
        case refused(EngineError)
    }

    /// The sidebar's Decks section, as last read: every deck as a tree,
    /// Default first while it holds cards, each with its counts.
    public var deckRows: [DeckRow] {
        Self.deckRows(of: decks)
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
        return Self.deckRows(of: defaultDeck + decks + others.map(CountedDeck.empty))
    }

    /// Asks which deck the selected cards the table lists move to, in the
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
    /// in the Change Deck sheet or in the New Deck sheet a Deck field opens
    /// (`CardsWindowDeckField.swift`): the deck's whole name, its levels
    /// cleaned up; a blank name, as the field starts, which keeps OK off; or
    /// a refusal of a name whose top level is one of Default's, as the engine
    /// refuses it. Nil while the window asks for no new deck's name.
    public func newDeckEntry(_ text: String) -> NewDeckEntry? {
        switch question {
        case .changeDeck(let change): guard change.isNamingNewDeck else { return nil }
        case .newDeck: break
        default: return nil
        }
        do throws(EngineError) {
            return .name(try checkedDeckName(text))
        } catch .blankDeckName {
            return .blankName
        } catch {
            return .refused(error)
        }
    }

    /// Chooses OK after New Deck…, whose name field holds `text`: the
    /// sheet's tree lists the deck, with the decks it sits inside, and
    /// chooses it, for Move to make it as it moves the cards there; or, in
    /// the New Deck sheet, the Deck field it was asked from holds the deck
    /// (`CardsWindowDeckField.swift`). A deck already listed is chosen.
    /// While OK doesn't take `text`, as `newDeckEntry(_:)` says, it does
    /// nothing, and the sheet says why.
    public mutating func chooseNewDeck(_ text: String) {
        guard case .name(let name)? = newDeckEntry(text) else { return }
        if case .newDeck(let fields) = question {
            question = nil
            putInDeckField(name, fields)
            return
        }
        guard case .changeDeck(var change) = question else { return }
        if !change.newDecks.contains(name) {
            change.newDecks.append(name)
        }
        change.chosenDeck = name
        change.isNamingNewDeck = false
        question = .changeDeck(change)
    }

    /// Goes back to the Change Deck sheet's tree from the name New Deck…
    /// asked for, which Lucas cancelled.
    public mutating func cancelNewDeck() {
        guard case .changeDeck(var change) = question else { return }
        change.isNamingNewDeck = false
        question = .changeDeck(change)
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
            read(on: ladder)
        }
    }

    /// The rows of `decks`, as a tree, in the order a tree lists them, each
    /// named by its last level under its parent.
    private static func deckRows(of decks: [CountedDeck]) -> [DeckRow] {
        let byName = Dictionary(decks.map { ($0.deck.name, $0) }, uniquingKeysWith: { first, _ in first })
        /// The rows of `trees`, listed under `parent`.
        func rows(of trees: [TagTree], under parent: String?) -> [DeckRow] {
            trees.compactMap { tree in
                // The forest holds `decks`' names alone, so each tree finds
                // its own.
                guard let counted = byName[tree.name] else { return nil }
                return DeckRow(
                    deck: counted.deck, title: TagPath.shown(tree.name, under: parent), counts: counted.counts,
                    children: rows(of: tree.children, under: tree.name))
            }
        }
        return rows(of: TagTree.forest(of: decks.map(\.deck.name)), under: nil)
    }
}

extension CountedDeck {
    /// The deck `name`, with nothing of its own, which counts no card.
    fileprivate static func empty(_ name: String) -> CountedDeck {
        CountedDeck(deck: Deck(name: name), counts: DeckCounts(cards: 0, due: 0))
    }
}
