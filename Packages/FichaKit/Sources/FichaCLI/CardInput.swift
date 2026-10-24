import ArgumentParser
import FichaCore
import Foundation

/// The fields of each card `ficha approve`, `ficha approve-expansion` and
/// `ficha fix` read, as their
/// help and their errors list them. The types are listed the British way,
/// with no comma before "or", like the rest of the text.
let cardFields = """
    type (\(CardType.allCases.map(\.rawValue).formatted(.list(type: .or).locale(Locale(identifier: "en_GB")))), \
    or null when there's none), front, back, tags (a list, which can be empty) and source (null when there's none)
    """

/// What a command reads as JSON on standard input, where Claude can pass any
/// text in a quoted heredoc without escaping it, in the words its errors use:
/// a list of cards, which `ficha approve` reads, or one card, which `ficha
/// approve-expansion` and `ficha fix` read.
struct CardsInput {
    /// The command that reads it.
    let command: String
    /// What it holds, like "the cards".
    let what: String
    /// The input as a whole, as a place in it, like "the list".
    let whole: String
    /// The JSON it must be, like "a JSON list".
    let json: String
    /// What it must hold, as a sentence.
    let rule: String
    /// Whether it's a list, so a place in it starts with a card's position.
    let isList: Bool

    /// The list of cards `ficha approve` reads.
    static let list = CardsInput(
        command: "approve", what: "the cards", whole: "the list", json: "a JSON list",
        rule: "They must be a JSON list where each card has \(cardFields)", isList: true)
    /// The card `ficha fix` reads.
    static let fixedCard = oneCard(for: "fix")
    /// The card `ficha approve-expansion` reads.
    static let expandedCard = oneCard(for: "approve-expansion")

    /// One card, as `command` reads it.
    private static func oneCard(for command: String) -> CardsInput {
        CardsInput(
            command: command, what: "the card", whole: "the card", json: "a JSON object",
            rule: "It must be a JSON object with \(cardFields)", isList: false)
    }

    /// Checks that something comes on standard input: without it, the
    /// command would wait for it in silence.
    func requireStandardInput() throws {
        if isatty(FileHandle.standardInput.fileDescriptor) == 1 {
            throw ValidationError("Pass \(what) as JSON on standard input; see `ficha \(command) --help`.")
        }
    }
}

/// The cards in `input`, a JSON list, cleaned up as `CardContent` says.
func cards(in input: Data) throws -> [CardContent] {
    let cards: [CardInput]
    do {
        cards = try JSONDecoder().decode([CardInput].self, from: input)
    } catch let error as DecodingError {
        throw CardsInputError.unreadable(error, .list)
    }
    return try cards.enumerated().map { position, card in
        guard let content = card.content else {
            throw CardsInputError.blankSide(position: position)
        }
        return content
    }
}

/// The card in `input`, a JSON object read as `cardsInput` says, cleaned up as
/// `CardContent` says.
func card(in input: Data, as cardsInput: CardsInput) throws -> CardContent {
    let card: CardInput
    do {
        card = try JSONDecoder().decode(CardInput.self, from: input)
    } catch let error as DecodingError {
        throw CardsInputError.unreadable(error, cardsInput)
    }
    guard let content = card.content else {
        throw CardsInputError.blankSide(position: nil)
    }
    return content
}

/// Everything on standard input.
func standardInput() throws -> Data {
    try FileHandle.standardInput.readToEnd() ?? Data()
}

/// A card as `ficha approve`, `ficha approve-expansion` and `ficha fix` read
/// it. Every field must be
/// there, `type` and `source` too, as null when there's none, so a
/// misspelled field fails instead of passing for a missing one.
private struct CardInput: Decodable {
    let type: CardType?
    let front: String
    let back: String
    let tags: [String]
    let source: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(CardType?.self, forKey: .type)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decode(String.self, forKey: .back)
        tags = try container.decode([String].self, forKey: .tags)
        source = try container.decode(String?.self, forKey: .source)
    }

    /// What the card holds, cleaned up, or nil when its front or back is
    /// blank.
    var content: CardContent? {
        CardContent(type: type, front: front, back: back, tags: tags, source: source)
    }

    private enum CodingKeys: String, CodingKey {
        case type, front, back, tags, source
    }
}

/// What can be wrong with the cards `ficha approve`, `ficha approve-expansion`
/// or `ficha fix` reads.
/// Each message says where, so whoever wrote the JSON can fix it.
enum CardsInputError: LocalizedError {
    /// The input isn't the JSON the command reads, with every field.
    case unreadable(DecodingError, CardsInput)
    /// A card has a blank front or back: the one at this position in the
    /// list, or the only one, with no position.
    case blankSide(position: Int?)

    var errorDescription: String? {
        switch self {
        case .unreadable(let error, let input):
            """
            Couldn't read \(input.what): \(explanation(of: error, in: input)). \(input.rule); see \
            `ficha \(input.command) --help`.
            """
        case .blankSide(let position?):
            "Card [\(position)] has a blank front or back: write both."
        case .blankSide(nil):
            "The card has a blank front or back: write both."
        }
    }
}

/// Where the cards' JSON doesn't fit, and why.
private func explanation(of error: DecodingError, in input: CardsInput) -> String {
    switch error {
    case .keyNotFound(let key, let context):
        // A card in a list is missing it, or the only card is.
        context.codingPath.isEmpty
            ? "\(input.whole) is missing \"\(key.stringValue)\""
            : "card \(place(context.codingPath, in: input)) is missing \"\(key.stringValue)\""
    case .valueNotFound(_, let context):
        "\(place(context.codingPath, in: input)) is null"
    case .typeMismatch(_, let context) where context.codingPath.isEmpty:
        "the input isn't \(input.json)"
    case .typeMismatch(_, let context):
        "\(place(context.codingPath, in: input)) isn't of the right type"
    case .dataCorrupted(let context) where context.codingPath.isEmpty:
        "the input isn't valid JSON"
    case .dataCorrupted(let context):
        "\(place(context.codingPath, in: input)) isn't valid"
    @unknown default:
        "the input doesn't have the right shape"
    }
}

/// A place in the cards' JSON: like `[1].source` in a list, `source` in one
/// card, or the input as a whole.
private func place(_ path: [any CodingKey], in input: CardsInput) -> String {
    guard !path.isEmpty else {
        return input.whole
    }
    let place = path.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
    return input.isList ? place : String(place.drop { $0 == "." })
}
