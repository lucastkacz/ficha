/// The settings that decide which cards Lucas reviews, and when, and how the
/// review panel behaves. Each one starts as a default from the MVP spec (#4),
/// but for the new cards a day and the desired retention, which start as
/// ADR 0034 sets them, and the hour Ficha's day starts at, as ADR 0045 sets it,
/// and Lucas can change it in Settings; the app passes them to the engine as a
/// value. Some of them decide a card's progress, the scheduler's settings, the
/// new cards a day, the hour Ficha's day starts at and the forgotten-often
/// count, and sync, so the engine keeps them (`progress`); the rest stay each
/// device's own.
public struct ReviewSettings: Sendable, Equatable {
    /// The settings FSRS spaces cards with, as Anki does (#404).
    public var scheduler: Scheduler
    /// How many cards an appearance or a review now brings at most, a new one
    /// included.
    public var cardsPerAppearance: Int
    /// How many new cards Lucas meets in a day at most, by Ficha's day, for
    /// every deck together: the pace's (`Pace`).
    public var newCardsPerDay: Int
    /// The hour Ficha's day starts at, by the device's clock, from 0 to 23:
    /// Ficha's day runs from it to the same hour the next day, and the new
    /// cards a day, the finish date and the days Ficha names count by it
    /// (ADR 0045).
    public var dayStartsAtHour: Int
    /// How far ahead an appearance looks: it brings along the cards due
    /// within it, and their reviews count as on time.
    public var lookAhead: Duration
    /// The hours in which appearances may happen, by the device's clock,
    /// which may cross midnight (ADR 0045).
    public var activeHours: ActiveHours
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
    /// How many lapses of one of a card's ways, agains while it was
    /// graduated, since its front or back last changed, before the review
    /// panel offers to flag it as forgotten often, at least 1, or nil when it
    /// never offers.
    public var forgottenOftenAfter: Int?

    /// The settings Ficha starts with, the scheduler's at 85% and the Steady
    /// pace (ADR 0034), on every device that stores none of its own: a new
    /// install, or one whose user never changed the settings that sync.
    public static let defaults = ReviewSettings(
        scheduler: .newInstall,
        cardsPerAppearance: 5,
        newCardsPerDay: Pace.steady.newCardsPerDay,
        // Anki's "Next day starts at".
        dayStartsAtHour: 4,
        lookAhead: .seconds(20 * 60),
        // From 9:00 to 22:00.
        activeHours: ActiveHours(start: 9, end: 22),
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

    /// Whether `hour`, an hour of the day from 0 to 23, is one of them: from
    /// `start` on, and before `end` on the same day or, when they cross
    /// midnight, the next.
    public func contains(_ hour: Int) -> Bool {
        crossMidnight ? start <= hour || hour < end : start <= hour && hour < end
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
