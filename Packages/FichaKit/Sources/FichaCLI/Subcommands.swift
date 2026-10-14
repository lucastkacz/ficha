import ArgumentParser
import FichaData

/// `ficha capture`: saves a capture in the inbox.
struct CaptureCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Guarda una captura en la bandeja, para refinarla después, e imprime la captura."
    )

    @Argument(help: "Lo que querés recordar: una palabra, un concepto, una frase o una pregunta.")
    var text: String

    @Option(help: "Una nota sobre qué quisiste decir, para cuando la refines.")
    var note: String?

    @Option(help: "Dónde lo encontraste: un libro, un podcast…")
    var source: String?

    func run(on engine: Engine) throws -> any Encodable {
        try engine.capture(text: text, note: note, source: source)
    }
}

/// `ficha inbox`: lists the captures waiting in the inbox.
struct InboxCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Lista las capturas que esperan en la bandeja, de la más vieja a la más nueva."
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.inbox()
    }
}

/// `ficha discard`: takes a capture out of the inbox without cards.
struct DiscardCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "discard",
        abstract: "Descarta una captura: la saca de la bandeja sin fichas, e imprime la captura."
    )

    @Argument(help: "El id de la captura, como lo muestra `ficha inbox`.")
    var captureID: Int64

    func run(on engine: Engine) throws -> any Encodable {
        try engine.discard(captureID)
    }
}

/// `ficha cards`: lists the cards.
struct CardsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "cards",
        abstract: "Lista tus fichas, en el orden en que las aprobaste."
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.cards()
    }
}
