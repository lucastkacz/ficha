import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the review panel while it's open: how it closes, when an
/// appearance's panel takes the keyboard, and how long Lucas takes on a card,
/// with the default settings. Left untouched for 10 minutes, the panel closes
/// on its own, and an appearance's panel takes the keyboard once Lucas has
/// been idle for 5 seconds.
struct ReviewPanelTests {
    let calendar: Calendar
    let time: ManualTimeSource
    /// The steady clock the panel times Lucas on.
    let clock = ManualClock()
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("a panel left untouched for 10 minutes closes on its own, which counts as a snooze")
    func anUntouchedPanelClosesOnItsOwn() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = engine.openPanel(.appearance, with: [.firstView(serendipia)], settings: settings)

        time.advance(by: minutes(10) - 1)
        panel.closeIfUntouched()
        #expect(panel.outcome == nil)
        time.advance(by: 1)
        panel.closeIfUntouched()

        #expect(panel.outcome == .autoClosed)
        #expect(try engine.appearanceLog().map(\.outcome) == [.autoClosed])
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == .new)
    }

    @Test("doing something in the panel keeps it open for another 10 minutes")
    func touchingThePanelKeepsItOpen() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = engine.openPanel(.appearance, with: [.firstView(serendipia)], settings: settings)

        time.advance(by: minutes(5))
        panel.touch()
        time.advance(by: minutes(10) - 1)
        panel.closeIfUntouched()
        #expect(panel.outcome == nil)
        time.advance(by: 1)
        panel.closeIfUntouched()

        #expect(panel.outcome == .autoClosed)
    }

    // So Lucas can ask for more cards, or undo the last one.
    @Test("once Lucas answered every card, the panel stays open, and closing it then finishes it")
    func thePanelStaysOpenOnceEveryCardIsAnswered() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let start = time.now
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)
        time.advance(by: 8)

        try panel.answer(.firstView, responseTime: .seconds(8))
        #expect(panel.current == nil)
        #expect(panel.outcome == nil)
        panel.close(.byLucas)

        #expect(panel.outcome == .finished)
        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(trigger: .reviewNow, shownAt: start, closedAt: start + 8, outcome: .finished)
            ]
        )
        #expect(
            try engine.standing(of: serendipia.id, on: settings.ladder) == .onLadder(step: 0, due: start + 8 + hours(1))
        )
    }

    @Test("closed with cards left, the panel is snoozed, and the cards Lucas didn't answer stay as they were")
    func closingWithCardsLeftSnoozes() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        try engine.meet(petricor)
        time.advance(by: hours(1))
        var panel = engine.openPanel(.appearance, with: [.review(ubuntu), .review(petricor)], settings: settings)

        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.close(.byLucas)

        #expect(panel.outcome == .snoozed)
        #expect(try engine.appearanceLog().map(\.outcome) == [.snoozed])
        #expect(try engine.standing(of: petricor.id, on: settings.ladder).isDue(at: time.now))
    }

    @Test("an appearance's panel takes the keyboard once Lucas has been idle for 5 seconds, and only once")
    func anAppearanceTakesTheKeyboardOnceIdle() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = engine.openPanel(.appearance, with: [.firstView(serendipia)], settings: settings)
        #expect(!panel.mayHaveKeyboard)

        let takesItBeforeFiveSeconds = panel.takesKeyboard(on: FakeMac(idleTime: .milliseconds(4_999)))
        let takesItAtFiveSeconds = panel.takesKeyboard(on: FakeMac(idleTime: .seconds(5)))
        let takesItAgain = panel.takesKeyboard(on: FakeMac(idleTime: .seconds(60)))

        #expect(!takesItBeforeFiveSeconds)
        #expect(takesItAtFiveSeconds)
        #expect(!takesItAgain)
        #expect(panel.mayHaveKeyboard)
    }

    // Without the idle time, the panel can't tell whether Lucas is typing.
    @Test("an appearance's panel doesn't take the keyboard when the Mac doesn't say how long Lucas has been idle")
    func anAppearanceWaitsForTheIdleTime() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = engine.openPanel(.appearance, with: [.firstView(serendipia)], settings: settings)

        let takesIt = panel.takesKeyboard(on: FakeMac(idleTime: nil))

        #expect(!takesIt)
        #expect(!panel.mayHaveKeyboard)
    }

    @Test("once Lucas clicks an appearance's panel, it has the keyboard and doesn't take it again on its own")
    func clickingThePanelGivesItTheKeyboard() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = engine.openPanel(.appearance, with: [.firstView(serendipia)], settings: settings)

        panel.clicked()
        let takesItOnItsOwn = panel.takesKeyboard(on: FakeMac(idleTime: .seconds(60)))

        #expect(panel.mayHaveKeyboard)
        #expect(!takesItOnItsOwn)
    }

    @Test("review now's panel has the keyboard from the start: Lucas opened it")
    func reviewNowHasTheKeyboard() throws {
        try approveCard("serendipia", in: engine)

        let panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)

        #expect(panel.mayHaveKeyboard)
    }

    @Test(
        "writing a flag's note leaves its time out of the card's response time, and cancelling it goes on from where it waited"
    )
    func writingANoteWaits() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings, clock: clock)

        clock.advance(by: .seconds(3))
        panel.startFlagging()
        panel.write(note: "Falta un ejemplo")
        clock.advance(by: .seconds(20))
        panel.cancelFlagging()
        clock.advance(by: .seconds(2))
        panel.flip()
        panel.rate(.good)

        #expect(try engine.reviewLog().last?.responseTime == .seconds(5))
    }

    // The Cards window can delete the card the panel shows.
    @Test("burying a card that was deleted meanwhile leaves the panel on it, and records that the bury failed")
    func aFailedBuryLeavesTheCard() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings, clock: clock)
        try engine.delete([serendipia.id])

        panel.buryCard()

        #expect(panel.failure?.action == .bury)
        #expect(panel.failure?.error == .cardNotFound(serendipia.id))
        #expect(panel.content == .firstView(serendipia))
        panel.dismissFailure()
        #expect(panel.failure == nil)
    }

    // The Cards window can set aside the tag of the card the panel shows, as
    // it can bury the card.
    @Test("answering a card whose tag was set aside after the panel opened fails as answering a buried one does")
    func answeringACardSetAsideMeanwhileFailsAsABuriedOneDoes() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approve(
            card(.word, front: "ubuntu", back: "Humanidad hacia los otros.", tags: ["filosofía"]), in: engine)
        var buriedPanel = engine.openPanel(.reviewNow, with: [.firstView(serendipia)], settings: settings)
        var setAsidePanel = engine.openPanel(.reviewNow, with: [.firstView(ubuntu)], settings: settings)
        try engine.bury(serendipia.id)
        try engine.setAside("filosofía")

        buriedPanel.endFirstView()
        setAsidePanel.endFirstView()

        #expect(buriedPanel.failure?.action == .answer)
        #expect(buriedPanel.failure?.error == .cardBuried(serendipia.id))
        #expect(setAsidePanel.failure?.action == .answer)
        #expect(setAsidePanel.failure?.error == .cardSetAside(ubuntu.id, tags: ["filosofía"]))
        #expect(buriedPanel.content == .firstView(serendipia))
        #expect(setAsidePanel.content == .firstView(ubuntu))
        #expect(try engine.reviewLog().isEmpty)
    }

    // Ficha Dev's debug menu moves the engine's time forward, as this test's
    // time does.
    @Test("Ficha Dev moving the time doesn't change how long Lucas took on a card")
    func movingTheTimeLeavesTheResponseTime() throws {
        try approveCard("serendipia", in: engine)
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings, clock: clock)

        clock.advance(by: .seconds(8))
        time.advance(by: hours(3))
        panel.endFirstView()

        #expect(try engine.reviewLog().map(\.responseTime) == [.seconds(8)])
    }

    // Lucas, 2026-10-15: nothing was reviewed, so there's nothing to wait
    // after.
    @Test("an empty review now isn't logged, so it doesn't hold the next appearance back")
    func anEmptyReviewNowIsNotLogged() throws {
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)
        time.advance(by: minutes(1))

        panel.close(.byLucas)

        #expect(panel.outcome == .finished)
        #expect(try engine.appearanceLog().isEmpty)
        let serendipia = try approveCard("serendipia", in: engine)
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.firstView(serendipia)]))
    }
}
