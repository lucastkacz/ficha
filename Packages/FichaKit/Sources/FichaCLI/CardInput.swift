import ArgumentParser
import FichaCore
import Foundation

/// The fields of each card `ficha approve` and `ficha fix` read, as their
/// help and their errors list them. The types are listed the British way,
/// with no comma before "or", like the rest of the text.
let cardFields = """
    type (\(CardType.allCases.map(\.rawValue).formatted(.list(type: .or).locale(Locale(identifier: "en_GB"))))), \
    front, back, tags (a list, which can be empty) and source (null when there's none)
    """

/// Checks that something comes on standard input, where `ficha approve` and
/// `ficha fix` read `what` as JSON: without it, the command would wait for it
/// in silence. Claude passes any text there in a quoted heredoc, without
/// escaping it.
func requireStandardInput(_ what: String, for command: String) throws {
    if isatty(FileHandle.standardInput.fileDescriptor) == 1 {
        throw ValidationError("Pass \(what) as JSON on standard input; see `ficha \(command) --help`.")
    }
}

/// Everything on standard input.
func standardInput() throws -> Data {
    try FileHandle.standardInput.readToEnd() ?? Data()
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

/// The card in `input`, a JSON object, cleaned up as `CardContent` says.
func card(in input: Data) throws -> CardContent {
    let card: CardInput
    do {
        card = try JSONDecoder().decode(CardInput.self, from: input)
    } catch let error as DecodingError {
        throw CardsInputError.unreadable(error, .one)
    }
    guard let content = card.content else {
        throw CardsInputError.blankSide(position: nil)
    }
    return content
}

/// A card as `ficha approve` and `ficha fix` read it. Every field must be
/// there, `source` too, as null when there's none, so a misspelled field
/// fails instead of passing for a missing one.
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

    /// What the card holds, cleaned up, or nil when its front or back is
    /// blank.
    var content: CardContent? {
        CardContent(type: type, front: front, back: back, tags: tags, source: source)
    }

    private enum CodingKeys: String, CodingKey {
        case type, front, back, tags, source
    }
}

/// What a command reads on standard input: a list of cards, as `ficha
/// approve` does, or one card, as `ficha fix` does.
enum CardsInputShape {
    case list
    case one
}

/// What can be wrong with the cards `ficha approve` or `ficha fix` reads.
/// Each message says where, so whoever wrote the JSON can fix it.
enum CardsInputError: LocalizedError {
    /// The input isn't a JSON list of cards, or a JSON card, with every
    /// field.
    case unreadable(DecodingError, CardsInputShape)
    /// A card has a blank front or back: the one at this position in the
    /// list, or the only one, with no position.
    case blankSide(position: Int?)

    var errorDescription: String? {
        switch self {
        case .unreadable(let error, .list):
            """
            Couldn't read the cards: \(explanation(of: error, in: .list)). They must be a JSON list where each card \
            has \(cardFields); see `ficha approve --help`.
            """
        case .unreadable(let error, .one):
            """
            Couldn't read the card: \(explanation(of: error, in: .one)). It must be a JSON object with \
            \(cardFields); see `ficha fix --help`.
            """
        case .blankSide(let position?):
            "Card [\(position)] has a blank front or back: write both."
        case .blankSide(nil):
            "The card has a blank front or back: write both."
        }
    }
}

/// Where the cards' JSON doesn't fit, and why.
private func explanation(of error: DecodingError, in shape: CardsInputShape) -> String {
    switch error {
    case .keyNotFound(let key, let context):
        // A card in a list is missing it, or the only card is.
        context.codingPath.isEmpty
            ? "\(jsonPath([], in: shape)) is missing \"\(key.stringValue)\""
            : "card \(jsonPath(context.codingPath, in: shape)) is missing \"\(key.stringValue)\""
    case .valueNotFound(_, let context):
        "\(jsonPath(context.codingPath, in: shape)) is null"
    case .typeMismatch(_, let context) where context.codingPath.isEmpty:
        shape == .list ? "they aren't a list" : "it isn't a JSON object"
    case .typeMismatch(_, let context):
        "\(jsonPath(context.codingPath, in: shape)) isn't of the right type"
    case .dataCorrupted(let context) where context.codingPath.isEmpty:
        shape == .list ? "they aren't valid JSON" : "it isn't valid JSON"
    case .dataCorrupted(let context):
        "\(jsonPath(context.codingPath, in: shape)) isn't valid"
    @unknown default:
        shape == .list ? "they don't have the right shape" : "it doesn't have the right shape"
    }
}

/// A place in the cards' JSON: like `[1].source` in a list, or `source` in
/// one card. The input itself is "the list" or "the card".
private func jsonPath(_ path: [any CodingKey], in shape: CardsInputShape) -> String {
    guard !path.isEmpty else {
        return shape == .list ? "the list" : "the card"
    }
    let place = path.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
    return shape == .list ? place : String(place.drop { $0 == "." })
}
