import Foundation

/// How fast new cards come, for every deck together (ADR 0034): Chill,
/// Steady or Faster, each a number of new cards a day, the setting that
/// decides progress by name. Steady to start. The numbers are provisional:
/// the Ficha Lab measured each pace's appearances and minutes a weekday.
public enum Pace: String, Sendable, CaseIterable, Codable {
    case chill, steady, faster

    /// The new cards a day this pace brings: 1, 2 or 4.
    public var newCardsPerDay: Int {
        switch self {
        case .chill: 1
        case .steady: 2
        case .faster: 4
        }
    }

    /// The pace that brings `newCardsPerDay` new cards a day, or nil when
    /// none does, as for a number a version of Ficha before the pace kept.
    public init?(newCardsPerDay: Int) {
        guard let pace = Self.allCases.first(where: { $0.newCardsPerDay == newCardsPerDay }) else {
            return nil
        }
        self = pace
    }
}
