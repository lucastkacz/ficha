import FichaCore
import Foundation

// A deck's description in the Cards window (ADR 0044, #557): it shows above
// the deck's cards, in the bar above the grid, its own alone, which the decks
// inside it never take, and Description…, among the deck's actions, edits it
// in place, one or two lines, as Emoji… gives the deck its emoji
// (`CardsWindowDecks.swift`), through `Engine.setDescription(_:ofDeck:)`.
// One of Ficha's decks shows the description its `deck.json` holds in the
// grid's place before it's added (`FichaDeckFile.description`).

extension CardsWindowState {
    /// The deck whose description Description… edits in place, as the window
    /// last read it, whose field starts with the deck's own description: nil
    /// while it edits none. The sidebar chose it, and the field shows above
    /// its cards, in the description's place.
    public var describedDeck: Deck? {
        describedDeckName.flatMap { listedDeck($0) }
    }

    /// The description the bar above the grid shows under the name of the
    /// deck the sidebar chose: its own alone, as last read; nil while it has
    /// none, while the sidebar chose something else, and while Description…
    /// edits it, whose field shows in its place.
    public var chosenDeckDescription: String? {
        guard let deck = chosenDeckMenu?.deck, describedDeckName != deck.name else { return nil }
        return deck.description
    }

    /// Chooses Description… in the menu of the deck `deck`, by its whole name,
    /// or Default's by `Deck.defaultName`, while the sidebar lists it: the
    /// sidebar chooses the deck, and its description shows as a field, in
    /// place, which `describedDeck` says.
    public mutating func askForDescription(onDeck deck: String) {
        guard listedDeck(deck) != nil else { return }
        choose(.cards(.deck(deck)))
        describedDeckName = deck
    }

    /// Why Done refuses `text`, what the field of the deck Description… edits
    /// holds, for the field to say: a description longer than
    /// `Deck.longestDescription`, as the engine refuses it; nil while Done
    /// takes it.
    public func descriptionRefusal(_ text: String) -> EngineError? {
        do throws(EngineError) {
            _ = try Deck.checkedDescription(text)
            return nil
        } catch {
            return error
        }
    }

    /// Chooses Done in the field of the deck Description… edits, which holds
    /// `text`: gives the deck that description, without the spaces and line
    /// breaks around it, or takes its own away when `text` is blank, as
    /// `Engine.setDescription(_:ofDeck:)` does, ends the edit and reads the
    /// cards again; or records why it couldn't, as for a description longer
    /// than `Deck.longestDescription`, and goes on with the edit.
    public mutating func chooseDescription(_ text: String) {
        guard let deck = describedDeck else { return }
        let done = perform(.setDeckDescription(deck: deck.name)) { engine throws(EngineError) in
            try engine.setDescription(text, ofDeck: deck.name)
        }
        guard done else { return }
        describedDeckName = nil
        readAgain()
        askForTheFichaDeckAskedToAdd()
    }

    /// Chooses Cancel in the field of the deck Description… edits: ends the
    /// edit, leaving the deck's description as it was.
    public mutating func cancelDescription() {
        describedDeckName = nil
        askForTheFichaDeckAskedToAdd()
    }
}
