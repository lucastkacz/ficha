import FichaCore
import Foundation

extension Engine {
    /// The queue new cards come from now.
    public func queue(_ settings: ReviewSettings) throws(EngineError) -> [QueuedDeck] {
        []
    }

    /// Moves `deck` to `position` in the queue.
    public func moveInQueue(deck: String, to position: QueuePosition) throws(EngineError) {}
}
