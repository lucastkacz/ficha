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
            expands, which keeps its step. For example:

              ficha approve-expansion 15 <<'EOF'
              {"type": "word", "front": "serendipia",
               "back": "Un hallazgo valioso que se da por casualidad. También, una película de 2001.",
               "tags": ["lenguaje", "cine"], "source": "Un ensayo de Borges"}
              EOF

            The expansion leaves the inbox, and the command prints the card. To make new cards out of an expansion \
            instead, approve it with `ficha approve`.
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
