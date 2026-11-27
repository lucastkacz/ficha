import ArgumentParser
import FichaData

/// `ficha capture`: saves a capture in the inbox, unless it repeats a card or
/// a capture and isn't expanded.
struct CaptureCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Save a capture in the inbox, to refine later, and print the capture.",
        discussion: """
            A capture that repeats a card's front, the capture a card was approved from or a capture in the inbox, \
            ignoring case, accents, superscripts and subscripts, isn't saved: the command says what it repeats and fails. To keep it, capture it again with --expand; to ignore it, do \
            nothing.
            """
    )

    @Argument(help: "What you want to remember: a word, a concept, a quote or a question.")
    var text: String

    @Option(help: "A note on what you meant, for when you refine it.")
    var note: String?

    @Option(help: "Where you came across it: a book, a podcast…")
    var source: String?

    @ArgumentParser.Flag(
        help: """
            If it repeats a card, keep it in the inbox attached to that card, to add to it when you refine. If it \
            repeats a capture, keep it next to that one.
            """
    )
    var expand = false

    func run(on engine: Engine) throws -> any Encodable {
        if expand {
            return try engine.expand(text: text, note: note, source: source)
        }
        return switch try engine.capture(text: text, note: note, source: source) {
        case .saved(let capture):
            capture
        case .duplicate(let repeated):
            throw DuplicateCaptureError(text: text, repeated: repeated)
        }
    }
}

/// `ficha inbox`: lists what waits in the inbox.
struct InboxCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: """
            List what waits in the inbox: your captures, your cards' expansions, your follow-ups on them and the \
            cards you flagged.
            """,
        discussion: """
            It prints "captures", oldest first; "expansions", each a capture with the card it expands, oldest \
            first; "followUps", each a capture you asked in the review panel with the card it follows up, oldest \
            first; and "flaggedCards", each with your note on what to fix in "flag", the first flagged first.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.inbox()
    }
}

/// `ficha discard`: takes a capture out of the inbox without cards.
struct DiscardCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "discard",
        abstract: "Discard a capture: take it out of the inbox without cards, and print the capture."
    )

    @Argument(help: "The capture's id, as `ficha inbox` shows it.")
    var captureID: Int64

    func run(on engine: Engine) throws -> any Encodable {
        try engine.discard(captureID)
    }
}

/// `ficha set-aside`: sets a card aside, or puts it back, as `ficha deck
/// set-aside` does a deck (ADR 0041). The engine buries the card, as the
/// database keeps a card set aside on its own, and unburies it.
struct SetCardAsideCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-aside",
        abstract: "Set a card aside, or with --off put it back, and print the card.",
        discussion: """
            A card set aside is out of your reviews until you put it back, and out of the inbox too if it's \
            flagged, with its note; it keeps its progress and its review log, and its deck still lists it. Put \
            back, it goes back to your reviews, or to the inbox when it's flagged, or it stays set aside with its \
            deck while that deck, or a deck it sits inside, is. `ficha deck set-aside` sets a whole deck aside.
            """
    )

    @Argument(help: "The card's id, as `ficha cards` or `ficha inbox` shows it.")
    var cardID: Int64

    @ArgumentParser.Flag(help: "Put it back instead.")
    var off = false

    func run(on engine: Engine) throws -> any Encodable {
        if off {
            return try engine.unbury(cardID)
        }
        return try engine.bury(cardID)
    }
}

/// `ficha cards`: lists the cards.
struct CardsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "cards",
        abstract: "List your cards, in the order they came in, and whether each goes both ways.",
        discussion: """
            Every card says in "bothWays" whether it goes both ways, coming back first too, its back on top, once \
            you've met it; `ficha add`, `ficha approve` and `ficha fix` set it. Every card names in "deck" the deck it \
            lives in, by its whole name, as "Idiomas::Inglés", or "" for Default, where a card lives when it has no \
            other deck; `ficha add`, `ficha approve`, `ficha fix`, `ficha approve-expansion` and `ficha change-deck` \
            set it. A flagged card has your note on what to fix in "flag", one set aside on its own says when you \
            set it aside in "buriedAt", as `ficha set-aside` and the Cards window set it aside, and one set aside \
            with its deck lists in "setAsideBy" the set-aside decks it's set aside by, the outermost first: its own \
            deck, or decks it sits inside, as the Cards window and `ficha deck set-aside` set them aside. A card's \
            "type" is word, concept, quote or question, or a type of your own, by its name. A card \
            leaves out "type", "source" or "captureID" when it has no type, no source, or didn't come from a capture. \
            A card with an image or a sound on its front or back names it in "frontImage", "backImage", "frontSound" \
            or "backSound", left out when that side has none; a side with only an image or a sound has an empty text. \
            `ficha attach` puts one on a side and `ficha detach` takes one off, and `ficha add`, `ficha approve`, \
            `ficha approve-expansion` and `ficha fix` take them too. A card whose front or back changed since it came \
            in says when it last did in "editedAt": an edit, a fix, an approved expansion, a side's image or sound put \
            on or taken off, or an import; a change to its tags, type or source alone doesn't count.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.cards()
    }
}
