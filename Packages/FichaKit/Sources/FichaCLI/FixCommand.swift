import ArgumentParser
import FichaData

/// `ficha fix`: fixes a flagged card with new content. It reads the card as
/// JSON from standard input, like `ficha approve`.
struct FixCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix",
        abstract: "Fix a flagged card with new content, read as JSON from standard input.",
        discussion: """
            The card is a JSON object with \(cardFields). It replaces the card's content. For example:

              ficha fix 7 <<'EOF'
              {"type": "word", "front": "serendipia",
               "back": "Un hallazgo valioso que se da por casualidad.",
               "tags": ["lenguaje"], "source": "Un ensayo de Borges"}
              EOF

            Only a flagged card can be fixed. It leaves the inbox and goes back to your reviews, on its step, and \
            the command prints it.
            """
    )

    @Argument(help: "The flagged card's id, as `ficha inbox` shows it.")
    var cardID: Int64

    func validate() throws {
        try CardsInput.fixedCard.requireStandardInput()
    }

    func run(on engine: Engine) throws -> any Encodable {
        try engine.fix(cardID, with: card(in: standardInput(), as: .fixedCard))
    }
}
