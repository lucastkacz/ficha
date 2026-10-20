import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on what the Cards window lists: Lucas's cards, each with where it
/// stands on his ladder and when he last saw it.
struct CardsWindowTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("the Cards window lists every card but the buried ones, flagged ones with their flag")
    func theWindowListsEveryCardButTheBuriedOnes() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.bury(ojala.id)

        let rows = try engine.cardRows(on: ReviewSettings.defaults.ladder)

        #expect(rows.map(\.card.id) == [serendipia.id, ubuntu.id])
        #expect(rows.map(\.card.flag?.note) == [nil, "Falta un ejemplo"])
    }

    @Test("each card stands on the ladder Lucas set, with its step's wait, and was last seen at its latest answer")
    func eachCardStandsOnLucassLadder() throws {
        // A ladder of 10 minutes, 1 day and 3 days.
        var settings = ReviewSettings.defaults
        settings.ladder = try #require(Ladder(waits: [.seconds(minutes(10)), .seconds(days(1)), .seconds(days(3))]))
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("ubuntu", in: engine)
        try engine.record(
            .firstView, of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, settings: settings)
        time.advance(by: minutes(10))
        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)
        let climbedAt = time.now
        // A review ahead, whose good doesn't count, is still the last time
        // Lucas saw it.
        time.advance(by: hours(1))
        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings,
            reviewingAhead: true)

        let rows = try engine.cardRows(on: settings.ladder)

        #expect(rows.map(\.standing) == [.onLadder(step: 1, due: climbedAt + days(1)), .new])
        #expect(rows.map(\.wait) == [.seconds(days(1)), nil])
        #expect(rows.map(\.lastSeen) == [time.now, nil])
    }

    @Test("a flagged card keeps its step but has no due time, since it won't show up until it's fixed")
    func aFlaggedCardHasNoDueTime() throws {
        let ladder = ReviewSettings.defaults.ladder
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("ojalá", in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        try engine.climb(ubuntu, to: 2, movingForward: time)
        let serendipiaStanding = try engine.standing(of: serendipia.id, on: ladder)
        let ubuntuStanding = try engine.standing(of: ubuntu.id, on: ladder)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))

        let rows = try engine.cardRows(on: ladder)

        #expect(rows.map(\.standing) == [serendipiaStanding, ubuntuStanding, .new])
        #expect(rows.map(\.due) == [serendipiaStanding.due, nil, nil])
    }
}
