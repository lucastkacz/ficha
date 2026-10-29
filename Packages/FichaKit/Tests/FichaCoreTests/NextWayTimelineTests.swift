import FichaCore
import Foundation
import Testing

/// Tests on the widget's timeline as the planner works it out (#171): what it
/// shows from a time on, as if Lucas rated nothing in between, and where it
/// stops.
struct NextWayTimelineTests {
    let calendar: Calendar
    let now: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
        self.calendar = calendar
        now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9)))
    }

    @Test("a new card the widget shows stays as days go by, so the timeline ends, rather than asking again days ahead")
    func aNewCardStaysAsDaysGoBy() throws {
        let cards = CardsInReviews([card(1)], priorityTags: [], log: [])

        let timeline = try ReviewSettings.defaults.nextWayTimeline(cards: cards, from: now, calendar: calendar)

        #expect(timeline.entries.map(\.date) == [now])
        #expect(timeline.entries.map(\.nextWay) == [.waiting(CardWay(cardID: 1, way: .frontFirst), isNew: true)])
        #expect(timeline.refreshAt == nil)
    }

    @Test("with ways that come due more than 200 times, the timeline stops at the 200th, and is worked out again then")
    func stopsAfter200Looks() throws {
        // Each due a minute after the one before, on the first step, so the
        // first stays first.
        let placed = (1...250).map { id in
            placement(of: Int64(id), on: 0, dueAt: now + TimeInterval(id * 60))
        }
        let cards = CardsInReviews((1...250).map { card(Int64($0)) }, priorityTags: [], log: placed)

        let timeline = try ReviewSettings.defaults.nextWayTimeline(cards: cards, from: now, calendar: calendar)

        #expect(timeline.entries.map(\.date) == [now, now + 60])
        #expect(
            timeline.entries.map(\.nextWay) == [
                .comesAt(now + 60), .waiting(CardWay(cardID: 1, way: .frontFirst), isNew: false),
            ])
        #expect(timeline.refreshAt == now + 200 * 60)
    }

    @Test("a timeline whose widget changes more than 30 times stops at its 30th entry, and is worked out again then")
    func stopsAt30Entries() throws {
        // A ladder of 40 steps, and a card on each, each due an hour after
        // the one before, a step lower, so it comes first once it's due.
        var settings = ReviewSettings.defaults
        settings.ladder = try #require(Ladder(waits: (1...40).map { .seconds($0 * 60 * 60) }))
        let placed = (1...40).map { id in
            placement(of: Int64(id), on: 40 - id, dueAt: now + TimeInterval(id * 60 * 60))
        }
        let cards = CardsInReviews((1...40).map { card(Int64($0)) }, priorityTags: [], log: placed)

        let timeline = try settings.nextWayTimeline(cards: cards, from: now, calendar: calendar)

        #expect(timeline.entries.count == 30)
        #expect(timeline.entries.last?.date == now + 29 * 60 * 60)
        #expect(timeline.entries.last?.nextWay == .waiting(CardWay(cardID: 29, way: .frontFirst), isNew: false))
        #expect(timeline.refreshAt == now + 29 * 60 * 60)
    }

    /// The placement an import gave the card with the id `id`, a day before
    /// the test's time, on `step`, due at `due`.
    private func placement(of id: Int64, on step: Int, dueAt due: Date) -> ReviewLogEntry {
        ReviewLogEntry(placing: id, on: Placement(step: step, due: due), at: now - 24 * 60 * 60)
    }
}

/// The card with the id `id`, in Lucas's reviews, one way, with no tags.
private func card(_ id: Int64) -> (id: Int64, standing: CardStanding, tags: [String], bothWays: Bool) {
    (id, .inReviews, [], false)
}
