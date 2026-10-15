import ArgumentParser
import FichaData

/// `ficha capture`: saves a capture in the inbox.
struct CaptureCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Save a capture in the inbox, to refine later, and print the capture."
    )

    @Argument(help: "What you want to remember: a word, a concept, a quote or a question.")
    var text: String

    @Option(help: "A note on what you meant, for when you refine it.")
    var note: String?

    @Option(help: "Where you came across it: a book, a podcast…")
    var source: String?

    func run(on engine: Engine) throws -> any Encodable {
        try engine.capture(text: text, note: note, source: source)
    }
}

/// `ficha inbox`: lists what waits in the inbox.
struct InboxCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "List what waits in the inbox: your captures, and the cards you flagged.",
        discussion: """
            It prints "captures", oldest first, and "flaggedCards", each with your note on what to fix in "flag", \
            the first flagged first.
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
        abstract: "Bury a card: take it out of your reviews for good, with its history, and print the card.",
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
        discussion: "A card that was flagged when it was buried goes back to the inbox instead, with its note."
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
            A flagged card has your note on what to fix in "flag", and a buried one says when you buried it in \
            "buriedAt".
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.cards()
    }
}
