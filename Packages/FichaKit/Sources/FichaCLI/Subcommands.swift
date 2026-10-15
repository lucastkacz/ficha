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

/// `ficha inbox`: lists the captures waiting in the inbox.
struct InboxCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "List the captures waiting in the inbox, oldest first."
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

/// `ficha cards`: lists the cards.
struct CardsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "cards",
        abstract: "List your cards, in the order you approved them."
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.cards()
    }
}
