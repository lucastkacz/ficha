import ArgumentParser
import FichaCore
import FichaData
import Foundation

/// The fields of each card `ficha approve`, `ficha approve-expansion` and
/// `ficha fix` read, as their
/// help and their errors list them. The types are listed the British way,
/// with no comma before "or", like the rest of the text.
let cardFields = """
    type (\(CardType.builtIn.map(\.writtenName).formatted(.list(type: .or).locale(Locale(identifier: "en_GB")))), \
    the name of a type of your own, which Ficha makes when you have none by that name, or null when there's \
    none), front, back, tags (a list, which can be empty) and source (null when there's none), and can have \
    frontImage, backImage, frontSound and backSound (a file's path or name, or null), bothWays (true or false) \
    and deck (a deck's whole name, as `ficha decks` prints it, with "::" between a deck and a deck inside it, \
    which Ficha makes when you have none by that name, or "" for Default)
    """

/// What a card's frontImage, backImage, frontSound and backSound hold, as the
/// help of `ficha approve`, `ficha approve-expansion` and `ficha fix` says
/// it.
let fileFields = """
    frontImage, backImage, frontSound and backSound put an image or a sound on a side: the path of a file on your \
    Mac, such as "~/Downloads/coloratura.mp3", or the name of one Ficha holds, as `ficha cards` prints it. Ficha \
    shrinks an image, and converts a sound, a video's too, as it comes in. The CLI's sandbox lets it read files from \
    your Downloads folder alone.
    """

/// What `ficha approve-expansion` and `ficha fix` do with a side's image or
/// sound that a card gives as null or leaves out, as their help says it.
let filesKept = """
    null takes a side's image or sound off, and one left out stays, so a card copied from `ficha cards` keeps its \
    images and sounds.
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

/// The cards in `input`, a JSON list, which the engine checks as it saves
/// them.
func cards(in input: Data) throws -> [CardDraft] {
    do {
        return try JSONDecoder().decode([CardInput].self, from: input).map(\.draft)
    } catch let error as DecodingError {
        throw CardsInputError.unreadable(error, .list)
    }
}

/// The card in `input`, a JSON object read as `cardsInput` says, which the
/// engine checks as it saves it.
func card(in input: Data, as cardsInput: CardsInput) throws -> CardDraft {
    do {
        return try JSONDecoder().decode(CardInput.self, from: input).draft
    } catch let error as DecodingError {
        throw CardsInputError.unreadable(error, cardsInput)
    }
}

/// Everything on standard input.
func standardInput() throws -> Data {
    try FileHandle.standardInput.readToEnd() ?? Data()
}

/// A card as `ficha approve`, `ficha approve-expansion` and `ficha fix` read
/// it. Every field must be there, `type` and `source` too, as null when
/// there's none, so a misspelled field fails instead of passing for a missing
/// one, but a side's image and sound, which a card leaves out to keep its
/// own, `bothWays`, which a card leaves out to go one way or keep its own,
/// and `deck`, which a card leaves out to live in Default or stay in its own.
/// Other fields, such as those `ficha cards` prints, are ignored.
private struct CardInput: Decodable {
    /// The type's name, as `CardDraft` takes it.
    let type: String?
    let front: String
    let back: String
    let tags: [String]
    let source: String?
    let frontImage: FileChange
    let backImage: FileChange
    let frontSound: FileChange
    let backSound: FileChange
    /// True or false, or nil when it's left out; never null.
    let bothWays: Bool?
    /// A deck's whole name, or "" for Default, as `ficha cards` writes it, or
    /// nil when it's left out; never null.
    let deck: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String?.self, forKey: .type)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decode(String.self, forKey: .back)
        tags = try container.decode([String].self, forKey: .tags)
        source = try container.decode(String?.self, forKey: .source)
        frontImage = try Self.fileChange(in: container, forKey: .frontImage)
        backImage = try Self.fileChange(in: container, forKey: .backImage)
        frontSound = try Self.fileChange(in: container, forKey: .frontSound)
        backSound = try Self.fileChange(in: container, forKey: .backSound)
        bothWays = container.contains(.bothWays) ? try container.decode(Bool.self, forKey: .bothWays) : nil
        deck = container.contains(.deck) ? try container.decode(String.self, forKey: .deck) : nil
    }

    /// The card, as the engine takes it.
    var draft: CardDraft {
        CardDraft(
            type: type, front: front, back: back, tags: tags, source: source, frontImage: frontImage,
            backImage: backImage, frontSound: frontSound, backSound: backSound, bothWays: bothWays, deck: deck)
    }

    /// What the card does with a side's image or sound, under `key`: left
    /// out, it keeps the card's, or puts none on a new card; null takes it
    /// off; and a file's path or name puts that file on.
    private static func fileChange(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws
        -> FileChange
    {
        guard container.contains(key) else {
            return .keep
        }
        guard let text = try container.decode(String?.self, forKey: key) else {
            return .remove
        }
        guard let file = FileForSide(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "It's blank.")
        }
        return .put(file)
    }

    private enum CodingKeys: String, CodingKey {
        case type, front, back, tags, source, frontImage, backImage, frontSound, backSound, bothWays, deck
    }
}

/// What can be wrong with the cards `ficha approve`, `ficha approve-expansion`
/// or `ficha fix` reads, before the engine checks them.
/// Each message says where, so whoever wrote the JSON can fix it.
enum CardsInputError: LocalizedError {
    /// The input isn't the JSON the command reads, with every field.
    case unreadable(DecodingError, CardsInput)

    var errorDescription: String? {
        switch self {
        case .unreadable(let error, let input):
            """
            Couldn't read \(input.what): \(explanation(of: error, in: input)). \(input.rule); see \
            `ficha \(input.command) --help`.
            """
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
