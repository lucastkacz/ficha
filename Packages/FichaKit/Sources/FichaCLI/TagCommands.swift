import ArgumentParser
import FichaCore
import FichaData
import Foundation

// The `ficha` CLI's control of tags (ADR 0022): `ficha tags` lists every tag
// as All Tags does, and each of `ficha tag`'s commands makes one change
// through the engine's actions, as the Cards window does, so it syncs, and
// prints what it changed. None asks first: the refine session asks Lucas. A
// tag only labels its cards (ADR 0024): setting aside and prioritizing are a
// deck's, and `ficha tag convert-to-decks` turns the tags that said where
// Lucas's cards lived before decks into decks, once (`TagsIntoDecks.swift`).

/// `ficha tags`: lists every tag.
struct TagsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List every tag, as All Tags in the Cards window does, with its counts and what it has of its own.",
        discussion: """
            Tags come in the order a tree lists them, each tag inside another right after it. Each says its whole \
            name in "name", with "::" between a tag and a tag inside it, as in "economía::Argentina"; in "cards", \
            how many cards it lists when you choose it, those with a tag inside it too, buried ones left out; in \
            "due", how many of those are due now and in your reviews, which those of a set-aside deck never are; \
            in "pinned" whether it's pinned to the sidebar, and in "pinPlace" its place among the pinned tags, \
            counted from 0, left out while it isn't; and its own "color" and "emoji", left out when it has none. \
            `ficha tag` changes them.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try PrintedTags(of: engine).tags
    }
}

/// `ficha tag`: the commands that change tags.
struct TagCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Change your tags, one change a command, and print what changed.",
        discussion: """
            Name a tag by its whole name, as `ficha tags` prints it, with "::" between a tag and a tag inside it. \
            Each change syncs to your other devices, as the Cards window's does, and none asks first.
            """,
        subcommands: [
            RenameTagCommand.self, DeleteTagsCommand.self, ClearUnusedTagsCommand.self, PinTagsCommand.self,
            UnpinTagCommand.self, MovePinnedTagsCommand.self, TagColorCommand.self, TagEmojiCommand.self,
            ConvertTagsToDecksCommand.self,
        ]
    )
}

/// `ficha tag rename`: renames or moves a tag.
struct RenameTagCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a tag, or move it, with every tag inside it, and print it and the tags inside it.",
        discussion: """
            A new name with "::" moves the tag inside another, and one without moves it to the top. Every card \
            with it, or with a tag inside it, carries the new name, on every device, and the tag keeps its pin, \
            color and emoji. Onto a tag that exists, the two join. For example:

              ficha tag rename economía::Argentina Argentina
            """
    )

    @Argument(help: "The tag's whole name, as `ficha tags` prints it.")
    var tag: String

    @Argument(help: "Its new whole name.")
    var newName: String

    func run(on engine: Engine) throws -> any Encodable {
        let tag = try PrintedTags(of: engine).existing(tag)
        let name = try engine.renameTag(tag, to: newName)
        return try PrintedTags(of: engine).tags.filter { TagPath.isTag($0.name, within: name) }
    }
}

/// `ficha tag delete`: deletes tags.
struct DeleteTagsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete tags, each with every tag inside it, and print what it did.",
        discussion: """
            Every card with them, on every device, loses them, and stays: no card is deleted. Their pins, colors \
            and emoji go too. It prints the tags in "tags", those inside them that went with them in "tagsInside", \
            and how many cards lost them in "cards".
            """
    )

    @Argument(help: "The tags' whole names, as `ficha tags` prints them.")
    var tags: [String]

    func run(on engine: Engine) throws -> any Encodable {
        let listing = try PrintedTags(of: engine)
        return try engine.deleteTags(try tags.map(listing.existing))
    }
}

/// `ficha tag clear-unused`: deletes the tags no card carries.
struct ClearUnusedTagsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear-unused",
        abstract: "Delete the tags no card carries, and print their names.",
        discussion: """
            It deletes each tag that has something of its own, a pin, a color or an emoji, which no card here \
            carries, nor a tag inside it. Your other devices' cards keep their tags: while only the cards in \
            chosen decks sync, one of theirs that doesn't sync may still carry it.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.clearUnusedTags()
    }
}

/// `ficha tag pin`: pins tags to the sidebar.
struct PinTagsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "pin",
        abstract: "Pin tags to the Cards window's sidebar, and print the pinned tags in their order.",
        discussion: """
            They go next to each other, in the order given: after the pinned tags, where those already pinned stay, \
            or with --at, at that place among the other pinned tags, counted from 0, where those already pinned \
            move too.
            """
    )

    @Argument(help: "The tags' whole names, as `ficha tags` prints them.")
    var tags: [String]

    @Option(help: ArgumentHelp("Their place among the other pinned tags, counted from 0.", valueName: "place"))
    var at: Int?

    func validate() throws {
        guard (at ?? 0) >= 0 else {
            throw ValidationError("--at takes a place counted from 0, and got \(at ?? 0).")
        }
    }

    func run(on engine: Engine) throws -> any Encodable {
        let listing = try PrintedTags(of: engine)
        try engine.pin(try tags.map(listing.existing), at: at)
        return try PrintedTags(of: engine).pinned
    }
}

/// `ficha tag unpin`: unpins a tag from the sidebar.
struct UnpinTagCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "unpin",
        abstract: "Unpin a tag from the Cards window's sidebar, and print the pinned tags in their order.",
        discussion: "It stays in All Tags, with its cards."
    )

    @Argument(help: "The tag's whole name, as `ficha tags` prints it.")
    var tag: String

    func run(on engine: Engine) throws -> any Encodable {
        try engine.unpin(try PrintedTags(of: engine).existing(tag))
        return try PrintedTags(of: engine).pinned
    }
}

/// `ficha tag move-pinned`: moves pinned tags among the pinned tags.
struct MovePinnedTagsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "move-pinned",
        abstract: "Move pinned tags to a place among the others, and print the pinned tags in their order.",
        discussion: """
            They go next to each other, in the order given, the first at --to, counted from 0 among the other \
            pinned tags. A tag that isn't pinned is refused, and none moves. For example:

              ficha tag move-pinned historia --to 0
            """
    )

    @Argument(help: "The pinned tags' whole names, as `ficha tags` prints them.")
    var tags: [String]

    @Option(help: ArgumentHelp("Their place among the other pinned tags, counted from 0.", valueName: "place"))
    var to: Int

    func validate() throws {
        guard to >= 0 else {
            throw ValidationError("--to takes a place counted from 0, and got \(to).")
        }
    }

    func run(on engine: Engine) throws -> any Encodable {
        let listing = try PrintedTags(of: engine)
        try engine.movePinnedTags(try tags.map(listing.existing), to: to)
        return try PrintedTags(of: engine).pinned
    }
}

/// `ficha tag color`: gives a tag a color, or takes it away.
struct TagColorCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "color",
        abstract: "Give a tag a color, or take its color away with none, and print the tag.",
        discussion: """
            The colors are Finder's: \(TagColor.allCases.map(\.rawValue).joined(separator: ", ")). A tag inside \
            it with no color of its own shows it.
            """
    )

    @Argument(help: "The tag's whole name, as `ficha tags` prints it.")
    var tag: String

    @Argument(help: ArgumentHelp("One of Finder's colors, or none.", valueName: "color"))
    var color: String

    func validate() throws {
        _ = try chosenColor(color, of: "a tag")
    }

    func run(on engine: Engine) throws -> any Encodable {
        let tag = try PrintedTags(of: engine).existing(tag)
        try engine.setColor(try chosenColor(color, of: "a tag"), of: tag)
        return try PrintedTags(of: engine).tag(tag)
    }
}

/// `ficha tag emoji`: gives a tag an emoji, or takes it away.
struct TagEmojiCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "emoji",
        abstract: "Give a tag an emoji, or take its emoji away with none, and print the tag.",
        discussion: "A tag inside it with no emoji of its own shows it."
    )

    @Argument(help: "The tag's whole name, as `ficha tags` prints it.")
    var tag: String

    @Argument(help: ArgumentHelp("One emoji, or none.", valueName: "emoji"))
    var emoji: String

    func run(on engine: Engine) throws -> any Encodable {
        let tag = try PrintedTags(of: engine).existing(tag)
        try engine.setEmoji(try chosenEmoji(emoji), of: tag)
        return try PrintedTags(of: engine).tag(tag)
    }
}

/// `ficha tag convert-to-decks`: turns tags into decks, once.
struct ConvertTagsToDecksCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert-to-decks",
        abstract: "Turn tags into decks of the same names, moving their cards out of Default, and print what it did.",
        discussion: """
            It's for your tags from before decks, once. For each tag, in the order given: the tag, and each tag \
            inside it, become decks of the same whole names, each with its tag's color, emoji, switch and choice \
            to sync, and the tags go, their pins with them; every card still in Default that carries one of them \
            moves to the deck of the deepest one it carries, and loses that tag and those it sits inside. A card \
            an earlier tag moved out of Default stays there, and keeps this tag as a tag. It prints the decks it \
            makes in "decks", each with how many cards move to it in "cards", and in "cardsWithTwoTags" the cards \
            that carry two tags of the list, neither inside the other, each with its "id", its "front", those \
            "tags", and the "deck" it goes to. With --preview it prints the same, and changes nothing. For \
            example:

              ficha tag convert-to-decks Idiomas historia --preview
            """
    )

    @Argument(help: "The tags' whole names, as `ficha tags` prints them, in the order they turn into decks.")
    var tags: [String]

    @ArgumentParser.Flag(help: "Print what it would do instead, changing nothing.")
    var preview = false

    func run(on engine: Engine) throws -> any Encodable {
        let listing = try PrintedTags(of: engine)
        let tags = try tags.map(listing.existing)
        return preview ? try engine.conversion(ofTags: tags) : try engine.convertTagsToDecks(tags)
    }
}

/// A tag as `ficha tags` prints it.
struct PrintedTag: Encodable, Equatable {
    let name: String
    let cards: Int
    let due: Int
    let pinned: Bool
    let pinPlace: Int?
    let color: String?
    let emoji: String?
}

extension PrintedTag {
    /// The tag `name` with nothing of its own and no card, as a change can
    /// leave it, which `ficha tags` no longer lists.
    init(withNothingNamed name: String) {
        self.init(name: name, cards: 0, due: 0, pinned: false, pinPlace: nil, color: nil, emoji: nil)
    }
}

/// Every tag as `ficha tags` prints it, read from the engine at once.
struct PrintedTags {
    /// Every tag, in the order a tree lists them.
    let tags: [PrintedTag]
    /// The pinned tags, in their order.
    let pinned: [PrintedTag]

    /// The tags `engine` holds now, each with its counts on the engine's
    /// ladder, read together.
    init(of engine: Engine) throws {
        let counted = try engine.countedTags(on: engine.progressSettings().ladder)
        let pinnedNames = counted.map(\.tag).pinnedInOrder.map(\.name)
        let tags = counted.map { counted in
            let (tag, count) = (counted.tag, counted.counts)
            return PrintedTag(
                name: tag.name, cards: count.cards, due: count.due, pinned: tag.isPinned,
                pinPlace: pinnedNames.firstIndex(of: tag.name), color: tag.color?.rawValue, emoji: tag.emoji)
        }
        self.tags = tags
        pinned = pinnedNames.compactMap { name in tags.first { $0.name == name } }
    }

    /// The tag `name` names, its levels cleaned up as a card's are, or an
    /// error when it's blank or no tag has it.
    func existing(_ name: String) throws -> String {
        guard let normalized = TagPath.normalized(name) else {
            throw EngineError.blankTagName
        }
        guard tags.contains(where: { $0.name == normalized }) else {
            throw UnknownTagError(tag: name)
        }
        return normalized
    }

    /// The tag named `name` as it stands now: as `ficha tags` lists it, or
    /// with nothing of its own and no card, when a change left it so.
    func tag(_ name: String) -> PrintedTag {
        tags.first { $0.name == name } ?? PrintedTag(withNothingNamed: name)
    }
}

/// The color `text` gives, by its name, or nil for none, written "none"; or
/// an error naming the colors `what`, a tag or a deck, can have.
func chosenColor(_ text: String, of what: String) throws -> TagColor? {
    if text == "none" {
        return nil
    }
    guard let chosen = TagColor(rawValue: text) else {
        throw ValidationError(
            """
            “\(text)” isn't a color \(what) can have. Pick one of \
            \(TagColor.allCases.map(\.rawValue).joined(separator: ", ")), or none.
            """)
    }
    return chosen
}

/// The emoji `text` gives, or nil for none, written "none" or left empty; or
/// an error when it isn't one emoji.
func chosenEmoji(_ text: String) throws -> Emoji? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text == "none" || text.isEmpty ? nil : try Emoji(text)
}

/// A tag a `ficha tag` command names that no card carries, nor has anything
/// of its own. Its message says where the tags are.
struct UnknownTagError: LocalizedError {
    /// The name, as it was given.
    let tag: String

    var errorDescription: String? {
        """
        You have no tag named “\(tag)”, so nothing changed. `ficha tags` lists yours, each by its whole name, with \
        “::” between a tag and a tag inside it.
        """
    }
}
