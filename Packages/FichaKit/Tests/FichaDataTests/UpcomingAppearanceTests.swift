import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the appearances the engine plans ahead for the iPhone, which
/// schedules them as card notifications (ADR 0010), with the default
/// settings. They start at 9 in the morning in Buenos Aires, when active hours
/// start.
struct UpcomingAppearanceTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("with no cards, no appearance is planned")
    func noCardsPlanNothing() throws {
        #expect(try engine.upcomingAppearances(settings).isEmpty)
    }

    @Test("a due card plans an appearance right away within active hours, and at their next start outside them")
    func aDueCardPlansAnAppearanceWithinActiveHours() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))

        time.move(to: try at(10, 0))
        let withinActiveHours = try engine.upcomingAppearances(settings).first
        time.move(to: try at(22, 0))
        let afterThem = try engine.upcomingAppearances(settings).first

        #expect(withinActiveHours == UpcomingAppearance(time: try at(10, 0), cards: [.review(serendipia)]))
        #expect(afterThem == UpcomingAppearance(time: try at(9, 0, day: 15), cards: [.review(serendipia)]))
    }

    // A card notification Lucas leaves alone closes, for separation, as it
    // shows (#97), and nothing he rates in between changes the plan.
    @Test("planned appearances keep 30 minutes from the last one that closed, and from each other, within active hours")
    func plannedAppearancesKeepTheSeparation() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(20, 30))
        time.move(to: try at(20, 55))
        var reviewNow = engine.openPanel(.reviewNow, with: [.review(serendipia)], settings: settings)
        time.move(to: try at(21, 0))
        reviewNow.close(.byLucas)

        let times = try engine.upcomingAppearances(settings).prefix(3).map(\.time)

        #expect(times == [try at(21, 30), try at(9, 0, day: 15), try at(9, 30, day: 15)])
    }

    // Otherwise, the app would plan the cards left alone as an appearance
    // right away.
    @Test("an appearance Lucas never touched makes the next one wait 30 minutes from when it showed")
    func theNextAppearanceWaitsFromAnUntouchedOne() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        _ = try engine.upcomingAppearances(settings)

        time.move(to: try at(10, 20))
        let next = try engine.upcomingAppearances(settings).first

        #expect(next == UpcomingAppearance(time: try at(10, 30), cards: [.review(serendipia)]))
    }

    // Ficha Dev's "Bring the next appearance now" (#101).
    @Test("a first appearance brought forward is planned then, and once it comes untouched, it's a snooze from then")
    func aFirstAppearanceBroughtForwardStaysThere() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(12, 0))
        time.move(to: try at(10, 0))
        let broughtForward = try engine.upcomingAppearances(settings, bringingTheFirstTo: try at(10, 1)).first

        time.move(to: try at(10, 10))
        _ = try engine.upcomingAppearances(settings)

        #expect(broughtForward == UpcomingAppearance(time: try at(10, 1), cards: [.review(serendipia)]))
        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(10, 1), closedAt: try at(10, 1), outcome: .snoozed)
            ])
    }

    @Test("each planned appearance comes once a card is due, with at most 5, along with those due within 20 minutes")
    func eachAppearanceBringsTheCardsDueWithinTheLookAhead() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 20))
        let petricor = try meetCard("petricor", dueAt: try at(10, 21))
        let schadenfreude = try meetCard("Schadenfreude", dueAt: try at(10, 40))
        let ockham = try meetCard("navaja de Ockham", dueAt: try at(10, 40))
        try meetCard("costo hundido", dueAt: try at(10, 40))

        let firstTwo = try engine.upcomingAppearances(settings).prefix(2)

        #expect(
            Array(firstTwo) == [
                UpcomingAppearance(time: try at(10, 0), cards: [.review(ubuntu), .review(serendipia)]),
                UpcomingAppearance(
                    time: try at(10, 30),
                    cards: [
                        .review(ubuntu), .review(serendipia), .review(petricor), .review(schadenfreude),
                        .review(ockham),
                    ]),
            ])
    }

    @Test("once Lucas met the day's 5 new cards, the next one is planned for the next day's active hours")
    func theNextNewCardWaitsForTheNextDay() throws {
        let met = try ["ubuntu", "petricor", "serendipia", "Schadenfreude", "navaja de Ockham"].map {
            try approveCard($0, in: engine)
        }
        let sunkCost = try approveCard("costo hundido", in: engine)
        // Met at 9:00 and good twice, they're due again on the 16th.
        for card in met {
            try engine.meet(card)
        }
        for review in [try at(10, 0), try at(14, 0)] {
            time.move(to: review)
            for card in met {
                try engine.review(card, .good)
            }
        }

        let next = try engine.upcomingAppearances(settings).first

        #expect(next == UpcomingAppearance(time: try at(9, 0, day: 15), cards: [.firstView(sunkCost)]))
    }

    // iOS keeps at most 64 notifications pending for an app (#97).
    @Test("the plan stops one short of the 64 notifications iOS keeps pending")
    func thePlanStopsShortOfTheCap() throws {
        try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))

        #expect(try engine.upcomingAppearances(settings).count == 63)
    }

    @Test("rating a card plans its next appearance for when it's due again")
    func ratingACardChangesThePlan() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        let before = try engine.upcomingAppearances(settings).first

        try engine.review(serendipia, .good)
        let after = try engine.upcomingAppearances(settings).first

        #expect(before == UpcomingAppearance(time: try at(10, 0), cards: [.review(serendipia)]))
        #expect(after == UpcomingAppearance(time: try at(14, 0), cards: [.review(serendipia)]))
    }

    @Test("planned appearances leave out a flagged card and a buried card that are due")
    func plannedAppearancesLeaveOutFlaggedAndBuriedCards() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let petricor = try meetCard("petricor", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        try engine.flag(petricor.id, note: note("Falta decir de dónde viene"))
        try engine.bury(serendipia.id)
        time.move(to: try at(10, 0))

        let plan = try engine.upcomingAppearances(settings)

        #expect(plan.first?.time == (try at(10, 0)))
        #expect(plan.map(\.cards) == Array(repeating: [.review(ubuntu)], count: Engine.mostUpcomingAppearances))
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
