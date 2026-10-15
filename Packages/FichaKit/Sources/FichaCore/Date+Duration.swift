import Foundation

extension Date {
    /// The time `duration` after this one.
    public func adding(_ duration: Duration) -> Date {
        addingTimeInterval(duration / .seconds(1))
    }
}
