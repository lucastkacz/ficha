import ArgumentParser
import FichaCore
import FichaData
import Foundation
import Testing

// For the commands, which the CLI parses from its arguments and runs on the
// engine, and the JSON it prints their results as.
@testable import FichaCLI

/// Tests on the `ficha` CLI's control of tags and card types (ADR 0022): each
/// command parsed from its arguments, as a refine session types them, run on
/// an engine in memory, and the JSON it prints.
struct TagAndTypeCommandsTests {
    let engine: Engine

    init() throws {
        engine = try Engine(location: .inMemory, time: ManualTimeSource(now: Date(timeIntervalSince1970: 0)))
    }

    // historia is pinned first and green; literatura is pinned second and
    // has an emoji; música has a color and no card. A tag has no switch nor
    // choice to sync to print: decks have them (ADR 0024).
    @Test(
        "`ficha tags` prints every tag in tree order, with its counts, its pin and its place, and what it has of its own"
    )
    func tagsPrintsEveryTag() async throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía", "historia"])
        try approveCard("Facundo", tags: ["historia"])
        try engine.pin(["historia", "literatura"])
        try engine.setColor(.green, of: "historia")
        try engine.setEmoji(Emoji("📚"), of: "literatura")
        try engine.setColor(.blue, of: "música")

        let printed = try await ficha("tags")

        #expect(
            printed == """
                [
                  {
                    "cards" : 2,
                    "color" : "green",
                    "due" : 0,
                    "name" : "historia",
                    "pinPlace" : 0,
                    "pinned" : true
                  },
                  {
                    "cards" : 1,
                    "due" : 0,
                    "emoji" : "📚",
                    "name" : "literatura",
                    "pinPlace" : 1,
                    "pinned" : true
                  },
                  {
                    "cards" : 1,
                    "due" : 0,
                    "name" : "literatura::poesía",
                    "pinned" : false
                  },
                  {
                    "cards" : 0,
                    "color" : "blue",
                    "due" : 0,
                    "name" : "música",
                    "pinned" : false
                  }
                ]
                """)
    }

    @Test("`ficha tag rename` moves a tag with the tags inside it, and prints them under their new names")
    func renamingATag() async throws {
        try approveCard("cepo", tags: ["economía::Argentina"])
        try engine.setColor(.green, of: "economía")

        let printed = try await tags(from: ficha("tag", "rename", "economía", "historia :: economía"))

        #expect(printed.map(\.name) == ["historia::economía", "historia::economía::Argentina"])
        #expect(printed.map(\.color) == ["green", nil])
        #expect(try engine.cards().map(\.tags) == [["historia::economía::Argentina"]])
    }

    // Only the cards in a chosen deck sync, and none is chosen: what syncs
    // is the decks' to decide, so the command says nothing of it.
    @Test(
        "`ficha tag delete` deletes several tags, each with the tags inside it, and prints what it did, under selective sync too"
    )
    func deletingTags() async throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía", "historia", "argentina"])
        try approveCard("Facundo", tags: ["historia"])
        try engine.syncOnlyChosenDecks(true)

        let printed = try await ficha("tag", "delete", "literatura", "historia")

        #expect(
            printed == """
                {
                  "cards" : 2,
                  "tags" : [
                    "literatura",
                    "historia"
                  ],
                  "tagsInside" : [
                    "literatura::poesía"
                  ]
                }
                """)
        #expect(try engine.cards().map(\.tags) == [["argentina"], []])
    }

    @Test("`ficha tag clear-unused` deletes the tags no card carries, and prints their names")
    func clearingUnusedTags() async throws {
        try approveCard("Martín Fierro", tags: ["literatura"])
        try engine.setColor(.blue, of: "música")
        try engine.setColor(.green, of: "literatura")

        let printed = try await ficha("tag", "clear-unused")

        #expect(
            printed == """
                [
                  "música"
                ]
                """)
        #expect(try engine.allTags().map(\.name) == ["literatura"])
    }

    @Test("`ficha tag pin`, `unpin` and `move-pinned` change the pinned tags, and print them in their order")
    func pinningTags() async throws {
        try approveCard("Martín Fierro", tags: ["literatura", "historia", "argentina"])

        let pinnedLast = try await tags(from: ficha("tag", "pin", "literatura", "historia"))
        let pinnedFirst = try await tags(from: ficha("tag", "pin", "argentina", "--at", "0"))
        let moved = try await tags(from: ficha("tag", "move-pinned", "historia", "--to", "0"))
        let unpinned = try await tags(from: ficha("tag", "unpin", "argentina"))

        #expect(pinnedLast.map(\.name) == ["literatura", "historia"])
        #expect(pinnedFirst.map(\.name) == ["argentina", "literatura", "historia"])
        #expect(pinnedFirst.map(\.pinPlace) == [0, 1, 2])
        #expect(moved.map(\.name) == ["historia", "argentina", "literatura"])
        #expect(unpinned.map(\.name) == ["historia", "literatura"])
    }

    @Test("`ficha tag move-pinned` refuses a tag that isn't pinned, as the app does")
    func movingATagThatIsntPinned() async throws {
        try approveCard("Martín Fierro", tags: ["literatura", "historia"])
        try engine.pin("literatura")

        await #expect(throws: EngineError.tagNotPinned("historia")) {
            try await ficha("tag", "move-pinned", "historia", "--to", "0")
        }
    }

    @Test("`ficha tag` no longer sets a tag aside, prioritizes it or chooses it to sync: decks do (ADR 0024)")
    func aTagHasNoSwitch() throws {
        #expect(throws: (any Error).self) { try FichaCommand.parseAsRoot(["tag", "set-aside", "literatura"]) }
        #expect(throws: (any Error).self) { try FichaCommand.parseAsRoot(["tag", "prioritize", "literatura"]) }
        #expect(throws: (any Error).self) { try FichaCommand.parseAsRoot(["tag", "choose-to-sync", "literatura"]) }
    }

    @Test("`ficha tag color` and `emoji` set a tag's own, take it away with none, and print it")
    func settingWhatATagHasOfItsOwn() async throws {
        try approveCard("Martín Fierro", tags: ["literatura"])

        let colored = try await tag(from: ficha("tag", "color", "literatura", "purple"))
        let withEmoji = try await tag(from: ficha("tag", "emoji", "literatura", "📚"))
        let uncolored = try await tag(from: ficha("tag", "color", "literatura", "none"))
        let withoutEmoji = try await tag(from: ficha("tag", "emoji", "literatura", "none"))

        #expect(colored.color == "purple")
        #expect(withEmoji.emoji == "📚")
        #expect(uncolored.color == nil)
        #expect(withoutEmoji.emoji == nil)
    }

    // Each tag has no card and one thing of its own, which the command takes
    // away, and with it the tag's row.
    @Test("a tag command that leaves a tag with nothing of its own and no card prints it with everything off")
    func takingAwayATagsLastOwnThing() async throws {
        try engine.setColor(.blue, of: "música")
        try engine.setEmoji(Emoji("🎬"), of: "cine")

        let printed = [
            try await tag(from: ficha("tag", "color", "música", "none")),
            try await tag(from: ficha("tag", "emoji", "cine", "none")),
        ]

        #expect(
            printed
                == ["música", "cine"].map { name in
                    TagAsPrinted(name: name, cards: 0, due: 0, pinned: false, pinPlace: nil, color: nil, emoji: nil)
                })
        #expect(try engine.allTags().isEmpty)
    }

    @Test("a color a tag can't have, or text that isn't one emoji, is refused, and nothing changes")
    func aWrongColorOrEmojiIsRefused() async throws {
        try approveCard("Martín Fierro", tags: ["literatura"])

        #expect(throws: (any Error).self) { try FichaCommand.parseAsRoot(["tag", "color", "literatura", "pink"]) }
        await #expect(throws: EngineError.notOneEmoji) { try await ficha("tag", "emoji", "literatura", "libro") }
        #expect(try engine.allTags() == [CardTag(name: "literatura")])
    }

    @Test("a tag command refuses a tag no card carries nor has anything of its own, and changes nothing")
    func anUnknownTagIsRefused() async throws {
        try approveCard("Martín Fierro", tags: ["literatura"])

        await #expect(throws: UnknownTagError.self) { try await ficha("tag", "pin", "literatur") }
        await #expect(throws: UnknownTagError.self) { try await ficha("tag", "delete", "literatura", "historia") }
        #expect(try engine.allTags() == [CardTag(name: "literatura")])
        #expect(try engine.cards().map(\.tags) == [["literatura"]])
    }

    @Test("`ficha types` prints the four types Ficha comes with, then the user's own, with how many cards each has")
    func typesPrintsEveryType() async throws {
        let drug = try engine.makeUserType(named: "Fármaco", emoji: Emoji("💊"))
        try approveCard("ibuprofeno", tags: [], type: .user(drug))
        try approveCard("serendipia", tags: [], type: .word)

        let printed = try await ficha("types")

        #expect(
            printed == """
                [
                  {
                    "builtIn" : true,
                    "cards" : 1,
                    "name" : "word"
                  },
                  {
                    "builtIn" : true,
                    "cards" : 0,
                    "name" : "concept"
                  },
                  {
                    "builtIn" : true,
                    "cards" : 0,
                    "name" : "quote"
                  },
                  {
                    "builtIn" : true,
                    "cards" : 0,
                    "name" : "question"
                  },
                  {
                    "builtIn" : false,
                    "cards" : 1,
                    "emoji" : "💊",
                    "name" : "Fármaco"
                  }
                ]
                """)
    }

    @Test(
        "`ficha type make`, `rename`, `emoji` and `delete` change a type of the user's own by its name, and print it; its cards then have none"
    )
    func changingAUserType() async throws {
        let made = try await type(from: ficha("type", "make", "Fármaco", "--emoji", "💊"))
        try approveCard("ibuprofeno", tags: [], type: .user(try #require(try engine.userTypes().first)))
        let renamed = try await type(from: ficha("type", "rename", "farmaco", "Droga"))
        let withoutEmoji = try await type(from: ficha("type", "emoji", "droga", "none"))
        let deleted = try await type(from: ficha("type", "delete", "Droga"))

        #expect(made == TypeAsPrinted(name: "Fármaco", builtIn: false, emoji: "💊", cards: 0))
        #expect(renamed == TypeAsPrinted(name: "Droga", builtIn: false, emoji: "💊", cards: 1))
        #expect(withoutEmoji == TypeAsPrinted(name: "Droga", builtIn: false, emoji: nil, cards: 1))
        #expect(deleted == withoutEmoji)
        #expect(try engine.userTypes().isEmpty)
        #expect(try engine.cards().map(\.type) == [nil])
    }

    @Test("a type command refuses one of the four Ficha comes with, a type the user doesn't have, and a taken name")
    func aTypeCommandRefuses() async throws {
        try engine.makeUserType(named: "Fármaco")
        try engine.makeUserType(named: "Droga")

        await #expect(throws: BuiltInTypeError.self) { try await ficha("type", "delete", "word") }
        await #expect(throws: UnknownTypeError.self) { try await ficha("type", "rename", "Remedio", "Medicamento") }
        await #expect(throws: EngineError.typeNameTaken("Droga")) {
            try await ficha("type", "rename", "Fármaco", "droga")
        }
        await #expect(throws: EngineError.builtInTypeName("quote")) { try await ficha("type", "make", "quote") }
        #expect(try engine.userTypes().map(\.name) == ["Droga", "Fármaco"])
    }

    /// Runs `ficha` with `arguments` on the engine, as the CLI parses and
    /// runs them, and returns the JSON it prints.
    @discardableResult
    private func ficha(_ arguments: String...) async throws -> String {
        let command = try FichaCommand.parseAsRoot(arguments)
        let engineCommand = try #require(command as? any EngineCommand)
        return try json(await engineCommand.run(on: engine))
    }

    /// The tags `printed` lists, as a command prints them.
    private func tags(from printed: String) throws -> [TagAsPrinted] {
        try JSONDecoder().decode([TagAsPrinted].self, from: Data(printed.utf8))
    }

    /// The tag `printed` holds, as a command prints it.
    private func tag(from printed: String) throws -> TagAsPrinted {
        try JSONDecoder().decode(TagAsPrinted.self, from: Data(printed.utf8))
    }

    /// The type `printed` holds, as a command prints it.
    private func type(from printed: String) throws -> TypeAsPrinted {
        try JSONDecoder().decode(TypeAsPrinted.self, from: Data(printed.utf8))
    }

    /// Approves a card with `front`, `tags` and `type` from a capture of its
    /// own, as a refine session does, and returns it.
    @discardableResult
    private func approveCard(_ front: String, tags: [String], type: CardType? = nil) throws -> Card {
        guard case .saved(let capture) = try engine.capture(text: front, note: nil, source: nil) else {
            throw EngineError.emptyCapture
        }
        let content = try #require(
            CardContent(type: type, front: front, back: "Lo que quiere decir «\(front)».", tags: tags, source: nil))
        return try #require(try engine.approve(capture.id, into: [content]).first)
    }
}

/// A tag as the CLI prints it, read back by the keys `ficha tags`' help
/// names: one missing, or of another kind, fails the test.
private struct TagAsPrinted: Decodable, Equatable {
    let name: String
    let cards: Int
    let due: Int
    let pinned: Bool
    let pinPlace: Int?
    let color: String?
    let emoji: String?
}

/// A card type as the CLI prints it, read back by the keys `ficha types`'
/// help names.
private struct TypeAsPrinted: Decodable, Equatable {
    let name: String
    let builtIn: Bool
    let emoji: String?
    let cards: Int
}
