import FichaCore
import Foundation
internal import GRDB

/// One small thing Lucas wants to remember, with a front and a back, as the
/// engine saved it when he approved it. The `ficha` CLI prints it as JSON,
/// without the source it doesn't have.
public struct Card: Sendable, Equatable, Encodable {
    public let id: Int64
    public let type: CardType
    public let front: String
    public let back: String
    public let tags: [String]
    public let source: String?
    /// When Lucas approved it.
    public let createdAt: Date
    /// The capture it was refined from.
    public let captureID: Int64
}

extension Card {
    /// A card read from a row of the `card` table, whose tags are a JSON array.
    init(row: Row) throws {
        id = try row.decode(forColumn: "id")
        let typeName: String = try row.decode(forColumn: "type")
        guard let type = CardType(rawValue: typeName) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Card \(id) has an unknown type")
            )
        }
        self.type = type
        front = try row.decode(forColumn: "front")
        back = try row.decode(forColumn: "back")
        let tagsColumn: String = try row.decode(forColumn: "tags")
        tags = try JSONDecoder().decode([String].self, from: Data(tagsColumn.utf8))
        source = try row.decode(forColumn: "source")
        createdAt = try row.decode(forColumn: "createdAt")
        captureID = try row.decode(forColumn: "captureId")
    }
}

/// A card's tags as the `card` table keeps them: a JSON array, which
/// `Card(row:)` reads back.
func tagsJSON(_ tags: [String]) throws -> String {
    String(decoding: try JSONEncoder().encode(tags), as: UTF8.self)
}
