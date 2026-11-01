/// The settings that decide which cards Lucas reviews, and when, and how the
/// review panel behaves. Each one starts as a default from the MVP spec (#4)
/// and Lucas can change it in Settings; the app passes them to the engine as
/// a value. Some of them decide a card's progress, the ladder, the scheduler's
/// settings, the new cards a day and the forgotten-often count, and sync, so
/// the engine keeps them (`progress`); the rest stay each device's own.
public struct ReviewSettings: Sendable, Equatable {
    /// The waits a card climbs as Lucas remembers it.
    public var ladder: Ladder
    /// The settings FSRS spaces cards with, as Anki does (#404): kept and
    /// synced beside the ladder, which still spaces them until #407.
    public var scheduler: Scheduler
    /// How many cards an appearance or a review now brings at most, a new one
    /// included.
    public var cardsPerAppearance: Int
    /// How many new cards Lucas meets in a day at most, by his Mac's calendar
    /// day.
    public var newCardsPerDay: Int
    /// How far ahead an appearance looks: it brings along the cards due
    /// within it, and their reviews count as on time.
    public var lookAhead: Duration
    /// The hours of the day in which appearances may happen, by the Mac's
    /// clock: from the start of the first to the end of the last.
    public var activeHours: Range<Int>
    /// How long the next appearance waits at least after the last appearance
    /// or review now closed.
    public var separation: Duration
    /// How long an appearance waits at least after the Mac wakes.
    public var waitAfterWaking: Duration
    /// How long an appearance waits at least after a suppression ends, so
    /// Lucas has a moment to wrap up.
    public var waitAfterSuppression: Duration
    /// The suppressions in Settings that hold appearances back: Lucas can
    /// turn each one off. A Focus isn't in Settings, and always applies.
    public var suppressionsThatApply: Set<Suppression>
    /// How long the review panel stays open untouched before it closes on its
    /// own, which counts as a snooze.
    public var autoClose: Duration
    /// Whether the review panel takes the keyboard when it shows up on its
    /// own.
    public var focusMode: FocusMode
    /// How long Lucas must be idle before the review panel takes the
    /// keyboard, in the once-idle focus mode.
    public var idleBeforeTakingKeyboard: Duration
    /// How many reviews of one of a card's ways Lucas rates again in, since
    /// its front or back last changed, before the review panel offers to
    /// flag it as forgotten often, at least 1, or nil when it never offers.
    public var forgottenOftenAfter: Int?

    /// The settings Ficha starts with.
    public static let defaults = ReviewSettings(
        ladder: .standard,
        scheduler: .standard,
        cardsPerAppearance: 5,
        newCardsPerDay: 5,
        lookAhead: .seconds(20 * 60),
        // From 9:00 to 22:00.
        activeHours: 9..<22,
        separation: .seconds(30 * 60),
        waitAfterWaking: .seconds(2 * 60),
        waitAfterSuppression: .seconds(2 * 60),
        suppressionsThatApply: Set(Suppression.allCases.filter(\.isInSettings)),
        autoClose: .seconds(10 * 60),
        focusMode: .onceIdle,
        idleBeforeTakingKeyboard: .seconds(5),
        // Anki's number of lapses for a leech.
        forgottenOftenAfter: 8
    )
}
