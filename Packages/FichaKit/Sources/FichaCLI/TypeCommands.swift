import ArgumentParser
import FichaCore
import FichaData
import Foundation

// The `ficha` CLI's control of card types (`GLOSSARY.md`'s Card type):
// `ficha types` lists the four Ficha comes with and the user's own, and each
// of `ficha type`'s commands makes, renames, gives an emoji to or deletes a
// type of the user's own through the engine's actions, as the Cards window
// does, so it syncs, and prints what it changed. The four are fixed.

/// `ficha types`: lists the card types.
struct TypesCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "types",
        abstract: "List the card types: the four Ficha comes with, then your own, and how many cards each has.",
        discussion: """
            Each type says its name in "name", as `ficha cards` writes a card's type: word, concept, quote and \
            question for the four Ficha comes with, which say so in "builtIn", and your own types by their names, \
            in alphabetical order. A type of your own has its emoji in "emoji", left out when it has none. "cards" \
            counts its cards, buried ones too. `ficha type` changes your own.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try (CardType.builtIn + engine.userTypes().map(CardType.user)).map { type in
            try PrintedType(type, in: engine)
        }
    }
}

/// `ficha type`: the commands that change the user's own card types.
struct TypeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Make, rename, give an emoji to or delete a card type of your own, and print what changed.",
        discussion: """
            Name a type of your own by its name, as `ficha types` prints it, ignoring case and accents. The four \
            Ficha comes with are fixed. Each change syncs to your other devices, as the Cards window's does, and \
            none asks first.
            """,
        subcommands: [MakeTypeCommand.self, RenameTypeCommand.self, TypeEmojiCommand.self, DeleteTypeCommand.self]
    )
}

/// `ficha type make`: makes a card type of the user's own.
struct MakeTypeCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "make",
        abstract: "Make a card type of your own, and print it.",
        discussion: """
            Its name can't be one of the four Ficha comes with, nor one of yours, ignoring case and accents. For \
            example:

              ficha type make Fármaco --emoji 💊
            """
    )

    @Argument(help: "Its name.")
    var name: String

    @Option(help: ArgumentHelp("Its emoji: one emoji.", valueName: "emoji"))
    var emoji: String?

    func run(on engine: Engine) throws -> any Encodable {
        let type = try engine.makeUserType(named: name, emoji: try emoji.flatMap(chosenEmoji))
        return try PrintedType(.user(type), in: engine)
    }
}

/// `ficha type rename`: renames a card type of the user's own.
struct RenameTypeCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a card type of your own, and print it: its cards keep it.",
        discussion: "Its new name can't be one of the four Ficha comes with, nor another of yours."
    )

    @Argument(help: "Its name, as `ficha types` prints it.")
    var name: String

    @Argument(help: "Its new name.")
    var newName: String

    func run(on engine: Engine) throws -> any Encodable {
        let type = try engine.renameUserType(try userType(named: name, in: engine).id, to: newName)
        return try PrintedType(.user(type), in: engine)
    }
}

/// `ficha type emoji`: gives a card type of the user's own an emoji, or takes
/// it away.
struct TypeEmojiCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "emoji",
        abstract: "Give a card type of your own an emoji, or take its emoji away with none, and print it."
    )

    @Argument(help: "Its name, as `ficha types` prints it.")
    var name: String

    @Argument(help: ArgumentHelp("One emoji, or none.", valueName: "emoji"))
    var emoji: String

    func run(on engine: Engine) throws -> any Encodable {
        let type = try engine.setEmoji(try chosenEmoji(emoji), ofUserType: try userType(named: name, in: engine).id)
        return try PrintedType(.user(type), in: engine)
    }
}

/// `ficha type delete`: deletes a card type of the user's own.
struct DeleteTypeCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a card type of your own, and print it, with how many cards it had.",
        discussion: "Its cards stay, with no type, as the Cards window leaves them, on every device."
    )

    @Argument(help: "Its name, as `ficha types` prints it.")
    var name: String

    func run(on engine: Engine) throws -> any Encodable {
        let type = try userType(named: name, in: engine)
        let printed = try PrintedType(.user(type), in: engine)
        try engine.deleteUserType(type.id)
        return printed
    }
}

/// A card type as `ficha types` prints it.
struct PrintedType: Encodable, Equatable {
    let name: String
    let builtIn: Bool
    let emoji: String?
    let cards: Int

    /// `type`, with as many cards as `engine` counts it has now.
    init(_ type: CardType, in engine: Engine) throws {
        name = type.writtenName
        builtIn = type.userType == nil
        emoji = type.userType?.emoji
        cards = try engine.cardCount(of: type)
    }
}

/// The user's type that `name` names, ignoring case and accents, or an error
/// when it names one of the four Ficha comes with, or none.
private func userType(named name: String, in engine: Engine) throws -> UserType {
    if let builtIn = CardType(builtInNamed: name) {
        throw BuiltInTypeError(type: builtIn.writtenName)
    }
    guard let type = try engine.userTypes().first(where: { UserType.isSameName(name, as: $0.name) }) else {
        throw UnknownTypeError(type: name)
    }
    return type
}

/// A type a `ficha type` command names that the user doesn't have. Its message
/// says where the types are.
struct UnknownTypeError: LocalizedError {
    /// The name, as it was given.
    let type: String

    var errorDescription: String? {
        "You have no type named “\(type)”, so nothing changed. `ficha types` lists yours."
    }
}

/// One of the four types Ficha comes with, which a `ficha type` command was
/// asked to change: they're fixed.
struct BuiltInTypeError: LocalizedError {
    /// The type's name, as `ficha types` prints it.
    let type: String

    var errorDescription: String? {
        """
        “\(type)” is one of the four types Ficha comes with, which can't be renamed, given an emoji or deleted, so \
        nothing changed. To change a type, make one of your own with `ficha type make`, or pick one `ficha types` \
        lists as yours.
        """
    }
}
