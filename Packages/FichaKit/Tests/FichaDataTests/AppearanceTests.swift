import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on when the review panel shows up on its own, and with which cards
/// (ADR 0003), with the default settings. They start at 9 in the morning in
/// Buenos Aires, when active hours start.
struct AppearanceTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("the review panel shows up on its own once a card is due, and not before")
    func showsUpOnceACardIsDue() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))

        time.move(to: try at(10, 0) - 1)
        #expect(try appearance() == .notNow(.nothingDue))
        time.move(to: try at(10, 0))
        #expect(try appearance() == .show([.review(serendipia)]))
    }

    @Test("with nothing due, a single new card is enough for an appearance")
    func aNewCardIsEnoughWithNothingDue() throws {
        let serendipia = try approveCard("serendipia", in: engine)

        #expect(try appearance() == .show([.firstView(serendipia)]))
    }

    @Test("an appearance brings along the cards due within the next 20 minutes, and not those due later")
    func bringsAlongTheCardsDueWithinTwentyMinutes() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 20))
        try meetCard("petricor", dueAt: try at(10, 21))

        time.move(to: try at(10, 0))

        #expect(try appearance() == .show([.review(ubuntu), .review(serendipia)]))
    }

    // So that a card brought along moves on the ladder as if it had waited
    // its whole wait, while a review ahead, which Lucas asks for, doesn't
    // (ADR 0002).
    @Test("a card an appearance brings along before it's due is reviewed as on time, unlike one due later")
    func cardsBroughtAlongAreReviewedOnTime() throws {
        try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 20))
        let petricor = try meetCard("petricor", dueAt: try at(10, 21))
        time.move(to: try at(10, 0))

        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .appearance, settings: settings)

        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == .onLadder(step: 1, due: try at(14, 0)))
        #expect(throws: EngineError.cardNotDue(petricor.id)) {
            try engine.record(
                .review(.good), of: petricor.id, responseTime: .seconds(3), trigger: .appearance, settings: settings)
        }
    }

    @Test("the cards an appearance brings along take their place by step, as review now's cards do")
    func cardsBroughtAlongTakeTheirPlaceByStep() throws {
        // petricor climbs to the second step, due at 14:00, and ubuntu waits
        // on the first, due at 14:10.
        let petricor = try meetCard("petricor", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        try engine.review(petricor, .good)
        let ubuntu = try meetCard("ubuntu", dueAt: try at(14, 10))

        time.move(to: try at(14, 0))

        #expect(try appearance() == .show([.review(ubuntu), .review(petricor)]))
    }

    @Test("appearances only happen within active hours, from 9:00 to 22:00 by the Mac's clock")
    func onlyWithinActiveHours() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))

        time.move(to: try at(8, 59, day: 15))
        #expect(try appearance() == .notNow(.outsideActiveHours))
        time.move(to: try at(9, 0, day: 15))
        #expect(try appearance() == .show([.review(serendipia)]))
        time.move(to: try at(21, 59, day: 15))
        #expect(try appearance() == .show([.review(serendipia)]))
        time.move(to: try at(22, 0, day: 15))
        #expect(try appearance() == .notNow(.outsideActiveHours))
    }

    @Test(
        "the next appearance comes no sooner than 30 minutes after the last appearance or review now closed",
        arguments: [Trigger.appearance, .reviewNow]
    )
    func waitsThirtyMinutesAfterTheLastOneClosed(trigger: Trigger) throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 5))
        try engine.recordClosing(of: trigger, shownAt: try at(10, 0), outcome: .snoozed)

        time.move(to: try at(10, 35) - 1)
        #expect(try appearance() == .notNow(.tooSoonAfterLastOne(until: try at(10, 35))))
        time.move(to: try at(10, 35))
        #expect(try appearance() == .show([.review(serendipia)]))
    }

    @Test("after the Mac wakes, a waiting appearance comes 2 minutes later")
    func waitsTwoMinutesAfterTheMacWakes() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        let mac = FakeMac(lastWake: try at(10, 30))

        time.move(to: try at(10, 32) - 1)
        #expect(try appearance(on: mac) == .notNow(.tooSoonAfterWaking(until: try at(10, 32))))
        time.move(to: try at(10, 32))
        #expect(try appearance(on: mac) == .show([.review(serendipia)]))
    }

    @Test(
        "an appearance snoozed with Esc or closed on its own leaves its cards due for the next one",
        arguments: [AppearanceLogEntry.Outcome.snoozed, .autoClosed]
    )
    func aSnoozedAppearanceLeavesItsCardsDue(outcome: AppearanceLogEntry.Outcome) throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        #expect(try appearance() == .show([.review(serendipia)]))

        time.move(to: try at(10, 10))
        try engine.recordClosing(of: .appearance, shownAt: try at(10, 0), outcome: outcome)

        time.move(to: try at(10, 40))
        #expect(try appearance() == .show([.review(serendipia)]))
    }

    // A first view counts once Lucas ends it with "Got it", so a new card he
    // snoozed comes back in the next appearance.
    @Test("a snoozed first view doesn't count toward the day's 5 new cards")
    func aSnoozedFirstViewDoesNotCount() throws {
        let met = try ["ubuntu", "petricor", "serendipia", "Schadenfreude"].map { try approveCard($0, in: engine) }
        let ockham = try approveCard("navaja de Ockham", in: engine)
        for card in met {
            try engine.meet(card)
        }
        #expect(try appearance() == .show([.firstView(ockham)]))

        time.move(to: try at(9, 5))
        try engine.recordClosing(of: .appearance, shownAt: try at(9, 0), outcome: .snoozed)

        time.move(to: try at(9, 35))
        #expect(try appearance() == .show([.firstView(ockham)]))
    }

    // 21:00 in Buenos Aires is already the next day in UTC.
    @Test("the day's new cards start over at midnight, by the Mac's calendar")
    func newCardsStartOverAtMidnight() throws {
        time.move(to: try at(21, 0))
        let met = try ["ubuntu", "petricor", "serendipia", "Schadenfreude", "navaja de Ockham"].map {
            try approveCard($0, in: engine)
        }
        let sunkCost = try approveCard("costo hundido", in: engine)
        for card in met {
            try engine.meet(card)
        }

        time.move(to: try at(21, 30))
        #expect(try appearance() == .notNow(.nothingDue))

        time.move(to: try at(9, 0, day: 15))
        for card in met {
            try engine.review(card, .good)
        }
        #expect(try appearance() == .show([.firstView(sunkCost)]))
    }

    @Test("every appearance and review now goes into the appearance log, with its trigger, times and outcome")
    func appearancesAndReviewNowsGoIntoTheAppearanceLog() throws {
        time.move(to: try at(10, 3))
        try engine.recordClosing(of: .appearance, shownAt: try at(10, 0), outcome: .snoozed)
        time.move(to: try at(11, 20))
        try engine.recordClosing(of: .reviewNow, shownAt: try at(11, 18), outcome: .finished)
        time.move(to: try at(12, 10))
        try engine.recordClosing(of: .appearance, shownAt: try at(12, 0), outcome: .autoClosed)

        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(10, 0), closedAt: try at(10, 3), outcome: .snoozed),
                AppearanceLogEntry(
                    trigger: .reviewNow, shownAt: try at(11, 18), closedAt: try at(11, 20), outcome: .finished),
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(12, 0), closedAt: try at(12, 10), outcome: .autoClosed),
            ]
        )
    }

    /// What the engine decides now about an appearance, on `mac`.
    private func appearance(on mac: FakeMac = FakeMac()) throws -> AppearanceDecision {
        try engine.checkAppearance(settings, mac: mac)
    }

    /// Approves a card with this front and meets it, an hour before `due`, so
    /// that it's due then, after the first step's wait. Each card is met after
    /// the ones before it, so they come due in order.
    @discardableResult
    private func meetCard(_ front: String, dueAt due: Date) throws -> Card {
        let card = try approveCard(front, in: engine)
        time.move(to: due - hours(1))
        try engine.meet(card)
        return card
    }

    /// A time of day on a day in October 2026 by the tests' calendar: the
    /// 14th, unless another day is given.
    private func at(_ hour: Int, _ minute: Int, day: Int = 14) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }
}
