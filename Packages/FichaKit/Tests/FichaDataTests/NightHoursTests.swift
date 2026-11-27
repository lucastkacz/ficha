import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on active hours that cross midnight (ADR 0045), from 20 to 3 unless
/// a test says otherwise, with Ficha's other settings: Steady, and Ficha's
/// day from 4:00. They run in Buenos Aires, from 9 in the morning of
/// Wednesday the 14th.
struct NightHoursTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings: ReviewSettings

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        var settings = ReviewSettings.defaults
        settings.activeHours = try #require(ActiveHours(from: 20, to: 3))
        self.settings = settings
    }

    @Test(
        "with active hours from 20 to 3, an appearance may come at 20:00, 23:59 and 2:59, and none at 3:00 or 19:59",
        .bug(id: 564))
    func appearancesComeFromTwentyToThree() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let moments = try [at(19, 59), at(20, 0), at(23, 59), at(2, 59, day: 15), at(3, 0, day: 15)]

        let decisions = try moments.map { moment in
            time.move(to: moment)
            return try engine.checkAppearance(settings, mac: FakeMac())
        }

        let shows = AppearanceDecision.show([.new(serendipia)])
        #expect(decisions == [.notNow(.outsideActiveHours), shows, shows, shows, .notNow(.outsideActiveHours)])
    }

    @Test(
        "with active hours from 9 to 22, an appearance may come at 9:00 and 21:59, and none at 22:00 or 8:59",
        .bug(id: 564))
    func appearancesComeFromNineToTwentyTwoAsBefore() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let moments = try [at(9, 0), at(21, 59), at(22, 0), at(8, 59, day: 15)]

        let decisions = try moments.map { moment in
            time.move(to: moment)
            return try engine.checkAppearance(.defaults, mac: FakeMac())
        }

        let shows = AppearanceDecision.show([.new(serendipia)])
        #expect(decisions == [shows, shows, .notNow(.outsideActiveHours), .notNow(.outsideActiveHours)])
    }

    // Serendipia, met at 22:00, is due at 23:00. Left alone, each planned
    // appearance brings it again once the separation passed.
    @Test(
        "the iPhone's planned appearances for 20 to 3 cross midnight, with none from 3:00 to 19:59",
        .bug(id: 564))
    func plannedAppearancesCrossMidnight() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        time.move(to: try at(22, 0))
        try engine.meet(serendipia)

        let planned = try engine.upcomingAppearances(settings).prefix(10).map(\.time)

        let night = try [
            at(23, 0), at(23, 30), at(0, 0, day: 15), at(0, 30, day: 15), at(1, 0, day: 15), at(1, 30, day: 15),
            at(2, 0, day: 15), at(2, 30, day: 15),
        ]
        #expect(planned == night + [try at(20, 0, day: 15), try at(20, 30, day: 15)])
    }

    // As the debate's simulation found: the night's first appearance, at
    // 20:00, and the next, 30 minutes after it closed, bring the day's two
    // new cards, and the rest bring the reviews.
    @Test(
        "a week of 20 to 3 at Steady, with the day at 4:00, brings two new cards a night, in the night's first two appearances from 20:00",
        .bug(id: 564))
    func aWeekOfNightsBringsTwoNewCardsANight() throws {
        let week = try appearances(over: 7, from: try at(12, 0), newCards: 20, settings: settings, calendar: calendar)

        let withNewCards = week.filter { !$0.newCards.isEmpty }
        let nights = try (14..<21).flatMap { day in try [at(20, 0, day: day), at(20, 31, day: day)] }
        #expect(withNewCards.map(\.time) == nights)
        #expect(withNewCards.allSatisfy { $0.newCards.count == 1 })
    }

    // Arte's two cards: La Gioconda met at 22:00, tonight's first, and Las
    // Meninas, which may still come tonight.
    @Test(
        "the queue's new cards left today count tonight's active hours: at 23:00, with 20 to 3, Steady and one met tonight, one is left",
        .bug(id: 564))
    func newCardsLeftTodayCountTonight() throws {
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        try approveInDeck("Las Meninas", deck: "Arte", in: engine)
        time.move(to: try at(22, 0))
        try engine.meet(gioconda)
        time.move(to: try at(23, 0))

        let arte = try #require(try engine.queue(settings).first)

        let today = calendar.startOfDay(for: time.now)
        #expect(arte.newCards == 1)
        #expect(arte.finish == FinishDate(soonest: today, latest: today))
    }

    /// A time of day on a day in October 2026 by the tests' calendar: the
    /// 14th, unless another day is given.
    private func at(_ hour: Int, _ minute: Int, day: Int = 14) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }
}
