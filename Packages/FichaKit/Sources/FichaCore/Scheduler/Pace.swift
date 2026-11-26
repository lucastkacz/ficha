import Foundation

/// How fast new cards come, for every deck together (ADR 0034): Chill,
/// Steady or Faster, each a number of new cards a day, the setting that
/// decides progress by name. Steady to start. The numbers are provisional:
/// the Ficha Lab measured each pace's appearances and minutes a weekday.
public enum Pace: String, Sendable, CaseIterable, Codable {
    case chill, steady, faster

    /// The new cards a day this pace brings.
    public var newCardsPerDay: Int {
        0
    }

    /// The pace that brings `newCardsPerDay` new cards a day, or nil when
    /// none does, as when the CLI or another version set another number.
    public init?(newCardsPerDay: Int) {
        return nil
    }
}
