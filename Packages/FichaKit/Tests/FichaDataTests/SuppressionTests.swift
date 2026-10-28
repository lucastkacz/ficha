import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on appearances held back by a suppression, with the default settings:
/// an appearance waits 2 minutes after the suppression ends. They start at 9
/// in the morning in Buenos Aires, when active hours start, with a card due.
struct SuppressionTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults
    let serendipia: Card

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        time.advance(by: hours(1))
    }

    @Test(
        "no appearance shows up during a meeting, a video, a full-screen app or a Focus that holds appearances back",
        arguments: [Suppression.meeting, .video, .fullScreen, .focus])
    func aSuppressionHoldsAppearancesBack(suppression: Suppression) throws {
        let decision = try engine.checkAppearance(settings, mac: FakeMac(suppressions: [suppression]))

        #expect(decision == .notNow(.suppressed(suppression)))
    }

    // Its switch is Ficha's filter, in System Settings, not Ficha's Settings.
    @Test("a Focus holds appearances back, and makes them wait once it ends, with every suppression off in Settings")
    func aFocusAppliesWhateverTheSettings() throws {
        var settings = settings
        settings.suppressionsThatApply = []
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac(suppressions: [.focus, .meeting]))
                == .notNow(.suppressed(.focus)))
        time.advance(by: minutes(40))
        let ended = time.now

        time.advance(by: minutes(1))
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac(suppressionEnds: [.focus: ended]))
                == .notNow(.tooSoonAfterSuppression(until: ended + minutes(2))))
        time.advance(by: minutes(1))
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac(suppressionEnds: [.focus: ended]))
                == .show([.review(serendipia)]))
    }

    @Test("a held-back appearance comes 2 minutes after the suppression ends")
    func comesTwoMinutesAfterTheSuppressionEnds() throws {
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac(suppressions: [.meeting]))
                == .notNow(.suppressed(.meeting)))
        time.advance(by: minutes(40))
        let ended = time.now
        let afterTheMeeting = FakeMac(suppressionEnds: [.meeting: ended])

        time.advance(by: minutes(2) - 1)
        #expect(
            try engine.checkAppearance(settings, mac: afterTheMeeting)
                == .notNow(.tooSoonAfterSuppression(until: ended + minutes(2))))
        time.advance(by: 1)
        #expect(try engine.checkAppearance(settings, mac: afterTheMeeting) == .show([.review(serendipia)]))
    }

    // Checked every minute, it's still the same appearance until it shows up.
    @Test("the appearance log records the suppression that held an appearance back once, and not as a closing")
    func theLogRecordsEachHeldBackAppearanceOnce() throws {
        let heldBackAt = time.now
        for suppression in [Suppression.meeting, .meeting, .video] {
            #expect(
                try engine.checkAppearance(settings, mac: FakeMac(suppressions: [suppression]))
                    == .notNow(.suppressed(suppression)))
            time.advance(by: minutes(1))
        }
        // The video ended two minutes later: the separation doesn't wait from
        // when the appearance was held back.
        let ended = time.now
        time.advance(by: minutes(2))
        let shownAt = time.now
        var panel = try openAppearance(on: FakeMac(suppressionEnds: [.video: ended]))
        try panel.answer(.review(.good), responseTime: .seconds(3))
        time.advance(by: 4)
        panel.close(.byLucas)
        let closedAt = time.now
        time.advance(by: hours(4))
        #expect(
            try engine.checkAppearance(
                settings, mac: FakeMac(suppressions: [.fullScreen], suppressionEnds: [.video: ended]))
                == .notNow(.suppressed(.fullScreen)))

        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: heldBackAt, closedAt: shownAt, outcome: .heldBack(.meeting)),
                AppearanceLogEntry(trigger: .appearance, shownAt: shownAt, closedAt: closedAt, outcome: .finished),
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: time.now, closedAt: time.now, outcome: .heldBack(.fullScreen)),
            ]
        )
    }

    @Test("nothing is held back, or recorded, while no card is due")
    func nothingDueIsNotHeldBack() throws {
        var panel = try openAppearance(on: FakeMac())
        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.close(.byLucas)
        time.advance(by: minutes(30))

        let decision = try engine.checkAppearance(settings, mac: FakeMac(suppressions: [.meeting]))

        #expect(decision == .notNow(.nothingDue))
        #expect(try engine.appearanceLog().map(\.outcome) == [.finished])
    }

    // At 22:00 active hours end, so the appearance won't come today.
    @Test("an appearance that stops being held back without showing up ends its entry, and the next one gets its own")
    func aHoldThatEndsWithoutAnAppearanceIsClosed() throws {
        let heldBackAt = try at(21, 55)
        time.move(to: heldBackAt)
        #expect(try appearance(on: FakeMac(suppressions: [.video])) == .notNow(.suppressed(.video)))
        let hoursEnd = try at(22, 0)
        time.move(to: hoursEnd)
        #expect(try appearance(on: FakeMac(suppressions: [.video])) == .notNow(.outsideActiveHours))
        let nextMorning = try at(9, 0, day: 15)
        time.move(to: nextMorning)

        #expect(try appearance(on: FakeMac(suppressions: [.meeting])) == .notNow(.suppressed(.meeting)))

        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: heldBackAt, closedAt: hoursEnd, outcome: .heldBack(.video)),
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: nextMorning, closedAt: nextMorning, outcome: .heldBack(.meeting)),
            ]
        )
    }

    // A Focus, unlike the others, has its switch outside Ficha's Settings.
    @Test(
        "a review now during a hold brings the cards due, and ends the hold as the review panel shows",
        arguments: [Suppression.meeting, .focus])
    func aReviewNowEndsAHold(suppression: Suppression) throws {
        let heldBackAt = time.now
        #expect(try appearance(on: FakeMac(suppressions: [suppression])) == .notNow(.suppressed(suppression)))
        time.advance(by: minutes(5))
        let reviewNowAt = time.now
        let cards = try engine.reviewNow(settings)
        #expect(cards == [.review(serendipia)])
        var panel = try engine.openPanel(.reviewNow, with: cards, settings: settings)
        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.close(.byLucas)

        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: heldBackAt, closedAt: reviewNowAt, outcome: .heldBack(suppression)),
                AppearanceLogEntry(
                    trigger: .reviewNow, shownAt: reviewNowAt, closedAt: reviewNowAt, outcome: .finished),
            ]
        )
    }

    /// What the engine decides now about an appearance, on `mac`.
    private func appearance(on mac: FakeMac) throws -> AppearanceDecision {
        try engine.checkAppearance(settings, mac: mac)
    }

    /// Opens the review panel of the appearance the engine decides on now, on
    /// `mac`, as the app does, and fails when there's none.
    private func openAppearance(on mac: FakeMac) throws -> ReviewPanelState {
        guard case .show(let cards) = try appearance(on: mac) else {
            throw NoAppearanceNow()
        }
        return try engine.openPanel(.appearance, with: cards, settings: settings)
    }

    /// A time of day on a day in October 2026 by the tests' calendar: the
    /// 14th, unless another day is given.
    private func at(_ hour: Int, _ minute: Int, day: Int = 14) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }
}

/// The engine decided there's no appearance, where a test expected one.
private struct NoAppearanceNow: Error {}
