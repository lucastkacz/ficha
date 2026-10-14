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
        abstract: "Aprueba una captura en una o más fichas, que lee en JSON de la entrada estándar.",
        discussion: """
            Las fichas son una lista JSON. Cada una tiene \(cardFields). Por ejemplo:

              ficha approve 12 <<'EOF'
              [{"type": "word", "front": "serendipia",
                "back": "Un hallazgo valioso que se da por casualidad.",
                "tags": ["lenguaje"], "source": null}]
              EOF

            Guarda las fichas como nuevas, en ese orden, saca la captura de la bandeja e imprime las fichas.
            """
    )

    @Argument(help: "El id de la captura, como lo muestra `ficha inbox`.")
    var captureID: Int64

    func validate() throws {
        // Without input, the command would wait for it in silence.
        if isatty(FileHandle.standardInput.fileDescriptor) == 1 {
            throw ValidationError("Pasale las fichas en JSON por la entrada estándar; mirá `ficha approve --help`.")
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
    type (\(CardType.allCases.map(\.rawValue).formatted(.list(type: .or).locale(Locale(identifier: "es"))))), \
    front, back, tags (una lista, que puede estar vacía) y source (null si no tiene)
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
            No se pudieron leer las fichas: \(explanation(of: error)). Tienen que ser una lista JSON donde cada \
            ficha tiene \(cardFields); mirá `ficha approve --help`.
            """
        case .blankSide(let position):
            "La ficha [\(position)] tiene el frente o el dorso vacío: escribí los dos."
        }
    }
}

/// Where the cards' JSON doesn't fit, and why.
private func explanation(of error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, let context):
        "a la ficha \(jsonPath(context.codingPath)) le falta \"\(key.stringValue)\""
    case .valueNotFound(_, let context):
        "\(jsonPath(context.codingPath)) es null"
    case .typeMismatch(_, let context):
        context.codingPath.isEmpty
            ? "no son una lista" : "\(jsonPath(context.codingPath)) no es del tipo que corresponde"
    case .dataCorrupted(let context):
        context.codingPath.isEmpty ? "no son JSON válido" : "\(jsonPath(context.codingPath)) no es válido"
    @unknown default:
        "no tienen la forma que corresponde"
    }
}

/// A place in the cards' JSON, like `[1].source`, or the list itself.
private func jsonPath(_ path: [any CodingKey]) -> String {
    guard !path.isEmpty else {
        return "la lista"
    }
    return path.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
}
