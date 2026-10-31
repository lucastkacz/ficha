import ArgumentParser
import FichaCore
import FichaData
import Foundation

// The `ficha` CLI's control of decks (ADR 0024): `ficha decks` lists every
// deck, as the Sync tab lists them to choose from, Default included, and
// each of `ficha deck`'s commands, and `ficha change-deck`, makes one change
// through the engine's actions, as the Cards window does, so it syncs, and
// prints what it changed. None asks first: the refine session asks Lucas.

/// `ficha decks`: lists every deck.
struct DecksCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "decks",
        abstract: "List every deck, Default included, with its counts and what it has of its own.",
        discussion: """
            Decks come in the order a tree lists them, Default first, each deck inside another right after it. \
            Each says its whole name in "name", with "::" between a deck and a deck inside it, as in \
            "Idiomas::Inglés", or "" for Default, where a card lives when it has no other deck; in "cards", how \
            many cards live in it or in a deck inside it, buried ones left out; in "due", how many of those are \
            due now and in your reviews, which those of a set-aside deck never are; in "setAside" and "priority" \
            its own switch, which a deck inside it doesn't show; its own "color" and "emoji", left out when it \
            has none; and in "chosenToSync" whether you chose it to sync. While only the cards in chosen decks \
            sync, it lists your other devices' decks too, as Settings' Sync tab does. `ficha deck` changes them, \
            and `ficha change-deck` moves cards between them.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try PrintedDecks(of: engine).decks
    }
}

/// `ficha deck`: the commands that change decks.
struct DeckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deck",
        abstract: "Change your decks, one change a command, and print what changed.",
        discussion: """
            Name a deck by its whole name, as `ficha decks` prints it, with "::" between a deck and a deck inside \
            it, or "" for Default. Each change syncs to your other devices, as the Cards window's does, and none \
            asks first.
            """,
        subcommands: [
            MakeDeckCommand.self, RenameDeckCommand.self, DeleteDeckCommand.self, SetDeckAsideCommand.self,
            PrioritizeDeckCommand.self, DeckColorCommand.self, DeckEmojiCommand.self, ChooseDeckToSyncCommand.self,
        ]
    )
}

/// `ficha deck make`: makes a deck.
struct MakeDeckCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "make",
        abstract: "Make a deck, which stays while it holds no card, and print it.",
        discussion: """
            A name with "::" makes it inside another deck, which it makes too when you have none by that name. A \
            deck that's there already stays as it is. A deck at the top can't take Default's name. For example:

              ficha deck make Idiomas::Inglés
            """
    )

    @Argument(help: "The deck's whole name.")
    var name: String

    func run(on engine: Engine) throws -> any Encodable {
        let name = try engine.makeDeck(named: name)
        return try PrintedDecks(of: engine).deck(name)
    }
}

/// `ficha deck rename`: renames or moves a deck.
struct RenameDeckCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a deck, or move it, with every deck inside it, and print it and the decks inside it.",
        discussion: """
            A new name with "::" moves the deck inside another, and one without moves it to the top. Every card \
            in it, or in a deck inside it, moves along, on every device, keeping its step, its review log and its \
            tags, and the deck keeps its switch, color, emoji and choice to sync. Onto a deck that exists, the two \
            join, and the deck there keeps what it had of its own. Default is never renamed, and no deck moves \
            inside itself. For example:

              ficha deck rename Idiomas::Inglés Inglés
            """
    )

    @Argument(help: "The deck's whole name, as `ficha decks` prints it.")
    var deck: String

    @Argument(help: "Its new whole name.")
    var newName: String

    func run(on engine: Engine) throws -> any Encodable {
        let deck = try PrintedDecks(of: engine).existing(deck)
        let name = try engine.renameDeck(deck, to: newName)
        return try PrintedDecks(of: engine).decks.filter { TagPath.isTag($0.name, within: name) }
    }
}

/// `ficha deck delete`: deletes a deck with its cards.
struct DeleteDeckCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a deck, with every deck inside it and every card in them, and print what it did.",
        discussion: """
            Every card in it, or in a deck inside it, buried ones too, is deleted with its review log, on every \
            device, whether or not it syncs, as in Anki; its expansions and follow-ups stay in the inbox. A card \
            another device holds in it that wasn't in it here, and that doesn't sync, moves to Default there. The \
            decks' switches, colors, emoji and choices to sync go too. Nothing undoes it, but the daily backups \
            keep what it deleted, and `ficha restore` brings one back. Default is never deleted: to keep a deck's \
            cards, move them first with `ficha change-deck`. It prints the deck in "deck", the decks inside it \
            that went with it in "decksInside", and how many cards it deleted in "cards".
            """
    )

    @Argument(help: "The deck's whole name, as `ficha decks` prints it.")
    var deck: String

    func run(on engine: Engine) throws -> any Encodable {
        try engine.deleteDeck(try PrintedDecks(of: engine).existing(deck))
    }
}

/// `ficha deck set-aside`: sets a deck aside, or stops.
struct SetDeckAsideCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-aside",
        abstract: "Set a deck aside, or with --off stop setting it aside, and print the deck.",
        discussion: """
            A set-aside deck's cards, and those of the decks inside it, are out of your reviews for now; they keep \
            their steps. A priority deck set aside is no longer one.
            """
    )

    @Argument(help: "The deck's whole name, as `ficha decks` prints it, or \"\" for Default.")
    var deck: String

    @ArgumentParser.Flag(help: "Stop setting it aside instead.")
    var off = false

    func run(on engine: Engine) throws -> any Encodable {
        try PrintedDecks.changing(deck, on: engine) { deck in
            if off {
                try engine.stopSettingAside(deck: deck)
            } else {
                try engine.setAside(deck: deck)
            }
        }
    }
}

/// `ficha deck prioritize`: makes a deck a priority deck, or not.
struct PrioritizeDeckCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "prioritize",
        abstract: "Make a deck a priority deck, or with --off no longer one, and print the deck.",
        discussion: """
            A priority deck's cards, and those of the decks inside it, come first when cards show up. A set-aside \
            deck, or a deck inside one, can't be one: stop setting it aside first.
            """
    )

    @Argument(help: "The deck's whole name, as `ficha decks` prints it, or \"\" for Default.")
    var deck: String

    @ArgumentParser.Flag(help: "Make it no longer a priority deck instead.")
    var off = false

    func run(on engine: Engine) throws -> any Encodable {
        try PrintedDecks.changing(deck, on: engine) { try engine.setPriority(!off, ofDeck: $0) }
    }
}

/// `ficha deck color`: gives a deck a color, or takes it away.
struct DeckColorCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "color",
        abstract: "Give a deck a color, or take its color away with none, and print the deck.",
        discussion: """
            The colors are Finder's: \(TagColor.allCases.map(\.rawValue).joined(separator: ", ")). A deck inside \
            it with no color of its own shows it.
            """
    )

    @Argument(help: "The deck's whole name, as `ficha decks` prints it, or \"\" for Default.")
    var deck: String

    @Argument(help: ArgumentHelp("One of Finder's colors, or none.", valueName: "color"))
    var color: String

    func validate() throws {
        _ = try chosenColor(color, for: .deck)
    }

    func run(on engine: Engine) throws -> any Encodable {
        try PrintedDecks.changing(deck, on: engine) { try engine.setColor(chosenColor(color, for: .deck), ofDeck: $0) }
    }
}

/// `ficha deck emoji`: gives a deck an emoji, or takes it away.
struct DeckEmojiCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "emoji",
        abstract: "Give a deck an emoji, or take its emoji away with none, and print the deck.",
        discussion: "A deck inside it with no emoji of its own shows it."
    )

    @Argument(help: "The deck's whole name, as `ficha decks` prints it, or \"\" for Default.")
    var deck: String

    @Argument(help: ArgumentHelp("One emoji, or none.", valueName: "emoji"))
    var emoji: String

    func run(on engine: Engine) throws -> any Encodable {
        try PrintedDecks.changing(deck, on: engine) { try engine.setEmoji(chosenEmoji(emoji), ofDeck: $0) }
    }
}

/// `ficha deck choose-to-sync`: chooses a deck to sync, or not.
struct ChooseDeckToSyncCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "choose-to-sync",
        abstract: "Choose a deck to sync, or with --off untick it, and print the deck.",
        discussion: """
            While only the cards in chosen decks sync, as Settings' Sync tab chooses, a card syncs when its deck, \
            or a deck its deck sits inside, is chosen; Default can be chosen too. A card that stops syncing leaves \
            iCloud and stays on every device. Choosing between every card and chosen decks stays in Settings.
            """
    )

    @Argument(help: "The deck's whole name, as `ficha decks` prints it, or \"\" for Default.")
    var deck: String

    @ArgumentParser.Flag(help: "Untick it instead.")
    var off = false

    func run(on engine: Engine) throws -> any Encodable {
        try PrintedDecks.changing(deck, on: engine) { try engine.setChosenToSync(!off, ofDeck: $0) }
    }
}

/// `ficha change-deck`: moves cards to a deck.
struct ChangeDeckCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "change-deck",
        abstract: "Move cards to a deck, as Change Deck… in the Cards window does, and print them.",
        discussion: """
            Name the deck by its whole name, as `ficha decks` prints it, with "::" between a deck and a deck \
            inside it, or "" for Default; one you have none by that name is made. Each card keeps its step, its \
            review log and its tags. For example:

              ficha change-deck 12 15 --to Idiomas::Inglés
            """
    )

    @Argument(help: "The cards' ids, as `ficha cards` shows them.")
    var cardIDs: [Int64]

    @Option(help: ArgumentHelp("The deck's whole name, or \"\" for Default.", valueName: "deck"))
    var to: String

    func run(on engine: Engine) throws -> any Encodable {
        let cardIDs = Set(cardIDs)
        try engine.changeDeck(of: cardIDs, to: to)
        return try engine.cards().filter { cardIDs.contains($0.id) }
    }
}

/// A deck as `ficha decks` prints it.
struct PrintedDeck: Encodable, Equatable {
    let name: String
    let cards: Int
    let due: Int
    let setAside: Bool
    let priority: Bool
    let color: String?
    let emoji: String?
    let chosenToSync: Bool
}

extension PrintedDeck {
    /// The deck `name` with nothing of its own and no card, as a command
    /// would print a deck `ficha decks` doesn't list, which no command leaves
    /// a deck it changed, since each keeps its row, or Default, always listed.
    init(withNothingNamed name: String) {
        self.init(
            name: name, cards: 0, due: 0, setAside: false, priority: false, color: nil, emoji: nil,
            chosenToSync: false)
    }
}

/// Every deck as `ficha decks` prints it, read from the engine at once.
struct PrintedDecks {
    /// Every deck, in the order a tree lists them, Default first.
    let decks: [PrintedDeck]

    /// The decks `engine` holds now, every one, as the Sync tab lists them,
    /// each with its counts on the engine's ladder, read together.
    init(of engine: Engine) throws {
        let ladder = try engine.progressSettings().ladder
        decks = try engine.countedDecks(on: ladder, asTheSyncTabLists: true).map { counted in
            let (deck, count) = (counted.deck, counted.counts)
            return PrintedDeck(
                name: deck.name, cards: count.cards, due: count.due, setAside: deck.switchedOn == .setAside,
                priority: deck.switchedOn == .priority, color: deck.color?.rawValue, emoji: deck.emoji,
                chosenToSync: deck.chosenToSync)
        }
    }

    /// The deck `name` names: Default for `Deck.defaultName`, which is
    /// always there, or a deck's whole name, its levels cleaned up as a
    /// card's deck's are; or an error when it's blank or no deck has it.
    func existing(_ name: String) throws -> String {
        guard name != Deck.defaultName else {
            return name
        }
        guard let normalized = TagPath.normalized(name) else {
            throw EngineError.blankDeckName
        }
        guard decks.contains(where: { $0.name == normalized }) else {
            throw UnknownDeckError(deck: name)
        }
        return normalized
    }

    /// The deck named `name` as it stands now: as `ficha decks` lists it, or
    /// with nothing of its own and no card when it doesn't.
    func deck(_ name: String) -> PrintedDeck {
        decks.first { $0.name == name } ?? PrintedDeck(withNothingNamed: name)
    }

    /// Makes `change` to the deck `name` names, checked as `existing(_:)`
    /// checks it, on `engine`, and returns the deck as it stands then: what
    /// each `ficha deck` command that changes a deck's own does.
    static func changing(_ name: String, on engine: Engine, _ change: (String) throws -> Void) throws -> PrintedDeck {
        let deck = try PrintedDecks(of: engine).existing(name)
        try change(deck)
        return try PrintedDecks(of: engine).deck(deck)
    }
}

/// A deck a `ficha deck` command names that no device has. Its message says
/// where the decks are.
struct UnknownDeckError: LocalizedError {
    /// The name, as it was given.
    let deck: String

    var errorDescription: String? {
        """
        You have no deck named “\(deck)”, so nothing changed. `ficha decks` lists yours, each by its whole name, \
        with “::” between a deck and a deck inside it, and Default as "". `ficha deck make` makes one.
        """
    }
}
