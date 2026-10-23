import ArgumentParser
import FichaData

/// `ficha approve-expansion`: adds an expansion to its card, with the card's
/// new content. It reads the card as JSON from standard input, like `ficha
/// fix`.
struct ApproveExpansionCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "approve-expansion",
        abstract: "Approve an expansion: give its card new content, read as JSON from standard input.",
        discussion: """
            The card is a JSON object with \(cardFields). It replaces the content of the card the expansion \
            expands, which keeps its step and its images. For example:

              ficha approve-expansion 15 <<'EOF'
              {"type": "word", "front": "serendipia",
               "back": "Un hallazgo valioso que se da por casualidad, cuando estabas buscando otra cosa. Por ejemplo: «Fue pura serendipia: entré a la librería por la lluvia y salí con mi libro favorito».",
               "tags": ["lenguaje"], "source": "Un podcast de etimología"}
              EOF

            The expansion leaves the inbox, and the command prints the card. To make new cards out of an expansion \
            instead, such as one for another meaning of the word, approve it with `ficha approve`.
            """
    )

    @Argument(help: "The expansion's capture id, as `ficha inbox` shows it.")
    var captureID: Int64

    func validate() throws {
        try CardsInput.expandedCard.requireStandardInput()
    }

    func run(on engine: Engine) throws -> any Encodable {
        try engine.approveExpansion(captureID, into: card(in: standardInput(), as: .expandedCard))
    }
}
