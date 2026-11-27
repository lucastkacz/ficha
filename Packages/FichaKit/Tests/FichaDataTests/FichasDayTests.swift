import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on Ficha's day (ADR 0045): from 4:00, or the hour the user sets, to
/// the same hour the next day, by the Mac's clock, so that a night that
/// crosses midnight is one day for the new cards a day and the days Ficha
/// names. They run at Steady, in Buenos Aires, from 9 in the morning of
/// Wednesday the 14th.
struct FichasDayTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // Active hours all day, so that appearances may come at 23:59 and at
    // 0:30. Ubuntu was met at 21:00, and each card is answered easy, so none
    // is due again for days.
    @Test(
        "with the day at 4:00 and Steady, a new card shown at 23:59 and answered at 0:00 counts toward the day that began at 4:00 the day before, so an appearance at 0:30 brings no new card",
        .bug(id: 562))
    func aNewCardAnsweredAfterMidnightCountsTowardTheNight() throws {
        var settings = ReviewSettings.defaults
        settings.activeHours = try #require(ActiveHours(from: 0, to: 24))
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try approveCard("serendipia", in: engine)
        time.move(to: try at(21, 0))
        try meetEasily(ubuntu)

        time.move(to: try at(23, 59))
        let shown = try engine.checkAppearance(settings, mac: FakeMac())
        var panel = try engine.openPanel(.appearance, with: [.new(petricor)], settings: settings)
        time.move(to: try at(0, 0, day: 15))
        try panel.answer(.review(.easy), responseTime: .seconds(60))
        panel.close(.byLucas)
        time.move(to: try at(0, 30, day: 15))

        #expect(shown == .show([.new(petricor)]))
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
    }

    @Test(
        "a review now at 3:59 brings no new card of a day whose new cards were met, and one at 4:00 brings one",
        .bug(id: 562))
    func theDayTurnsAtFour() throws {
        let serendipia = try meetTheDaysTwo(at: try at(21, 0))

        time.move(to: try at(3, 59, day: 15))
        let atThreeFiftyNine = try engine.reviewNow(.defaults)
        time.move(to: try at(4, 0, day: 15))

        #expect(atThreeFiftyNine.isEmpty)
        #expect(try engine.reviewNow(.defaults) == [.new(serendipia)])
    }

    @Test("with the day at 6:00, it turns at 6:00", .bug(id: 562))
    func theDayTurnsAtTheHourItStartsAt() throws {
        var settings = ReviewSettings.defaults
        settings.dayStartsAtHour = 6
        let serendipia = try meetTheDaysTwo(at: try at(21, 0))

        time.move(to: try at(4, 0, day: 15))
        let atFour = try engine.reviewNow(settings)
        time.move(to: try at(5, 59, day: 15))
        let atFiveFiftyNine = try engine.reviewNow(settings)
        time.move(to: try at(6, 0, day: 15))

        #expect(atFour.isEmpty)
        #expect(atFiveFiftyNine.isEmpty)
        #expect(try engine.reviewNow(settings) == [.new(serendipia)])
    }

    // As the debate's simulation found: the new cards of a day whose active
    // hours end before midnight come at the same times whether the day
    // starts at midnight or at 4:00, and so do the reviews they bring.
    @Test(
        "with active hours 9 to 22, a week brings the same appearances, with the same new cards, with the day at 4:00 as at midnight",
        .bug(id: 562))
    func aWeekOfDaytimeHoursIsTheSameWithTheDayAtFour() throws {
        var atMidnight = ReviewSettings.defaults
        atMidnight.dayStartsAtHour = 0

        let midnightWeek = try appearances(
            over: 7, from: time.now, newCards: 20, settings: atMidnight, calendar: calendar)
        let fourWeek = try appearances(over: 7, from: time.now, newCards: 20, settings: .defaults, calendar: calendar)

        #expect(fourWeek == midnightWeek)
        #expect(fourWeek.flatMap(\.newCards).count == 14)
    }

    // At 2:00 on Thursday the 15th, Ficha's day is still Wednesday's, whose
    // two new cards were met: Arte's other two come on Thursday at the
    // soonest, and by Friday at the latest, as five days in seven count.
    @Test(
        "a deck's finish date counts days from 4:00: at 2:00, the day whose new cards were met is still today, so the deck is met tomorrow at the soonest",
        .bug(id: 562))
    func aFinishDateCountsDaysFromFour() throws {
        let arte = try ["La Gioconda", "Las Meninas", "El Grito", "La noche estrellada"].map {
            try approveInDeck($0, deck: "Arte", in: engine)
        }
        time.move(to: try at(21, 0))
        try meetEasily(arte[0])
        try meetEasily(arte[1])
        time.move(to: try at(2, 0, day: 15))

        let finish = try #require(try engine.queue(.defaults).first?.finish)

        let (thursday, friday) = (try startOfDay(15), try startOfDay(16))
        #expect(finish == FinishDate(soonest: thursday, latest: friday))
        #expect(
            finish.wording(now: time.now, dayStartsAtHour: 4, calendar: calendar)
                == .dayOrNext(.tomorrow, .weekday(friday)))
    }

    /// Approves ubuntu, petricor and serendipia, and meets the first two at
    /// `time`, answered easy, so they're the day's two new cards at Steady,
    /// due again days later; and returns serendipia, still new.
    private func meetTheDaysTwo(at time: Date) throws -> Card {
        let met = try ["ubuntu", "petricor"].map { try approveCard($0, in: engine) }
        let serendipia = try approveCard("serendipia", in: engine)
        self.time.move(to: time)
        for card in met {
            try meetEasily(card)
        }
        return serendipia
    }

    /// Records the first review of a card's new way, front first, rated
    /// easy, from review now: it graduates, due days later.
    private func meetEasily(_ card: Card) throws {
        try engine.record(
            .review(.easy), of: card.id, responseTime: .seconds(8), trigger: .reviewNow, settings: .defaults)
    }

    /// A time of day on a day in October 2026 by the tests' calendar: the
    /// 14th, unless another day is given.
    private func at(_ hour: Int, _ minute: Int, day: Int = 14) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    /// The start of the day `day` of October 2026, by the tests' calendar.
    private func startOfDay(_ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day)))
    }
}
