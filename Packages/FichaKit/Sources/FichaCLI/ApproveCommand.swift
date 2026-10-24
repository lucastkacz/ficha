import ArgumentParser
import FichaData

/// `ficha approve`: approves a capture into cards. It reads them as JSON from
/// standard input, where Claude can pass any text in a quoted heredoc without
/// escaping it.
struct ApproveCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "approve",
        abstract: "Approve a capture into one or more cards, read as JSON from standard input.",
        discussion: """
            The cards are a JSON list. Each one has \(cardFields). For example:

              ficha approve 12 <<'EOF'
              [{"type": "word", "front": "serendipia",
                "back": "Un hallazgo valioso que se da por casualidad. Por ejemplo: «Fue pura serendipia: entré a la librería por la lluvia y salí con mi libro favorito».",
                "tags": ["lenguaje"], "source": null}]
              EOF

            It saves the cards as new, in that order, takes the capture out of the inbox and prints the cards. A \
            follow-up is approved the same way, and the card it follows up stays as it is.
            """
    )

    @Argument(help: "The capture's id, as `ficha inbox` shows it.")
    var captureID: Int64

    func validate() throws {
        try CardsInput.list.requireStandardInput()
    }

    func run(on engine: Engine) throws -> any Encodable {
        try engine.approve(captureID, into: cards(in: standardInput()))
    }
}
