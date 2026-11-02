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
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
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

        #expect(try appearance() == .show([.new(serendipia)]))
    }

    @Test("an appearance brings along the cards due within the next 20 minutes, and not those due later")
    func bringsAlongTheCardsDueWithinTwentyMinutes() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 20))
        try meetCard("petricor", dueAt: try at(10, 21))

        time.move(to: try at(10, 0))

        #expect(try appearance() == .show([.review(ubuntu), .review(serendipia)]))
    }

    // So that a card brought along counts as if it had waited its whole
    // interval, while a review ahead, which Lucas asks for, counts how long
    // it really waited (#404).
    @Test("a card an appearance brings along before it's due is reviewed as on time, unlike one due later")
    func cardsBroughtAlongAreReviewedOnTime() throws {
        try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 20))
        let petricor = try meetCard("petricor", dueAt: try at(10, 21))
        time.move(to: try at(10, 0))

        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .appearance, settings: settings)

        #expect(
            try engine.standing(of: serendipia.id, with: settings.scheduler).stageAndDue
                == learning(step: 1, due: try at(14, 0)))
        #expect(throws: EngineError.cardNotDue(petricor.id)) {
            try engine.record(
                .review(.good), of: petricor.id, responseTime: .seconds(3), trigger: .appearance, settings: settings)
        }
    }

    // Lucas, 2026-10-15: the look-ahead is for appearances only.
    @Test("review now can't review a card before it's due, even one an appearance would bring along")
    func reviewNowDoesNotLookAhead() throws {
        try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 20))
        time.move(to: try at(10, 0))

        #expect(throws: EngineError.cardNotDue(serendipia.id)) {
            try engine.record(
                .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)
        }
    }

    @Test("the cards an appearance brings along come shortest interval first, as review now's cards do")
    func cardsBroughtAlongComeShortestIntervalFirst() throws {
        // petricor moves to the second learning step, of 4 hours, due at
        // 14:00, and ubuntu waits the first's hour, due at 14:10, so it comes
        // first.
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
        time.move(to: try at(10, 0))
        var panel = try engine.openPanel(trigger, with: [.review(serendipia)], settings: settings)
        time.move(to: try at(10, 5))
        panel.close(.byLucas)

        time.move(to: try at(10, 35) - 1)
        #expect(try appearance() == .notNow(.tooSoonAfterLastOne(until: try at(10, 35))))
        time.move(to: try at(10, 35))
        #expect(try appearance() == .show([.review(serendipia)]))
    }

    @Test("while the Mac or its screens are asleep, no appearance comes")
    func noAppearanceWhileTheMacIsAsleep() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))

        time.move(to: try at(10, 0))

        #expect(try appearance(on: FakeMac(isAsleep: true)) == .notNow(.asleep))
        #expect(try appearance(on: FakeMac(isAsleep: false)) == .show([.review(serendipia)]))
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
        arguments: [ReviewPanelState.Closing.byLucas, .onItsOwn]
    )
    func aSnoozedAppearanceLeavesItsCardsDue(closing: ReviewPanelState.Closing) throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        var panel = try openAppearance()

        time.move(to: try at(10, 10))
        panel.close(closing)

        time.move(to: try at(10, 40))
        #expect(try appearance() == .show([.review(serendipia)]))
    }

    // A new card counts once Lucas rates its first review, so a new card he
    // snoozed comes back in the next appearance.
    @Test("a snoozed new card doesn't count toward the day's 5 new cards")
    func aSnoozedNewCardDoesNotCount() throws {
        let met = try ["ubuntu", "petricor", "serendipia", "Schadenfreude"].map { try approveCard($0, in: engine) }
        let ockham = try approveCard("navaja de Ockham", in: engine)
        for card in met {
            try engine.meet(card)
        }
        var panel = try openAppearance()
        #expect(panel.cards == [.new(ockham)])

        time.move(to: try at(9, 5))
        panel.close(.byLucas)

        time.move(to: try at(9, 35))
        #expect(try appearance() == .show([.new(ockham)]))
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
        #expect(try appearance() == .show([.new(sunkCost)]))
    }

    @Test("every appearance and review now goes into the appearance log, with its trigger, times and outcome")
    func appearancesAndReviewNowsGoIntoTheAppearanceLog() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        time.move(to: try at(10, 0))
        var snoozed = try engine.openPanel(.appearance, with: [.new(serendipia)], settings: settings)
        time.move(to: try at(10, 3))
        snoozed.close(.byLucas)
        time.move(to: try at(11, 18))
        var finished = try engine.openPanel(.reviewNow, with: [.new(serendipia)], settings: settings)
        time.move(to: try at(11, 20))
        try finished.answer(.review(.again), responseTime: .seconds(90))
        finished.close(.byLucas)
        time.move(to: try at(12, 0))
        var autoClosed = try engine.openPanel(.appearance, with: [.review(serendipia)], settings: settings)
        time.move(to: try at(12, 10))
        autoClosed.closeIfUntouched()

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

    /// Opens the review panel of the appearance the engine decides on now, as
    /// the app does, and fails when there's none.
    private func openAppearance() throws -> ReviewPanelState {
        guard case .show(let cards) = try appearance() else {
            throw NoAppearanceNow()
        }
        return try engine.openPanel(.appearance, with: cards, settings: settings)
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

/// The engine decided there's no appearance, where a test expected one.
private struct NoAppearanceNow: Error {}
