import ArgumentParser
import FichaData

/// `ficha fix`: fixes a flagged card with new content. It reads the card as
/// JSON from standard input, like `ficha approve`.
struct FixCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix",
        abstract: "Fix a flagged card with new content, read as JSON from standard input.",
        discussion: """
            The card is a JSON object with \(cardFields). It replaces the card's content, and the card keeps its \
            images and sounds. For example:

              ficha fix 7 <<'EOF'
              {"type": "word", "front": "serendipia",
               "back": "Un hallazgo valioso que se da por casualidad. Por ejemplo: «Fue pura serendipia: entré a la librería por la lluvia y salí con mi libro favorito».",
               "tags": ["lenguaje"], "source": "Un ensayo de Borges"}
              EOF

            Only a flagged card can be fixed. It leaves the inbox and goes back to your reviews, on its step, \
            unless one of its tags is set aside, and the command prints it.
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
