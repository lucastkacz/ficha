/// The settings that decide which cards Lucas reviews, and when. Each one is a
/// default from the MVP spec (#4) that he'll be able to change; the app passes
/// them to the engine as a value.
public struct ReviewSettings: Sendable, Equatable {
    /// The waits a card climbs as Lucas remembers it.
    public let ladder: Ladder
    /// How many cards an appearance or a review now brings at most, a new one
    /// included.
    public let cardsPerAppearance: Int
    /// How many new cards Lucas meets in a day at most, by his Mac's calendar
    /// day.
    public let newCardsPerDay: Int

    /// The settings Ficha starts with.
    public static let defaults = ReviewSettings(ladder: .standard, cardsPerAppearance: 5, newCardsPerDay: 5)
}
