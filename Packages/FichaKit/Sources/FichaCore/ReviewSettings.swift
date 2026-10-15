/// The settings that decide which cards Lucas reviews, and when, and how the
/// review panel behaves. Each one is a default from the MVP spec (#4) that
/// he'll be able to change; the app passes them to the engine as a value.
public struct ReviewSettings: Sendable, Equatable {
    /// The waits a card climbs as Lucas remembers it.
    public let ladder: Ladder
    /// How many cards an appearance or a review now brings at most, a new one
    /// included.
    public let cardsPerAppearance: Int
    /// How many new cards Lucas meets in a day at most, by his Mac's calendar
    /// day.
    public let newCardsPerDay: Int
    /// How far ahead an appearance looks: it brings along the cards due
    /// within it, and their reviews count as on time.
    public let lookAhead: Duration
    /// The hours of the day in which appearances may happen, by the Mac's
    /// clock: from the start of the first to the end of the last.
    public let activeHours: Range<Int>
    /// How long the next appearance waits at least after the last appearance
    /// or review now closed.
    public let separation: Duration
    /// How long an appearance waits at least after the Mac wakes.
    public let waitAfterWaking: Duration
    /// How long the review panel stays open untouched before it closes on its
    /// own, which counts as a snooze.
    public let autoClose: Duration
    /// Whether the review panel takes the keyboard when it shows up on its
    /// own.
    public let focusMode: FocusMode
    /// How long Lucas must be idle before the review panel takes the
    /// keyboard, in the once-idle focus mode.
    public let idleBeforeTakingKeyboard: Duration

    /// The settings Ficha starts with.
    public static let defaults = ReviewSettings(
        ladder: .standard,
        cardsPerAppearance: 5,
        newCardsPerDay: 5,
        lookAhead: .seconds(20 * 60),
        // From 9:00 to 22:00.
        activeHours: 9..<22,
        separation: .seconds(30 * 60),
        waitAfterWaking: .seconds(2 * 60),
        autoClose: .seconds(10 * 60),
        focusMode: .onceIdle,
        idleBeforeTakingKeyboard: .seconds(5)
    )
}
