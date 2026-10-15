import FichaCore
import FichaData
import Foundation
import Testing

/// A card for a test to approve a capture into: it always has a front and a
/// back, and no tags or source unless the test gives them.
func card(
    _ type: CardType,
    front: String,
    back: String,
    tags: [String] = [],
    source: String? = nil
) throws -> CardContent {
    try #require(CardContent(type: type, front: front, back: back, tags: tags, source: source))
}

/// Approves a capture into one word card with this front, the way refining
/// saves cards, and returns the card: a new card, after the ones approved
/// before it.
@discardableResult
func approveCard(_ front: String, in engine: Engine) throws -> Card {
    let capture = try engine.capture(text: front, note: nil, source: nil)
    let cards = try engine.approve(
        capture.id, into: [card(.word, front: front, back: "Lo que quiere decir «\(front)».")])
    return try #require(cards.first)
}

extension Engine {
    /// Records a new card's first view, as the review panel does when Lucas
    /// presses "Entendido", from review now.
    func meet(_ card: Card) throws {
        try recordFirstView(of: card.id, responseTime: .seconds(8), trigger: .reviewNow)
    }

    /// Records a review of a due card with `rating`, as the review panel does
    /// when Lucas rates it, from review now, on the default ladder.
    func review(_ card: Card, _ rating: Rating) throws {
        try recordReview(
            of: card.id, rating: rating, responseTime: .seconds(3), trigger: .reviewNow,
            ladder: ReviewSettings.defaults.ladder)
    }
}

extension ManualTimeSource {
    /// Moves time forward to `date`.
    func move(to date: Date) {
        advance(by: date.timeIntervalSince(now))
    }
}

/// The calendar of a Mac in Buenos Aires, whose days start at midnight there,
/// whatever time zone runs the tests.
func buenosAiresCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
    return calendar
}

/// 9 in the morning of a day in October 2026, by `calendar`.
func morning(of day: Int, in calendar: Calendar) throws -> Date {
    try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9)))
}

/// A span of whole minutes, in seconds.
func minutes(_ count: Int) -> TimeInterval {
    TimeInterval(count * 60)
}

/// A span of whole hours, in seconds.
func hours(_ count: Int) -> TimeInterval {
    TimeInterval(count * 60 * 60)
}

/// A span of whole days, in seconds.
func days(_ count: Int) -> TimeInterval {
    TimeInterval(count * 24 * 60 * 60)
}
