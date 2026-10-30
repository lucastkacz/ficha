import ArgumentParser
import FichaData

/// `ficha fix`: fixes a flagged card with new content. It reads the card as
/// JSON from standard input, like `ficha approve`.
struct FixCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix",
        abstract: "Fix a flagged card with new content, read as JSON from standard input.",
        discussion: """
            The card is a JSON object with \(cardFields). It replaces the card's content. \(fileFields) \
            \(filesKept) For example:

              ficha fix 7 <<'EOF'
              {"type": "word", "front": "serendipia",
               "back": "Un hallazgo valioso que se da por casualidad. Por ejemplo: «Fue pura serendipia: entré a la librería por la lluvia y salí con mi libro favorito».",
               "tags": ["lenguaje"], "source": "Un ensayo de Borges"}
              EOF

            bothWays true or false switches Both ways on or off, so the card comes back first too, its back on \
            top, or doesn't; left out, the card keeps its own.

            Only a flagged card can be fixed. It leaves the inbox and goes back to your reviews, on its step, \
            unless its deck, or a deck it sits inside, is set aside, and the command prints it.
            """
    )

    @Argument(help: "The flagged card's id, as `ficha inbox` shows it.")
    var cardID: Int64

    func validate() throws {
        try CardsInput.fixedCard.requireStandardInput()
    }

    func run(on engine: Engine) async throws -> any Encodable {
        try await engine.fix(cardID, with: card(in: standardInput(), as: .fixedCard))
    }
}
