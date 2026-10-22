import Foundation

/// Lucas's flag on a card: his note on what to fix, and when he wrote it.
public struct Flag: Sendable, Equatable, Encodable {
    /// What to fix, in his words.
    public let note: String
    /// When he flagged the card.
    public let flaggedAt: Date

    public init(note: String, flaggedAt: Date) {
        self.note = note
        self.flaggedAt = flaggedAt
    }
}
