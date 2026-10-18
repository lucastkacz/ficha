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
        "no appearance shows up during a meeting, a video or a full-screen app",
        arguments: [Suppression.meeting, .video, .fullScreen])
    func aSuppressionHoldsAppearancesBack(suppression: Suppression) throws {
        let decision = try engine.checkAppearance(settings, mac: FakeMac(suppressions: [suppression]))

        #expect(decision == .notNow(.suppressed(suppression)))
    }

    @Test("a held-back appearance comes 2 minutes after the suppression ends")
    func comesTwoMinutesAfterTheSuppressionEnds() throws {
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac(suppressions: [.meeting]))
                == .notNow(.suppressed(.meeting)))
        time.advance(by: minutes(40))
        let ended = time.now
        let afterTheMeeting = FakeMac(lastSuppressionEnd: ended)

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
        var panel = try openAppearance(on: FakeMac(lastSuppressionEnd: ended))
        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.close(.byLucas)
        let closedAt = time.now
        time.advance(by: hours(4))
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac(suppressions: [.fullScreen], lastSuppressionEnd: ended))
                == .notNow(.suppressed(.fullScreen)))

        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: heldBackAt, closedAt: heldBackAt, outcome: .heldBack(.meeting)),
                AppearanceLogEntry(trigger: .appearance, shownAt: closedAt, closedAt: closedAt, outcome: .finished),
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

    /// Opens the review panel of the appearance the engine decides on now, on
    /// `mac`, as the app does.
    private func openAppearance(on mac: FakeMac) throws -> ReviewPanelState {
        guard case .show(let cards) = try engine.checkAppearance(settings, mac: mac) else {
            Issue.record("There was no appearance")
            return engine.openPanel(.appearance, with: [], settings: settings)
        }
        return engine.openPanel(.appearance, with: cards, settings: settings)
    }
}
