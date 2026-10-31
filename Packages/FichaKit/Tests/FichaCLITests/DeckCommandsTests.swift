import ArgumentParser
import FichaCore
import FichaData
import Foundation
import Testing

// For the commands, which the CLI parses from its arguments and runs on the
// engine, and the JSON it prints their results as.
@testable import FichaCLI

/// Tests on the `ficha` CLI's control of decks (ADR 0024), and on its
/// conversion of tags into decks: each command parsed from its arguments, as
/// a refine session types them, run on an engine in memory, and the JSON it
/// prints.
struct DeckCommandsTests {
    let engine: Engine

    init() throws {
        engine = try Engine(location: .inMemory, time: ManualTimeSource(now: Date(timeIntervalSince1970: 0)))
    }

    // Libros is purple and chosen to sync, Libros::Argentina has an emoji,
    // and Historia is set aside with no card. Default holds Rosas.
    @Test(
        "`ficha decks` prints every deck in tree order, Default first by its empty name, with its counts and what it has of its own"
    )
    func decksPrintsEveryDeck() async throws {
        try approveCard("Martín Fierro", deck: "Libros::Argentina")
        try approveCard("Facundo", deck: "Libros")
        try approveCard("Rosas", deck: Deck.defaultName)
        try engine.setColor(.purple, ofDeck: "Libros")
        try engine.setEmoji(Emoji("📚"), ofDeck: "Libros::Argentina")
        try engine.setAside(deck: "Historia")
        try engine.setChosenToSync(true, ofDeck: "Libros")

        let printed = try await ficha("decks")

        #expect(
            printed == """
                [
                  {
                    "cards" : 1,
                    "chosenToSync" : false,
                    "due" : 0,
                    "name" : "",
                    "priority" : false,
                    "setAside" : false
                  },
                  {
                    "cards" : 0,
                    "chosenToSync" : false,
                    "due" : 0,
                    "name" : "Historia",
                    "priority" : false,
                    "setAside" : true
                  },
                  {
                    "cards" : 2,
                    "chosenToSync" : true,
                    "color" : "purple",
                    "due" : 0,
                    "name" : "Libros",
                    "priority" : false,
                    "setAside" : false
                  },
                  {
                    "cards" : 1,
                    "chosenToSync" : false,
                    "due" : 0,
                    "emoji" : "📚",
                    "name" : "Libros::Argentina",
                    "priority" : false,
                    "setAside" : false
                  }
                ]
                """)
    }

    @Test("`ficha decks` lists Default while it holds no card, so that it can be chosen to sync")
    func decksListsAnEmptyDefault() async throws {
        try engine.makeDeck(named: "Arte")

        #expect(try await decks(from: ficha("decks")).map(\.name) == [Deck.defaultName, "Arte"])
    }

    // Arte::Pintura holds La Gioconda; Historia exists with no card.
    @Test(
        "`ficha deck make`, `rename` and `delete` make a deck, rename it with the decks inside it, and delete it with its cards, printing each"
    )
    func makingRenamingAndDeletingADeck() async throws {
        let made = try await deck(from: ficha("deck", "make", " Historia "))
        try approveCard("La Gioconda", deck: "Arte::Pintura")
        try engine.setColor(.blue, ofDeck: "Arte")

        let renamed = try await decks(from: ficha("deck", "rename", "Arte", "Historia::Arte"))
        let deleted = try await ficha("deck", "delete", "Historia")

        #expect(made == DeckAsPrinted(name: "Historia"))
        #expect(renamed.map(\.name) == ["Historia::Arte", "Historia::Arte::Pintura"])
        #expect(renamed.map(\.color) == ["blue", nil])
        #expect(renamed.map(\.cards) == [1, 1])
        #expect(
            deleted == """
                {
                  "cards" : 1,
                  "deck" : "Historia",
                  "decksInside" : [
                    "Historia::Arte",
                    "Historia::Arte::Pintura"
                  ]
                }
                """)
        #expect(try engine.cards().isEmpty)
        #expect(try await decks(from: ficha("decks")).map(\.name) == [Deck.defaultName])
    }

    @Test(
        "`ficha deck set-aside`, `prioritize`, `color`, `emoji` and `choose-to-sync` change a deck's own, Default's too, take it away with --off or none, and print it"
    )
    func changingWhatADeckHasOfItsOwn() async throws {
        try approveCard("Martín Fierro", deck: "Libros")

        let setAside = try await deck(from: ficha("deck", "set-aside", "Libros"))
        let notSetAside = try await deck(from: ficha("deck", "set-aside", "Libros", "--off"))
        let priority = try await deck(from: ficha("deck", "prioritize", "Libros"))
        let colored = try await deck(from: ficha("deck", "color", "Libros", "green"))
        let withEmoji = try await deck(from: ficha("deck", "emoji", "Libros", "📚"))
        let chosen = try await deck(from: ficha("deck", "choose-to-sync", "Libros"))
        let defaultChosen = try await deck(from: ficha("deck", "choose-to-sync", ""))
        let none = [
            try await deck(from: ficha("deck", "prioritize", "Libros", "--off")),
            try await deck(from: ficha("deck", "color", "Libros", "none")),
            try await deck(from: ficha("deck", "emoji", "Libros", "none")),
            try await deck(from: ficha("deck", "choose-to-sync", "Libros", "--off")),
        ]

        #expect(setAside.setAside && !setAside.priority)
        #expect(!notSetAside.setAside)
        #expect(priority.priority)
        #expect(colored.color == "green")
        #expect(withEmoji.emoji == "📚")
        #expect(chosen.chosenToSync)
        #expect(defaultChosen == DeckAsPrinted(name: Deck.defaultName, chosenToSync: true))
        #expect(none.last == DeckAsPrinted(name: "Libros", cards: 1))
        #expect(none.map(\.priority) == [false, false, false, false])
        #expect(none.map(\.color) == ["green", nil, nil, nil])
    }

    @Test(
        "a deck command refuses what the app refuses: a blank name, Default's name, a deck inside itself, Default renamed or deleted, a set-aside deck prioritized, and a deck that isn't there"
    )
    func aDeckCommandRefuses() async throws {
        try approveCard("La Gioconda", deck: "Arte::Pintura")
        try engine.setAside(deck: "Arte")

        await #expect(throws: EngineError.blankDeckName) { try await ficha("deck", "make", " :: ") }
        await #expect(throws: EngineError.defaultDeckName("Default")) { try await ficha("deck", "make", "Default") }
        await #expect(throws: EngineError.deckInsideItself("Arte")) {
            try await ficha("deck", "rename", "Arte", "Arte::Pintura::Arte")
        }
        await #expect(throws: EngineError.defaultDeckStays) { try await ficha("deck", "rename", "", "Arte") }
        await #expect(throws: EngineError.defaultDeckStays) { try await ficha("deck", "delete", "") }
        await #expect(throws: EngineError.deckSetAside("Arte")) {
            try await ficha("deck", "prioritize", "Arte::Pintura")
        }
        await #expect(throws: UnknownDeckError.self) { try await ficha("deck", "color", "Música", "red") }
        #expect(throws: (any Error).self) { try FichaCommand.parseAsRoot(["deck", "color", "Arte", "pink"]) }
        #expect(try await decks(from: ficha("decks")).map(\.name) == [Deck.defaultName, "Arte", "Arte::Pintura"])
        #expect(try engine.cards().map(\.deck) == ["Arte::Pintura"])
    }

    @Test("`ficha change-deck` moves cards to a deck, made if it isn't there, or to Default, and prints them")
    func changingCardsDeck() async throws {
        let fierro = try approveCard("Martín Fierro", deck: Deck.defaultName)
        let facundo = try approveCard("Facundo", deck: "Libros")

        let moved = try await cards(
            from: ficha("change-deck", "\(fierro.id)", "\(facundo.id)", "--to", "Libros::Argentina"))
        let back = try await cards(from: ficha("change-deck", "\(facundo.id)", "--to", ""))

        #expect(moved.map(\.deck) == ["Libros::Argentina", "Libros::Argentina"])
        #expect(back.map(\.deck) == [Deck.defaultName])
        await #expect(throws: EngineError.cardNotFound(99)) { try await ficha("change-deck", "99", "--to", "Libros") }
    }

    // Martín Fierro carries two tags of the list; Rosas carries historia
    // alone. A deck historia is there already, chosen to sync.
    @Test(
        "`ficha tag convert-to-decks --preview` prints what turning tags into decks would do, changing nothing, and without it the tags become decks"
    )
    func convertingTagsToDecks() async throws {
        let fierro = try approveCard("Martín Fierro", deck: Deck.defaultName, tags: ["literatura::poesía", "historia"])
        try approveCard("Rosas", deck: Deck.defaultName, tags: ["historia"])
        try engine.setChosenToSync(true, ofDeck: "historia")

        let preview = try await ficha("tag", "convert-to-decks", "literatura", "historia", "--preview")
        let decksBefore = try engine.decks()
        let converted = try await ficha("tag", "convert-to-decks", "literatura", "historia")

        #expect(
            preview == """
                {
                  "cardsWithTwoTags" : [
                    {
                      "deck" : "literatura::poesía",
                      "front" : "Martín Fierro",
                      "id" : \(fierro.id),
                      "tags" : [
                        "literatura::poesía",
                        "historia"
                      ]
                    }
                  ],
                  "decks" : [
                    {
                      "cards" : 1,
                      "chosenToSync" : true,
                      "name" : "historia"
                    },
                    {
                      "cards" : 0,
                      "chosenToSync" : false,
                      "name" : "literatura"
                    },
                    {
                      "cards" : 1,
                      "chosenToSync" : false,
                      "name" : "literatura::poesía"
                    }
                  ]
                }
                """)
        #expect(decksBefore.map(\.name) == [Deck.defaultName, "historia"])
        #expect(converted == preview)
        #expect(try engine.cards().map(\.deck) == ["literatura::poesía", "historia"])
        #expect(try engine.cards().map(\.tags) == [["historia"], []])
        await #expect(throws: UnknownTagError.self) { try await ficha("tag", "convert-to-decks", "economía") }
    }

    /// Runs `ficha` with `arguments` on the engine, as the CLI parses and
    /// runs them, and returns the JSON it prints.
    @discardableResult
    private func ficha(_ arguments: String...) async throws -> String {
        let command = try FichaCommand.parseAsRoot(arguments)
        let engineCommand = try #require(command as? any EngineCommand)
        return try json(await engineCommand.run(on: engine))
    }

    /// The decks `printed` lists, as a command prints them.
    private func decks(from printed: String) throws -> [DeckAsPrinted] {
        try JSONDecoder().decode([DeckAsPrinted].self, from: Data(printed.utf8))
    }

    /// The deck `printed` holds, as a command prints it.
    private func deck(from printed: String) throws -> DeckAsPrinted {
        try JSONDecoder().decode(DeckAsPrinted.self, from: Data(printed.utf8))
    }

    /// The cards `printed` lists, by their decks, as `ficha cards` prints
    /// them.
    private func cards(from printed: String) throws -> [CardAsPrinted] {
        try JSONDecoder().decode([CardAsPrinted].self, from: Data(printed.utf8))
    }

    /// Approves a card with `front` and `tags` into `deck` from a capture of
    /// its own, as a refine session does, and returns it.
    @discardableResult
    private func approveCard(_ front: String, deck: String, tags: [String] = []) throws -> Card {
        guard case .saved(let capture) = try engine.capture(text: front, note: nil, source: nil) else {
            throw EngineError.emptyCapture
        }
        let content = try #require(
            CardContent(type: .word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags, source: nil))
        return try #require(try engine.approve(capture.id, into: [content], deck: deck).first)
    }
}

/// A deck as the CLI prints it, read back by the keys `ficha decks`' help
/// names: one missing, or of another kind, fails the test.
private struct DeckAsPrinted: Decodable, Equatable {
    var name: String
    var cards = 0
    var due = 0
    var setAside = false
    var priority = false
    var color: String?
    var emoji: String?
    var chosenToSync = false
}

/// A card as `ficha cards` prints it, by its deck alone.
private struct CardAsPrinted: Decodable {
    let deck: String
}
