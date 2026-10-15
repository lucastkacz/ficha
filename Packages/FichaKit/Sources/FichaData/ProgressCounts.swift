/// What the menu shows of Lucas's progress. Each card counts in one place at
/// most: a flagged card in the inbox, and a buried one nowhere.
public struct ProgressCounts: Sendable, Equatable {
    /// How many cards in his reviews are due.
    public let due: Int
    /// How many cards in his reviews he learned: those on a step that waits
    /// 30 days or more.
    public let learned: Int
    /// How many captures and flagged cards wait in the inbox.
    public let inInbox: Int
}
