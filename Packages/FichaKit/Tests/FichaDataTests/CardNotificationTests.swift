import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on answering cards from their card notifications on the iPhone (ADR
/// 0010), with the default settings: rating a card, a new one as a due one,
/// which moves its appearance on to the next card, and leaving them alone or
/// swiping them away, which snoozes it. They start at 9 in the
/// morning in Buenos Aires, when active hours start.
struct CardNotificationTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    // Nothing measures how long Lucas looked at a card notification. Good
    // moves serendipia from its first review to the second learning step's
    // 4 hours, and again puts ubuntu, a new card, on the first's hour.
    @Test(
        "a rating from a card notification, a new card's first review too, goes into the review log as an appearance's, with no response time"
    )
    func answersFromCardNotificationsGoIntoTheReviewLog() throws {
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        let ubuntu = try approveCard("ubuntu", in: engine)
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()

        time.move(to: try at(10, 1))
        _ = try engine.answerFromNotification(.review(.good), of: serendipia.id, in: appearance, settings: settings)
        time.move(to: try at(10, 2))
        _ = try engine.answerFromNotification(.review(.again), of: ubuntu.id, in: appearance, settings: settings)

        #expect(
            try engine.reviewLog().suffix(2).map(\.withoutIDs) == [
                ReviewLogEntry(
                    cardID: serendipia.id, kind: .review(.good), answeredAt: try at(10, 1), responseTime: nil,
                    trigger: .appearance, interval: .seconds(hours(4))),
                ReviewLogEntry(
                    cardID: ubuntu.id, kind: .review(.again), answeredAt: try at(10, 2), responseTime: nil,
                    trigger: .appearance, interval: .seconds(hours(1))),
            ])
    }

    // Anki's four, which the iPhone's category offers as the Mac's review
    // panel does, from `Rating.allCases` (#404): again on a card on the
    // first learning step keeps it there, hard waits halfway to the second
    // step, good moves it there, and easy graduates it.
    @Test("each of a card notification's four actions, again, hard, good and easy, answers its card")
    func eachOfACardNotificationsFourActionsAnswersItsCard() throws {
        let cards = try ["ubuntu", "serendipia", "petricor", "Schadenfreude"].map { front in
            try meetCard(front, dueAt: try at(10, 0))
        }
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()

        time.move(to: try at(10, 1))
        for (card, rating) in zip(cards, Rating.allCases) {
            _ = try engine.answerFromNotification(.review(rating), of: card.id, in: appearance, settings: settings)
        }

        #expect(
            try cards.map { try engine.standing(of: $0.id, with: settings.scheduler).stageAndDue?.stage } == [
                .learning(step: 0), .learning(step: 0), .learning(step: 1), .graduated,
            ])
        #expect(
            try cards.map { try engine.standing(of: $0.id, with: settings.scheduler).interval }.prefix(3) == [
                .seconds(hours(1)), .seconds(minutes(150)), .seconds(hours(4)),
            ])
    }

    @Test("the next card of an appearance is its next one still due, skipping one Lucas rated or buried meanwhile")
    func theNextCardSkipsOnesRatedOrBuriedMeanwhile() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        let petricor = try meetCard("petricor", dueAt: try at(10, 0))
        let schadenfreude = try meetCard("Schadenfreude", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()
        // In the app, before he answers the first card notification.
        try engine.review(serendipia, .good)
        try engine.bury(petricor.id)

        time.move(to: try at(10, 2))
        let next = try engine.answerFromNotification(.review(.hard), of: ubuntu.id, in: appearance, settings: settings)

        #expect(next == .review(schadenfreude))
    }

    @Test("a card notification's next card is never a flagged or a buried one")
    func theNextCardIsNeverFlaggedOrBuried() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        let petricor = try meetCard("petricor", dueAt: try at(10, 0))
        let schadenfreude = try meetCard("Schadenfreude", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()
        // In the app, before he answers the first card notification.
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))
        try engine.bury(petricor.id)

        time.move(to: try at(10, 2))
        let next = try engine.answerFromNotification(.review(.hard), of: ubuntu.id, in: appearance, settings: settings)
        let last = try engine.answerFromNotification(
            .review(.good), of: schadenfreude.id, in: appearance, settings: settings)

        #expect(next == .review(schadenfreude))
        #expect(last == nil)
    }

    // A card notification carries its card with its appearance, so only a
    // mistake could mix them up, and it would log a card that never showed.
    @Test("an answer to a card its appearance didn't bring is refused, and neither log changes")
    func anAnswerToACardFromAnotherAppearanceIsRefused() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        let appearance = NotifiedAppearance(shownAt: try at(10, 0), cardIDs: [ubuntu.id])
        let reviewLog = try engine.reviewLog()

        time.move(to: try at(10, 1))
        #expect(throws: EngineError.cardNotInAppearance(serendipia.id)) {
            try engine.answerFromNotification(.review(.good), of: serendipia.id, in: appearance, settings: settings)
        }

        #expect(try engine.reviewLog() == reviewLog)
        #expect(try engine.appearanceLog().isEmpty)
    }

    // Left partway, an appearance is a snooze, as on the Mac (#97).
    @Test(
        "an appearance goes into the appearance log from the time it showed, as a snooze until its last card's answer finishes it"
    )
    func answeringTheLastCardFinishesTheAppearance() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()

        time.move(to: try at(10, 1))
        _ = try engine.answerFromNotification(.review(.good), of: ubuntu.id, in: appearance, settings: settings)
        let partway = try engine.appearanceLog()
        time.move(to: try at(10, 3))
        let next = try engine.answerFromNotification(
            .review(.again), of: serendipia.id, in: appearance, settings: settings)

        #expect(
            partway == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(10, 0), closedAt: try at(10, 1), outcome: .snoozed)
            ])
        #expect(next == nil)
        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(10, 0), closedAt: try at(10, 3), outcome: .finished)
            ])
    }

    // Otherwise, the app would plan the cards left as an appearance right
    // away, with its sound, over the next card's notification.
    @Test(
        "while Lucas goes through an appearance's card notifications, the next appearance waits 30 minutes from his last answer"
    )
    func theNextAppearanceWaitsFromTheLastAnswer() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()

        time.move(to: try at(10, 5))
        _ = try engine.answerFromNotification(.review(.good), of: ubuntu.id, in: appearance, settings: settings)

        #expect(
            try engine.upcomingAppearances(settings).first
                == UpcomingAppearance(time: try at(10, 35), cards: [.review(serendipia)]))
    }

    // A card notification Lucas leaves alone is a snooze, as on the Mac
    // (#97). Only the last plan counts: the one it replaced never came.
    @Test(
        "planned appearances whose time came and that Lucas never touched go into the appearance log as snoozes, closed as they showed, the next time the engine plans"
    )
    func untouchedAppearancesAreSnoozes() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        try meetCard("serendipia", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()

        time.move(to: try at(10, 1))
        _ = try engine.answerFromNotification(.review(.good), of: ubuntu.id, in: appearance, settings: settings)
        // As the app does after each answer, which plans one at 10:31.
        _ = try engine.upcomingAppearances(settings)
        time.move(to: try at(11, 15))
        _ = try engine.upcomingAppearances(settings)

        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(10, 0), closedAt: try at(10, 1), outcome: .snoozed),
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(10, 31), closedAt: try at(10, 31), outcome: .snoozed),
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(11, 1), closedAt: try at(11, 1), outcome: .snoozed),
            ])
    }

    // Swiping a card notification away is a plain "not now" (#97).
    @Test(
        "swiping a card notification away snoozes its appearance, closed then, and its cards come back 30 minutes later"
    )
    func swipingACardNotificationAwayIsASnooze() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()

        time.move(to: try at(10, 5))
        try engine.snoozeFromNotification(appearance)
        // As the app does after the swipe.
        let next = try engine.upcomingAppearances(settings).first

        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(
                    trigger: .appearance, shownAt: try at(10, 0), closedAt: try at(10, 5), outcome: .snoozed)
            ])
        #expect(next == UpcomingAppearance(time: try at(10, 35), cards: [.review(ubuntu)]))
    }

    // A next card's notification stays on the lock screen while later
    // appearances come, and its answer counts for its own appearance, whose
    // entry is older than theirs.
    @Test(
        "an answer from an appearance's next card, after a later one came untouched, makes the next wait 30 minutes from the answer"
    )
    func theNextAppearanceWaitsFromTheLatestClosing() throws {
        let ubuntu = try meetCard("ubuntu", dueAt: try at(10, 0))
        let serendipia = try meetCard("serendipia", dueAt: try at(10, 0))
        let petricor = try meetCard("petricor", dueAt: try at(10, 45))
        time.move(to: try at(10, 0))
        let appearance = try nextAppearance()
        time.move(to: try at(10, 1))
        _ = try engine.answerFromNotification(.review(.good), of: ubuntu.id, in: appearance, settings: settings)
        // As the app does after each answer, which plans one at 10:31.
        _ = try engine.upcomingAppearances(settings)

        time.move(to: try at(10, 40))
        _ = try engine.answerFromNotification(.review(.good), of: serendipia.id, in: appearance, settings: settings)
        let next = try engine.upcomingAppearances(settings).first

        #expect(next == UpcomingAppearance(time: try at(11, 10), cards: [.review(petricor)]))
    }

    /// The next appearance the engine plans, as its card notifications carry
    /// it.
    private func nextAppearance() throws -> NotifiedAppearance {
        NotifiedAppearance(try #require(try engine.upcomingAppearances(settings).first))
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

    /// A time of day on October 14, 2026, by the tests' calendar.
    private func at(_ hour: Int, _ minute: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute)))
    }
}
