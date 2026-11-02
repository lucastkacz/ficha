import FichaCore
import Foundation
internal import GRDB

// A deck's switch (ADR 0011, ADR 0024): Set Aside takes the deck's cards,
// and those of every deck inside it, out of the user's reviews for now, and
// Prioritize brings them first when cards show up. A deck has one on at
// most, so setting aside a priority deck drops its priority, and a deck set
// aside, on its own or inside a deck that is, can't become a priority deck.
// The Cards window's deck menu and the menu bar's Prioritize submenu, which
// lists every deck as a tree, set them. Where a card stands and which cards
// come first read the switches in `CardsInReviews.swift`, which the merge
// gate watches; a tag's switch, kept from before decks, counts nowhere.

extension Deck {
    /// Whether it's set aside on its own: every card that lives in it, or in
    /// a deck inside it, is out of the user's reviews for now.
    public var isSetAside: Bool {
        switchedOn == .setAside
    }

    /// Whether it's a priority deck: every card that lives in it, or in a deck
    /// inside it, comes first when cards show up.
    public var isPriority: Bool {
        switchedOn == .priority
    }

    /// The deck that keeps it from becoming a priority deck while the decks
    /// named `setAside` are set aside: itself, when it's set aside on its
    /// own, or else the nearest deck it sits inside that is, since its cards
    /// are out of the user's reviews and a deck is never both (ADR 0011). Nil
    /// while none is, and while it's a priority deck already, so that the
    /// user can untick it. The one rule for the Prioritize submenu, the Cards
    /// window and the engine.
    func deckKeepingItFromPriority(amongSetAside setAside: Set<String>) -> String? {
        guard !isPriority else { return nil }
        return deckSettingAside(name, amongSetAside: setAside)
    }

    /// Whether Prioritize is on for it while the decks named `setAside` are
    /// set aside: unless one keeps it from becoming a priority deck, as
    /// `deckKeepingItFromPriority(amongSetAside:)` says.
    func canBePrioritized(amongSetAside setAside: Set<String>) -> Bool {
        deckKeepingItFromPriority(amongSetAside: setAside) == nil
    }
}

extension Sequence<Deck> {
    /// The names of the decks among these set aside on their own.
    var setAsideNames: Set<String> {
        Set(filter(\.isSetAside).map(\.name))
    }
}

/// The name of the deck that sets aside the cards of the deck `name` while
/// the decks named `setAside` are set aside on their own: the innermost of
/// those that set aside a card in it (`CardStanding.setAsideDecks(of:among:)`),
/// itself when it's one, or else the nearest deck it sits inside that is;
/// nil while none is. The one rule for graying a deck and for keeping it from
/// becoming a priority deck.
func deckSettingAside(_ name: String, amongSetAside setAside: Set<String>) -> String? {
    CardStanding.setAsideDecks(of: name, among: setAside).last
}

/// What the menu bar's Prioritize submenu offers, as the engine reads it:
/// "None", then every deck as a tree, Default first while it holds cards or
/// has a switch on, with a submenu for each parent, which lists the parent
/// itself first and then the decks right inside it.
public struct PrioritizeMenu: Sendable, Equatable {
    /// A deck the submenu offers, ticked while it's a priority deck, which
    /// toggles it, with the decks right inside it.
    public struct DeckItem: Sendable, Equatable, Identifiable {
        /// The deck, with what it has of its own and takes from the decks it
        /// sits inside.
        public let deck: Deck
        /// What it says: its last level under its parent, or nothing for
        /// Default, which the app names in the Mac's language.
        public let title: String
        /// Whether it's on: unless it's set aside, on its own or inside a deck
        /// that is, since a deck is never both (ADR 0011), but a priority
        /// deck always is, to untick.
        public let isEnabled: Bool
        /// The decks right inside it, in the order a tree lists them, which
        /// its submenu lists after it.
        public let children: [DeckItem]

        public var id: String {
            deck.name
        }

        /// Whether it's ticked: it's a priority deck.
        public var isTicked: Bool {
            deck.isPriority
        }
    }

    /// The decks it offers after "None", as a tree.
    public let decks: [DeckItem]

    /// Whether "None" is ticked: no deck is a priority deck.
    public var isNoneTicked: Bool {
        priorityDeckNames.isEmpty
    }

    /// The priority decks' names, in the order a tree lists them, which its
    /// title names while there are some.
    public var priorityDeckNames: [String] {
        decks.flatMap(\.flattened).filter(\.isTicked).map(\.id)
    }
}

extension PrioritizeMenu.DeckItem: DeckInTree {}

extension Engine {
    /// What the menu bar's Prioritize submenu offers: every deck this device
    /// lists (`decks()`), as a tree, each ticked while it's a priority deck,
    /// and off while it's set aside, on its own or inside a deck that is,
    /// unless it's a priority deck, to untick.
    public func prioritizeMenu() throws(EngineError) -> PrioritizeMenu {
        let decks = try self.decks()
        let setAside = decks.setAsideNames
        return PrioritizeMenu(
            decks: deckTree(of: decks, named: \.name) { deck, title, children in
                PrioritizeMenu.DeckItem(
                    deck: deck, title: title, isEnabled: deck.canBePrioritized(amongSetAside: setAside),
                    children: children)
            })
    }

    /// Sets the deck `deck` aside, by its whole name, or Default by
    /// `Deck.defaultName`: every card that lives in it, or in a deck inside
    /// it, leaves the user's reviews for now, also cards that move in later,
    /// unless it's buried or flagged. A priority deck is no longer one. Its
    /// cards keep their progress, and their intervals keep running. A deck that
    /// isn't there is made, as Change Deck makes one, and a name
    /// `makeDeck(named:)` refuses is refused.
    public func setAside(deck: String) throws(EngineError) {
        let deck = try checkedDeckOrDefault(deck)
        try write { db in
            try changeOwnDecks([deck], in: db) { $0.switchedOn = .setAside }
        }
    }

    /// Stops setting the deck `deck` aside: its cards come back to the user's
    /// reviews where they'd be without it, unless a deck it sits inside is
    /// set aside too. A deck that isn't set aside stays as it is.
    public func stopSettingAside(deck: String) throws(EngineError) {
        let deck = try checkedDeckOrDefault(deck)
        try write { db in
            try changeOwnDecks([deck], in: db) { own in
                if own.isSetAside {
                    own.switchedOn = nil
                }
            }
        }
    }

    /// Toggles the deck `deck`'s priority, as the Prioritize submenu does: a
    /// priority deck is no longer one, and any other becomes one, as
    /// `setPriority(_:ofDeck:)` says.
    public func togglePriority(ofDeck deck: String) throws(EngineError) {
        let deck = try checkedDeckOrDefault(deck)
        try write { db in
            try setPriority(try !ownDeck(deck, in: db).isPriority, of: deck, in: db)
        }
    }

    /// Makes the deck `deck` a priority deck, so that its cards, and those of
    /// every deck inside it, come first from the next appearance, review now
    /// or "See more" on, or no longer one, whatever it was. A deck set aside,
    /// on its own or inside a deck that is, can't become one, since its cards
    /// are out of the reviews and a deck is never both (ADR 0011), so the
    /// window and the submenu don't offer it, and the engine refuses it,
    /// naming the set-aside deck, as when another device set it aside
    /// meanwhile. A deck that isn't there is made, as `setAside(deck:)`
    /// says.
    public func setPriority(_ isPriority: Bool, ofDeck deck: String) throws(EngineError) {
        let deck = try checkedDeckOrDefault(deck)
        try write { db in
            try setPriority(isPriority, of: deck, in: db)
        }
    }

    /// Makes every priority deck no longer one, as the Prioritize submenu's
    /// "None" does, so the cards come in their usual order from the next
    /// appearance, review now or "See more" on.
    public func clearPriorityDecks() throws(EngineError) {
        try write { db in
            for deck in try FichaData.decks(switchedOn: .priority, in: db).sorted() {
                try changeOwnDecks([deck], in: db) { $0.switchedOn = nil }
            }
        }
    }

    /// Makes the deck `deck` a priority deck, or no longer one, in the write
    /// `db`, as `setPriority(_:ofDeck:)` says.
    private func setPriority(_ isPriority: Bool, of deck: String, in db: Database) throws {
        let setAside = try setAsideDecks(in: db)
        try changeOwnDecks([deck], in: db) { own in
            switch (own.switchedOn, isPriority) {
            case (.setAside, false), (.priority, true), (nil, false): return
            case (.priority, false): own.switchedOn = nil
            case (.setAside, true), (nil, true):
                if let setAsideDeck = own.deckKeepingItFromPriority(amongSetAside: setAside) {
                    throw EngineError.deckSetAside(setAsideDeck)
                }
                own.switchedOn = .priority
            }
        }
    }
}
