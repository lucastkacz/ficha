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
            ignoring case and accents, isn't saved: the command says what it repeats and fails. To keep it, capture it again with --expand; to ignore it, do \
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
        abstract: "List what waits in the inbox: your captures, your cards' expansions and the cards you flagged.",
        discussion: """
            It prints "captures", oldest first; "expansions", each a capture with the card it expands, oldest \
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

/// `ficha bury`: takes a card out of the reviews for good.
struct BuryCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "bury",
        abstract: "Bury a card: take it out of your reviews for good, with its review log, and print the card.",
        discussion: "A flagged card leaves the inbox too, with its note, until it's unburied."
    )

    @Argument(help: "The card's id, as `ficha cards` or `ficha inbox` shows it.")
    var cardID: Int64

    func run(on engine: Engine) throws -> any Encodable {
        try engine.bury(cardID)
    }
}

/// `ficha unbury`: brings a buried card back.
struct UnburyCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "unbury",
        abstract: "Unbury a card: put it back in your reviews, on its step, and print the card.",
        discussion: """
            A card that was flagged when it was buried goes back to the inbox instead, with its note, and one with \
            a set-aside tag stays set aside.
            """
    )

    @Argument(help: "The buried card's id, as `ficha cards` shows it.")
    var cardID: Int64

    func run(on engine: Engine) throws -> any Encodable {
        try engine.unbury(cardID)
    }
}

/// `ficha cards`: lists the cards.
struct CardsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "cards",
        abstract: "List your cards, in the order you approved them.",
        discussion: """
            A flagged card has your note on what to fix in "flag", a buried one says when you buried it in \
            "buriedAt", and one with tags you set aside in the Cards window lists them in "setAsideBy". A card \
            leaves out "type", "source" or "captureID" when it has no type, no source, or didn't come from a \
            capture. A card with an image on its front or back names it in "frontImage" or "backImage", left out \
            when that side has none; a side with only an image has an empty text. Images are added in the Cards \
            window, never through the CLI.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.cards()
    }
}
