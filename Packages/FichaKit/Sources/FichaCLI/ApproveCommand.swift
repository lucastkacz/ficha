import ArgumentParser
import FichaCore
import FichaData
import Foundation

/// `ficha approve`: approves a capture into cards. It reads them as JSON from
/// standard input, where Claude can pass any text in a quoted heredoc without
/// escaping it.
struct ApproveCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "approve",
        abstract: "Approves a capture into one or more cards, which it reads as JSON from standard input.",
        discussion: """
            The cards are a JSON list. Each one has \(cardFields). For example:

              ficha approve 12 <<'EOF'
              [{"type": "word", "front": "serendipia",
                "back": "Un hallazgo valioso que se da por casualidad.",
                "tags": ["lenguaje"], "source": null}]
              EOF

            Saves the cards as new, in that order, takes the capture out of the inbox, and prints the cards.
            """
    )

    @Argument(help: "The capture's id, as `ficha inbox` shows it.")
    var captureID: Int64

    func validate() throws {
        // Without input, the command would wait for it in silence.
        if isatty(FileHandle.standardInput.fileDescriptor) == 1 {
            throw ValidationError("Pass the cards as JSON on standard input; see `ficha approve --help`.")
        }
    }

    func run(on engine: Engine) throws -> any Encodable {
        let input = try FileHandle.standardInput.readToEnd() ?? Data()
        return try engine.approve(captureID, into: cards(in: input))
    }
}

/// The fields of each card `ficha approve` reads, as its help and its errors
/// list them.
private let cardFields = """
    type (\(CardType.allCases.map(\.rawValue).formatted(.list(type: .or).locale(Locale(identifier: "en"))))), \
    front, back, tags (a list, which can be empty) and source (null when there's none)
    """

/// A card as `ficha approve` reads it. Every field must be there, `source`
/// too, as null when there's none, so a misspelled field fails instead of
/// passing for a missing one.
private struct CardInput: Decodable {
    let type: CardType
    let front: String
    let back: String
    let tags: [String]
    let source: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(CardType.self, forKey: .type)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decode(String.self, forKey: .back)
        tags = try container.decode([String].self, forKey: .tags)
        source = try container.decode(String?.self, forKey: .source)
    }

    private enum CodingKeys: String, CodingKey {
        case type, front, back, tags, source
    }
}

/// The cards in `input`, a JSON list, cleaned up as `CardContent` says.
private func cards(in input: Data) throws -> [CardContent] {
    let cards: [CardInput]
    do {
        cards = try JSONDecoder().decode([CardInput].self, from: input)
    } catch let error as DecodingError {
        throw CardsInputError.unreadable(error)
    }
    return try cards.enumerated().map { position, card in
        guard
            let content = CardContent(
                type: card.type, front: card.front, back: card.back, tags: card.tags, source: card.source)
        else {
            throw CardsInputError.blankSide(position: position)
        }
        return content
    }
}

/// What can be wrong with the cards `ficha approve` reads. Each message says
/// where, so whoever wrote the JSON can fix it.
enum CardsInputError: LocalizedError {
    /// The input isn't a JSON list of cards with every field.
    case unreadable(DecodingError)
    /// The card at this position in the list has a blank front or back.
    case blankSide(position: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable(let error):
            """
            Couldn't read the cards: \(explanation(of: error)). They must be a JSON list where each card has \
            \(cardFields); see `ficha approve --help`.
            """
        case .blankSide(let position):
            "Card [\(position)] has a blank front or back: write both."
        }
    }
}

/// Where the cards' JSON doesn't fit, and why.
private func explanation(of error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, let context):
        "card \(jsonPath(context.codingPath)) is missing \"\(key.stringValue)\""
    case .valueNotFound(_, let context):
        "\(jsonPath(context.codingPath)) is null"
    case .typeMismatch(_, let context):
        context.codingPath.isEmpty
            ? "they aren't a list" : "\(jsonPath(context.codingPath)) isn't of the right type"
    case .dataCorrupted(let context):
        context.codingPath.isEmpty ? "they aren't valid JSON" : "\(jsonPath(context.codingPath)) isn't valid"
    @unknown default:
        "they don't have the right shape"
    }
}

/// A place in the cards' JSON, like `[1].source`, or the list itself.
private func jsonPath(_ path: [any CodingKey]) -> String {
    guard !path.isEmpty else {
        return "the list"
    }
    return path.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
}
