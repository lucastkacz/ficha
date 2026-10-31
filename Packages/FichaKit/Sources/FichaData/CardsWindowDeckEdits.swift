import FichaCore
import Foundation

// Renaming, moving and deleting decks in the Cards window (ADR 0024), as the
// engine does them (`RenamingDecks.swift`, `DeletingDecks.swift`). A deck's
// menu, in the sidebar and in the Actions menu above the card list, which is
// its keyboard path, offers Rename…, which asks for the deck's whole name in
// the rename sheet, so that a name with other levels moves it, as a drop
// does, and Delete…, which asks first, saying how many cards and decks it
// deletes; Default's offers neither. In the sidebar, cards dropped on a deck
// move there, as Change Deck moves them, and a deck dropped on another goes
// inside it, or to the top when it's dropped on the Decks section's title.
// The window follows a deck it holds by name to its new one: the deck the
// sidebar chose, the decks it closed, the deck the card form and the editor
// hold, and the one the last card was added to; and lets go of one deleted.
// It does so as it reads the cards again, after each change to decks this
// device applied since it last read them (`DeckChangesSince`), whoever made
// it: the window itself, the `ficha` CLI on the same database, or another
// device, heard in a fetch; so that Add or Save never makes a deck again
// under a name it no longer has.

extension CardsWindowState.DeckMenu {
    /// Whether the menu offers Rename… and Delete…: for every deck but
    /// Default, which is never renamed, moved or deleted.
    public var offersRenameAndDelete: Bool {
        !deck.isDefault
    }
}

extension CardsWindowState.DeckRow {
    /// Whether Lucas can drag its row, to drop it on another deck or on the
    /// Decks section's title: every deck but Default.
    public var isDraggable: Bool {
        !deck.isDefault
    }
}

extension CardsWindowState {
    /// Asks which name the deck `deck` gets, in the rename sheet, after
    /// Rename… in its menu, while the menu offers it.
    public mutating func askToRenameDeck(_ deck: String) {
        guard let menu = menu(forDeck: deck), menu.offersRenameAndDelete else { return }
        question = .renameDeck(menu.deck)
    }

    /// `text`, what the rename sheet's field holds for the deck `deck`, as OK
    /// takes it: the deck's new whole name, its levels cleaned up, or a
    /// refusal of a blank name, one whose top level is one of Default's, or
    /// one inside the deck itself, as the engine refuses them.
    func deckNameEntry(_ text: String, renaming deck: String) -> RenameEntry {
        do throws(EngineError) {
            return .name(try checkedDeckName(renaming: deck, to: text))
        } catch {
            return .refused(error)
        }
    }

    /// Renames the deck `deck` to `name`, and every deck inside it, for
    /// `action`, and reads the cards again, the window following it to its
    /// new name; or records why it couldn't. Whether it did.
    mutating func renameDeck(_ deck: String, to name: String, as action: FailedAction) -> Bool {
        let done = perform(action) { engine throws(EngineError) in
            try engine.renameDeck(deck, to: name)
        }
        if done {
            read(on: ladder)
        }
        return done
    }

    /// Asks whether to delete the deck `deck`, with every deck inside it and
    /// every card in them, saying what that does on this device, after
    /// Delete… in its menu, while the menu offers it; or records why it
    /// couldn't count them.
    public mutating func askToDeleteDeck(_ deck: String) {
        guard let menu = menu(forDeck: deck), menu.offersRenameAndDelete else { return }
        var deletion: DeckDeletion?
        let counted = perform(.deleteDeck(deck: deck)) { engine throws(EngineError) in
            deletion = try engine.deletion(ofDeck: deck)
        }
        if counted, let deletion {
            question = .deleteDeck(deletion)
        }
    }

    /// Deletes the deck of `deletion`, which the window asked about and Lucas
    /// confirmed, with every deck inside it and every card in them, and
    /// reads the cards again, the window letting go of them; or records why
    /// it couldn't. The dialog hands `deletion` back, as Delete's hands its
    /// cards.
    public mutating func deleteDeck(_ deletion: DeckDeletion) {
        question = nil
        let done = perform(.deleteDeck(deck: deletion.deck)) { engine throws(EngineError) in
            try engine.deleteDeck(deletion.deck)
        }
        if done {
            read(on: ladder)
        }
    }

    /// What Lucas drags onto the sidebar's decks: a card of the card list, by
    /// its id, each of the selected ones when he drags one of them, or a
    /// deck's row, by its whole name.
    public enum Dragged: Sendable, Hashable, Codable {
        case card(CardRow.ID)
        case deck(String)
    }

    /// Drops `dragged`, what Lucas drags, on the sidebar's deck `deck`,
    /// Default too: cards move there, a deck goes inside it. Whether it took
    /// the drop, as `dropCards(_:onDeck:)` and `dropDeck(_:onDeck:)` say,
    /// and never for a drop of cards with a deck, of several decks or of
    /// nothing, which it refuses without a word, as what's dragged goes back.
    @discardableResult
    public mutating func drop(_ dragged: [Dragged], onDeck deck: String) -> Bool {
        switch Self.drop(of: dragged) {
        case .cards(let cardIDs)?: dropCards(cardIDs, onDeck: deck)
        case .deck(let dropped)?: dropDeck(dropped, onDeck: deck)
        case nil: false
        }
    }

    /// Drops `dragged`, what Lucas drags, on the Decks section's title: a
    /// deck goes to the top. Whether it took the drop, as
    /// `dropDeckOnDecksTitle(_:)` says, and never for cards, which go in no
    /// deck there, nor for a drop `drop(_:onDeck:)` refuses.
    @discardableResult
    public mutating func dropOnDecksTitle(_ dragged: [Dragged]) -> Bool {
        guard case .deck(let dropped)? = Self.drop(of: dragged) else { return false }
        return dropDeckOnDecksTitle(dropped)
    }

    /// What a drop of `dragged` drops: cards alone, or one deck alone; or nil
    /// for anything else.
    private static func drop(of dragged: [Dragged]) -> Drop? {
        var cardIDs: [CardRow.ID] = []
        var decks: [String] = []
        for item in dragged {
            switch item {
            case .card(let id): cardIDs.append(id)
            case .deck(let deck): decks.append(deck)
            }
        }
        if decks.isEmpty, !cardIDs.isEmpty {
            return .cards(cardIDs)
        }
        if cardIDs.isEmpty, decks.count == 1, let deck = decks.first {
            return .deck(deck)
        }
        return nil
    }

    /// What a drop the sidebar takes drops.
    private enum Drop {
        case cards([CardRow.ID])
        case deck(String)
    }

    /// Drops the cards with the ids `cardIDs`, which Lucas drags from the
    /// card list, on the sidebar's deck `deck`, Default too: those the table
    /// lists move there, as Change Deck moves them, in one go, and the window
    /// reads the cards again. Whether it took the drop: not while he edits a
    /// card, nor when none of them would move, nor when the engine couldn't
    /// move them, which it records.
    private mutating func dropCards(_ cardIDs: [CardRow.ID], onDeck deck: String) -> Bool {
        guard editing == nil, listedDeck(deck) != nil, case .success(.cards(let rows))? = listing else {
            return false
        }
        let moving = Set(rows.filter { cardIDs.contains($0.id) && $0.card.deck != deck }.map(\.id))
        guard !moving.isEmpty else {
            return false
        }
        let done = perform(.changeDeck(cardCount: moving.count)) { engine throws(EngineError) in
            try engine.changeDeck(of: moving, to: deck)
        }
        if done {
            read(on: ladder)
        }
        return done
    }

    /// Drops the sidebar's deck `deck` on its deck `target`: it moves inside
    /// it, as `Engine.moveDeck(_:into:)` moves it, joining a deck of its name
    /// there if there's one; then the window follows it, opens `target` and
    /// the decks it sits inside, and reads the cards again. Whether it took
    /// the drop: never for Default, which stays where it is, nor on Default,
    /// which no deck sits inside, nor on the deck itself or a deck inside it,
    /// nor on the deck it sits right inside already, all of which it refuses
    /// without a word, as the row goes back; nor when the engine couldn't
    /// move it, which it records.
    private mutating func dropDeck(_ deck: String, onDeck target: String) -> Bool {
        guard listedDeck(deck) != nil, listedDeck(target) != nil, deck != Deck.defaultName,
            target != Deck.defaultName, !TagPath.isTag(target, within: deck), TagPath.parent(of: deck) != target
        else {
            return false
        }
        return moveDeck(deck, into: target)
    }

    /// Drops the sidebar's deck `deck` on the Decks section's title: it moves
    /// to the top, as `dropDeck(_:onDeck:)` moves a deck inside another.
    /// Whether it took the drop: never for Default, nor for a deck at the top
    /// already, nor when the engine couldn't move it, which it records.
    private mutating func dropDeckOnDecksTitle(_ deck: String) -> Bool {
        guard listedDeck(deck) != nil, deck != Deck.defaultName, TagPath.parent(of: deck) != nil else {
            return false
        }
        return moveDeck(deck, into: nil)
    }

    /// Moves the deck `deck` inside `parent`, or to the top when it's nil, as
    /// a drop does, and reads the cards again, the window following it, with
    /// `parent` and the decks it sits inside open; or records why it
    /// couldn't. Whether it did.
    private mutating func moveDeck(_ deck: String, into parent: String?) -> Bool {
        let done = perform(.moveDeck(deck: deck)) { engine throws(EngineError) in
            try engine.moveDeck(deck, into: parent)
        }
        guard done else {
            return false
        }
        if let parent {
            closedDecks.subtract(TagPath.lineage(of: parent))
        }
        read(on: ladder)
        return true
    }

    /// Points what the window holds of decks by name at their names after
    /// `changes`, the renames and deletions of decks since it last read the
    /// cards, whoever made them, as it reads them, once it read the decks
    /// (`DeckChangesSince.name(of:)`): the deck the sidebar chose, the decks
    /// it closed, the deck the card form holds, and the one Show Card set
    /// aside, the editor's, and the one the last card was added to. A deck
    /// deleted lets go: the sidebar goes back to All cards, the forms' decks
    /// to the deck a new card starts in, and the editor's and the one the
    /// last card was added to, to Default.
    mutating func follow(_ changes: DeckChangesSince) {
        lastDeckChangeFollowed = changes.last
        guard !changes.new.isEmpty else { return }
        if case .cards(.deck(let chosen)) = sidebarItem {
            sidebarItem = changes.name(of: chosen).map { .cards(.deck($0)) } ?? .cards(.all)
        }
        closedDecks = Set(closedDecks.compactMap(changes.name(of:)))
        editedDeck = changes.name(of: editedDeck) ?? Deck.defaultName
        lastDeckAddedTo = changes.name(of: lastDeckAddedTo) ?? Deck.defaultName
        let startingDeck = deckANewCardStartsIn
        if let formsDeck = cardForm?.draft.deck {
            cardForm?.draft.deck = changes.name(of: formsDeck) ?? startingDeck
        }
        if let setAsideFormsDeck = setAsideCardForm?.draft.deck {
            setAsideCardForm?.draft.deck = changes.name(of: setAsideFormsDeck) ?? startingDeck
        }
    }
}
