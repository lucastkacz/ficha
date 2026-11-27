/// The hours in which appearances may happen (ADR 0003), by the device's
/// clock: from the start of the hour `start` to the start of the hour `end`,
/// which comes before it when they cross midnight, as from 20 to 3 they do
/// (ADR 0045). They're never the same hour. Each device keeps its own
/// (ADR 0017).
public struct ActiveHours: Sendable, Hashable {
    /// The hour they start at, from 0 to 23.
    public let start: Int
    /// The hour they end at, from 1 to 24: one before `start` ends them the
    /// next day.
    public let end: Int

    /// Whether they cross midnight, ending the next day.
    public var crossMidnight: Bool {
        end < start
    }

    /// Whether `hour`, an hour of the day from 0 to 23, is one of them.
    public func contains(_ hour: Int) -> Bool {
        // A stub for #564's tests: hours that cross midnight hold none.
        start <= hour && hour < end
    }
}

extension ActiveHours {
    /// From the hour `start`, from 0 to 23, to the hour `end`, from 1 to 24,
    /// or nil when either isn't such an hour, or when they're the same hour.
    public init?(from start: Int, to end: Int) {
        guard (0...23).contains(start), (1...24).contains(end), start != end else {
            return nil
        }
        self.init(start: start, end: end)
    }
}
