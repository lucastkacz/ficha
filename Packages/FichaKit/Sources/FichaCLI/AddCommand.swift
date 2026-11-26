import ArgumentParser
import FichaData
import Foundation

/// `ficha add`: adds cards straight into their decks (ADR 0041). A stub,
/// until #534's code.
struct AddCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add one or more cards straight into their decks, read as JSON from standard input."
    )

    func run(on engine: Engine) async throws -> any Encodable {
        try await add(reading: standardInput(), on: engine)
    }

    /// Adds the cards in `input`, and returns them as the command prints
    /// them. A stub, until #534's code.
    func add(reading input: Data, on engine: Engine) async throws -> [Card] {
        []
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
