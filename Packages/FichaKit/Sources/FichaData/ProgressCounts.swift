/// What the menu shows of Lucas's progress.
public struct ProgressCounts: Sendable, Equatable {
    /// How many cards are due.
    public let due: Int
    /// How many cards he learned: those on a step that waits 30 days or more.
    public let learned: Int
    /// How many captures wait in the inbox.
    public let capturesInInbox: Int
}
