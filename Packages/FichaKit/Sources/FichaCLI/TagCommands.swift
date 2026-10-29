import ArgumentParser
import FichaCore
import FichaData
import Foundation

// The `ficha` CLI's control of tags (ADR 0022): `ficha tags` lists every tag
// as All Tags does, and each of `ficha tag`'s commands makes one change
// through the engine's actions, as the Cards window does, so it syncs, and
// prints what it changed. None asks first: the refine session asks Lucas.

/// `ficha tags`: lists every tag.
struct TagsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List every tag, as All Tags in the Cards window does, with its counts and what it has of its own.",
        discussion: """
            Tags come in the order a tree lists them, each tag inside another right after it. Each says its whole \
            name in "name", with "::" between a tag and a tag inside it, as in "economía::Argentina"; in "cards", \
            how many cards it lists when you choose it, those with a tag inside it too, buried ones left out; in \
            "due", how many of those are due now and in your reviews, none while it's set aside; in "pinned" \
            whether it's pinned to the sidebar, and in "pinPlace" its place among the pinned tags, counted from 0, \
            left out while it isn't; in "setAside" and "priority" its own switch, which a tag inside it doesn't \
            show; its own "color" and "emoji", left out when it has none; and in "chosenToSync" whether you chose \
            it to sync. `ficha tag` changes them.
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
            UnpinTagCommand.self, MovePinnedTagsCommand.self, SetTagAsideCommand.self, PrioritizeTagCommand.self,
            TagColorCommand.self, TagEmojiCommand.self, ChooseTagToSyncCommand.self,
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
            switch, color, emoji and choice to sync. Onto a tag that exists, the two join. For example:

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
            Every card with them, on every device, loses them, and stays: no card is deleted. Their pins, \
            switches, colors, emoji and choices to sync go too. It prints the tags in "tags", those inside them \
            that went with them in "tagsInside", how many cards lost them in "cards", how many of those came back \
            to your reviews in "cardsBackInReviews", as the set-aside tags they had went, and, while only the cards \
            with chosen tags sync, how many stopped syncing in "cardsThatStopSyncing", left with no chosen tag.
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
            It deletes each tag that has something of its own, a pin, a switch, a color, an emoji or a choice to \
            sync, which no card carries, nor a tag inside it. While only the cards with chosen tags sync, it \
            deletes only those chosen and those inside them: another device may keep cards with a tag that \
            doesn't sync.
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

/// `ficha tag set-aside`: sets a tag aside, or stops.
struct SetTagAsideCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-aside",
        abstract: "Set a tag aside, or with --off stop setting it aside, and print the tag.",
        discussion: """
            A set-aside tag's cards, and those of the tags inside it, are out of your reviews for now; they keep \
            their steps. A priority tag set aside is no longer one.
            """
    )

    @Argument(help: "The tag's whole name, as `ficha tags` prints it.")
    var tag: String

    @ArgumentParser.Flag(help: "Stop setting it aside instead.")
    var off = false

    func run(on engine: Engine) throws -> any Encodable {
        let tag = try PrintedTags(of: engine).existing(tag)
        if off {
            try engine.stopSettingAside(tag)
        } else {
            try engine.setAside(tag)
        }
        return try PrintedTags(of: engine).tag(tag)
    }
}

/// `ficha tag prioritize`: makes a tag a priority tag, or not.
struct PrioritizeTagCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "prioritize",
        abstract: "Make a tag a priority tag, or with --off no longer one, and print the tag.",
        discussion: """
            A priority tag's cards come first when cards show up. A set-aside tag can't be one: stop setting it \
            aside first.
            """
    )

    @Argument(help: "The tag's whole name, as `ficha tags` prints it.")
    var tag: String

    @ArgumentParser.Flag(help: "Make it no longer a priority tag instead.")
    var off = false

    func run(on engine: Engine) throws -> any Encodable {
        let listing = try PrintedTags(of: engine)
        let current = try listing.tag(listing.existing(tag))
        if !off && current.setAside {
            throw SetAsideTagError(tag: current.name)
        }
        // Toggling switches it only when it isn't as asked already.
        if current.priority == off {
            try engine.togglePriority(of: current.name)
        }
        return try PrintedTags(of: engine).tag(current.name)
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

    /// The color given, or nil for none, or an error naming the colors.
    private func chosenColor() throws -> TagColor? {
        if color == "none" {
            return nil
        }
        guard let chosen = TagColor(rawValue: color) else {
            throw ValidationError(
                """
                “\(color)” isn't a color a tag can have. Pick one of \
                \(TagColor.allCases.map(\.rawValue).joined(separator: ", ")), or none.
                """)
        }
        return chosen
    }

    func validate() throws {
        _ = try chosenColor()
    }

    func run(on engine: Engine) throws -> any Encodable {
        let tag = try PrintedTags(of: engine).existing(tag)
        try engine.setColor(try chosenColor(), of: tag)
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

/// `ficha tag choose-to-sync`: chooses a tag to sync, or not.
struct ChooseTagToSyncCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "choose-to-sync",
        abstract: "Choose a tag to sync, or with --off untick it, and print the tag.",
        discussion: """
            While only the cards with chosen tags sync, as Settings' Sync tab chooses, a card syncs when it has a \
            chosen tag, or a tag inside one. Choosing between every card and chosen tags stays in Settings.
            """
    )

    @Argument(help: "The tag's whole name, as `ficha tags` prints it.")
    var tag: String

    @ArgumentParser.Flag(help: "Untick it instead.")
    var off = false

    func run(on engine: Engine) throws -> any Encodable {
        let tag = try PrintedTags(of: engine).existing(tag)
        try engine.chooseToSync(tag, !off)
        return try PrintedTags(of: engine).tag(tag)
    }
}

/// A tag as `ficha tags` prints it.
struct PrintedTag: Encodable, Equatable {
    let name: String
    let cards: Int
    let due: Int
    let pinned: Bool
    let pinPlace: Int?
    let setAside: Bool
    let priority: Bool
    let color: String?
    let emoji: String?
    let chosenToSync: Bool
}

/// Every tag as `ficha tags` prints it, read from the engine at once.
struct PrintedTags {
    /// Every tag, in the order a tree lists them.
    let tags: [PrintedTag]

    /// The tags `engine` holds now, each with its counts on the engine's
    /// ladder.
    init(of engine: Engine) throws {
        let counts = try engine.tagCounts(on: engine.progressSettings().ladder)
        let pinned = try engine.pinnedTags().map(\.name)
        tags = try engine.allTags().map { tag in
            PrintedTag(
                name: tag.name, cards: counts[tag.name]?.cards ?? 0, due: counts[tag.name]?.due ?? 0,
                pinned: tag.isPinned, pinPlace: pinned.firstIndex(of: tag.name), setAside: tag.isSetAside,
                priority: tag.isPriority, color: tag.color?.rawValue, emoji: tag.emoji,
                chosenToSync: tag.chosenToSync)
        }
    }

    /// The pinned tags, in their order.
    var pinned: [PrintedTag] {
        tags.filter(\.pinned).sorted { ($0.pinPlace ?? 0) < ($1.pinPlace ?? 0) }
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

    /// The tag named `name`, which exists.
    func tag(_ name: String) throws -> PrintedTag {
        guard let tag = tags.first(where: { $0.name == name }) else {
            throw UnknownTagError(tag: name)
        }
        return tag
    }
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

/// A set-aside tag `ficha tag prioritize` was asked to make a priority tag,
/// which a tag never is while it's set aside (ADR 0011).
struct SetAsideTagError: LocalizedError {
    /// The tag's whole name.
    let tag: String

    var errorDescription: String? {
        """
        “\(tag)” is set aside, and a tag is never both set aside and a priority tag, so nothing changed. Stop \
        setting it aside first, with `ficha tag set-aside \(tag) --off`.
        """
    }
}
