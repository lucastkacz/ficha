import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the settings Lucas changes reaching the engine's decisions: each
/// one changes defaults and checks what he would see. They start at 9 in the
/// morning in Buenos Aires, when active hours start by default.
struct SettingsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    // The review log is the source of truth (ADR 0002), so a new ladder
    // applies to every card at once, without losing its progress.
    @Test("a changed ladder re-times every card from its history")
    func aChangedLadderReTimesTheCards() throws {
        var settings = ReviewSettings.defaults
        settings.ladder = try #require(Ladder(waits: [.seconds(minutes(30)), .seconds(hours(3)), .seconds(days(1))]))
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        let reviewedAt = time.now

        time.move(to: reviewedAt + days(1))

        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == .onLadder(step: 2, due: time.now))
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.review(serendipia)]))
        #expect(try engine.progress(settings).due == 1)
    }

    @Test("after the ladder is shortened, a card beyond its end sits on its last step")
    func aShortenedLadderKeepsTheCardOnItsLastStep() throws {
        var settings = ReviewSettings.defaults
        settings.ladder = try #require(Ladder(waits: [.seconds(hours(1)), .seconds(days(1)), .seconds(days(3))]))
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 5, movingForward: time)
        #expect(try engine.progress(.defaults).learned == 1)
        let reviewedAt = time.now

        time.move(to: reviewedAt + days(3))

        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == .onLadder(step: 2, due: time.now))
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.review(serendipia)]))
        #expect(try engine.progress(settings).learned == 0)
    }

    @Test("a suppression Lucas turned off neither holds appearances back nor makes them wait once it ends")
    func aSuppressionTurnedOffDoesNotApply() throws {
        var settings = ReviewSettings.defaults
        settings.suppressionsThatApply = [.meeting, .fullScreen]
        let serendipia = try approveCard("serendipia", in: engine)

        let duringAVideo = try engine.checkAppearance(settings, mac: FakeMac(suppressions: [.video]))
        let afterAVideo = try engine.checkAppearance(settings, mac: FakeMac(suppressionEnds: [.video: time.now]))
        let duringAVideoInFullScreen = try engine.checkAppearance(
            settings, mac: FakeMac(suppressions: [.video, .fullScreen]))

        #expect(duringAVideo == .show([.firstView(serendipia)]))
        #expect(afterAVideo == .show([.firstView(serendipia)]))
        #expect(duringAVideoInFullScreen == .notNow(.suppressed(.fullScreen)))
    }

    @Test("an appearance brings at most as many cards as the settings say, a new one included")
    func anAppearanceBringsTheSettingsCards() throws {
        var settings = ReviewSettings.defaults
        settings.cardsPerAppearance = 2
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        try approveCard("petricor", in: engine)

        time.move(to: try at(10, 0))

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.review(ubuntu), .review(serendipia)]))
    }

    @Test("an appearance brings along the cards due within the settings' look-ahead, and not those due later")
    func anAppearanceLooksAsFarAheadAsTheSettingsSay() throws {
        var settings = ReviewSettings.defaults
        settings.lookAhead = .seconds(minutes(5))
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 5))
        try meetCard("petricor", dueAt: try at(10, 6))

        time.move(to: try at(10, 0))

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.review(ubuntu), .review(serendipia)]))
    }

    @Test("Lucas meets as many new cards a day as the settings say")
    func newCardsPerDayComeFromTheSettings() throws {
        var settings = ReviewSettings.defaults
        settings.newCardsPerDay = 1
        try engine.meet(try approveCard("ubuntu", in: engine))
        try approveCard("petricor", in: engine)

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
        #expect(try engine.reviewNow(settings) == [])
    }

    @Test("a back-first first view counts toward the settings' new cards a day, as a new card's does")
    func backFirstFirstViewsCountTowardNewCardsPerDay() throws {
        var settings = ReviewSettings.defaults
        settings.newCardsPerDay = 2
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("ubuntu", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)

        try engine.meet(bothWays[0], way: .backFirst)

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
        #expect(try engine.reviewNow(settings) == [])
    }

    @Test("appearances happen within the settings' active hours, as far apart as their separation says")
    func activeHoursAndTheSeparationComeFromTheSettings() throws {
        var settings = ReviewSettings.defaults
        settings.activeHours = 10..<23
        settings.separation = .seconds(minutes(10))
        let serendipia = try approveCard("serendipia", in: engine)

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.outsideActiveHours))
        time.move(to: try at(22, 0))
        var panel = try engine.openPanel(.appearance, with: [.firstView(serendipia)], settings: settings)
        panel.close(.byLucas)
        time.advance(by: minutes(10) - 1)
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac())
                == .notNow(.tooSoonAfterLastOne(until: try at(22, 10))))
        time.advance(by: 1)
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.firstView(serendipia)]))
    }

    @Test("an appearance waits as long after a suppression ends, or the Mac wakes, as the settings say")
    func theWaitsAfterASuppressionAndWakingComeFromTheSettings() throws {
        var settings = ReviewSettings.defaults
        settings.waitAfterSuppression = .seconds(minutes(5))
        settings.waitAfterWaking = .seconds(minutes(10))
        let serendipia = try approveCard("serendipia", in: engine)
        let afterTheMeeting = FakeMac(suppressionEnds: [.meeting: time.now])
        let afterWaking = FakeMac(lastWake: time.now)

        time.advance(by: minutes(5) - 1)
        #expect(
            try engine.checkAppearance(settings, mac: afterTheMeeting)
                == .notNow(.tooSoonAfterSuppression(until: try at(9, 5))))
        time.advance(by: 1)
        #expect(try engine.checkAppearance(settings, mac: afterTheMeeting) == .show([.firstView(serendipia)]))
        #expect(
            try engine.checkAppearance(settings, mac: afterWaking) == .notNow(.tooSoonAfterWaking(until: try at(9, 10)))
        )
    }

    @Test("an appearance's panel closes on its own, and takes the keyboard, as the settings say")
    func autoCloseAndTheFocusModeComeFromTheSettings() throws {
        var settings = ReviewSettings.defaults
        settings.autoClose = .seconds(minutes(3))
        settings.focusMode = .always
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.appearance, with: [.firstView(serendipia)], settings: settings)

        let takesItWhileLucasTypes = panel.takesKeyboard(on: FakeMac(idleTime: .zero))
        time.advance(by: minutes(3))
        panel.closeIfUntouched()

        #expect(takesItWhileLucasTypes)
        #expect(panel.outcome == .autoClosed)
    }

    @Test("in the once-idle focus mode, an appearance's panel takes the keyboard after the settings' idle time")
    func theIdleTimeComesFromTheSettings() throws {
        var settings = ReviewSettings.defaults
        settings.idleBeforeTakingKeyboard = .seconds(2)
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.appearance, with: [.firstView(serendipia)], settings: settings)

        let takesItAfterASecond = panel.takesKeyboard(on: FakeMac(idleTime: .seconds(1)))
        let takesItAfterTwoSeconds = panel.takesKeyboard(on: FakeMac(idleTime: .seconds(2)))

        #expect(!takesItAfterASecond)
        #expect(takesItAfterTwoSeconds)
    }

    @Test(
        "a card is forgotten often after as many “Don't know” as the settings say, and again every half of that, rounded down"
    )
    func forgottenOftenComesFromTheSettings() throws {
        var settings = ReviewSettings.defaults
        settings.forgottenOftenAfter = 5
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)

        let saidSo = try (1...10).map { _ in try forget(ubuntu, with: settings)?.times }

        #expect(saidSo == [nil, nil, nil, nil, 5, nil, 7, nil, 9, nil])
    }

    @Test("with the offer turned off, no card is ever forgotten often")
    func forgottenOftenCanBeTurnedOff() throws {
        var settings = ReviewSettings.defaults
        settings.forgottenOftenAfter = nil
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)

        let saidSo = try (1...16).map { _ in try forget(ubuntu, with: settings) }

        #expect(saidSo.allSatisfy { $0 == nil })
    }

    /// Moves the time forward until `card` is due, rates it again with
    /// `settings`, as the review panel does, and returns whether it's now
    /// forgotten often.
    private func forget(_ card: Card, with settings: ReviewSettings) throws -> ForgottenOften? {
        time.move(to: try #require(try engine.standing(of: card.id, on: settings.ladder).due))
        return try engine.record(
            .review(.again), of: card.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)
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

    /// A time of day on the 14th of October 2026, by the tests' calendar.
    private func at(_ hour: Int, _ minute: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute)))
    }
}
