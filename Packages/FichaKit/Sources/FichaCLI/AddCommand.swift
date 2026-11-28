import ArgumentParser
import FichaData
import Foundation

/// `ficha add`: adds cards straight into their decks, so any agent that runs
/// commands on the Mac can make the user a deck (ADR 0043). It reads them as
/// JSON from standard input, where an agent can pass any text in a quoted
/// heredoc without escaping it, as `ficha fix` does.
struct AddCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add one or more cards straight into their decks, read as JSON from standard input.",
        discussion: """
            The cards are a JSON list. Each one has \(cardFields). For example:

              ficha add <<'EOF'
              [{"type": "word", "front": "serendipia",
                "back": "Un hallazgo valioso que se da por casualidad. Por ejemplo: «Fue pura serendipia: entré a la librería por la lluvia y salí con mi libro favorito».",
                "tags": ["etimología"], "source": null, "deck": "Idiomas::Español"}]
              EOF

            \(newCardFields)

            It saves the cards as new, in that order, and prints them. A card whose front repeats another card's, \
            one you have or one before it in the list, ignoring case, accents, superscripts and subscripts, adds \
            none of the list: the command says which card it repeats and fails.
            """
    )

    func validate() throws {
        try CardsInput.addedCards.requireStandardInput()
    }

    func run(on engine: Engine) async throws -> any Encodable {
        try await add(reading: standardInput(), on: engine)
    }

    /// Adds the cards in `input`, a JSON list as the command reads it, and
    /// returns them, as the command prints them; or adds none, and says why.
    func add(reading input: Data, on engine: Engine) async throws -> [Card] {
        let drafts = try cards(in: input, as: .addedCards)
        guard !drafts.isEmpty else {
            throw CardsInputError.noCards(.addedCards)
        }
        switch try await engine.add(drafts) {
        case .added(let cards):
            return cards
        case .duplicate(let position, of: .card(let card)):
            throw DuplicateCardError(
                position: position, front: drafts[position].front, repeated: .card(id: card.id, front: card.front))
        case .duplicate(let position, of: .cardInList(let earlier)):
            throw DuplicateCardError(
                position: position, front: drafts[position].front,
                repeated: .cardInList(position: earlier, front: drafts[earlier].front))
        }
    }
}

/// A list `ficha add` added none of, because a card in it repeats another
/// card's front, by the duplicate rule. Its message names both cards, and
/// says what to do.
struct DuplicateCardError: LocalizedError, Equatable {
    /// The card's place in the list, from 0, as the CLI's errors write it,
    /// like `[1]`.
    let position: Int
    /// Its front, as the list gives it.
    let front: String
    /// The card it repeats.
    let repeated: Repeated

    /// A card whose front a card in the list repeats.
    enum Repeated: Equatable {
        /// A card Ficha holds, by its id and its front.
        case card(id: Int64, front: String)
        /// A card before it in the list, by its place and its front, as the
        /// list gives it.
        case cardInList(position: Int, front: String)
    }

    var errorDescription: String? {
        """
        Card [\(position)], “\(trimmed(front))”, repeats \(repeatedCard), so no card of the list was added. Leave \
        it out, or give it a front of its own, and add the list again.
        """
    }

    /// The card it repeats, as its message names it.
    private var repeatedCard: String {
        switch repeated {
        case .card(let id, let front): "card \(id), “\(front)”"
        case .cardInList(let position, let front): "card [\(position)], “\(trimmed(front))”"
        }
    }
}

/// `front` as a message quotes it, without the spaces and line breaks around
/// it.
private func trimmed(_ front: String) -> String {
    front.trimmingCharacters(in: .whitespacesAndNewlines)
}
