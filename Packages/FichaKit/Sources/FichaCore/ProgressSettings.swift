/// The three settings that decide a card's progress: the ladder, how many new
/// cards a day, and when a card is forgotten often. They sync, so a card's
/// progress means the same on each of the user's devices (ADR 0017): the
/// engine keeps them in the database. The rest of `ReviewSettings`, when
/// Ficha shows up and how the review panel behaves, stays each device's own,
/// in the app's preferences.
public struct ProgressSettings: Sendable, Equatable {
    /// The waits a card climbs as the user remembers it.
    public var ladder: Ladder
    /// How many new cards the user meets in a day at most, by the device's
    /// calendar day.
    public var newCardsPerDay: Int
    /// How many reviews of one of a card's ways the user rates again in,
    /// since its front or back last changed, before the review panel offers
    /// to flag it as forgotten often, at least 1, or nil when it never
    /// offers.
    public var forgottenOftenAfter: Int?

    public init(ladder: Ladder, newCardsPerDay: Int, forgottenOftenAfter: Int?) {
        self.ladder = ladder
        self.newCardsPerDay = newCardsPerDay
        self.forgottenOftenAfter = forgottenOftenAfter
    }

    /// These settings, but for those that `changed` changed from `old`,
    /// which it gives: the user changed those, and these may hold another
    /// device's later change to the others.
    public func taking(_ changed: ProgressSettings, changedFrom old: ProgressSettings) -> ProgressSettings {
        var settings = self
        if changed.ladder != old.ladder {
            settings.ladder = changed.ladder
        }
        if changed.newCardsPerDay != old.newCardsPerDay {
            settings.newCardsPerDay = changed.newCardsPerDay
        }
        if changed.forgottenOftenAfter != old.forgottenOftenAfter {
            settings.forgottenOftenAfter = changed.forgottenOftenAfter
        }
        return settings
    }
}

extension ReviewSettings {
    /// Its settings that decide a card's progress, which sync: setting them
    /// leaves the rest as it is.
    public var progress: ProgressSettings {
        get {
            ProgressSettings(ladder: ladder, newCardsPerDay: newCardsPerDay, forgottenOftenAfter: forgottenOftenAfter)
        }
        set {
            ladder = newValue.ladder
            newCardsPerDay = newValue.newCardsPerDay
            forgottenOftenAfter = newValue.forgottenOftenAfter
        }
    }
}
