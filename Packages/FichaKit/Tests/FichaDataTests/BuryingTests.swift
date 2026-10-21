import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on burying cards, which takes them out of Lucas's reviews for good
/// without deleting them, one in the review panel or several at once in the
/// Cards window, and on unburying them, there or in a refine session.
struct BuryingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("a card buried in the review panel never shows up again, counts nowhere, and keeps its review log")
    func aBuriedCardNeverShowsUpAgain() throws {
        // serendipia gets to the 30-day step, from which a card is learned,
        // and comes due there.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 5, movingForward: time)
        time.advance(by: days(30))
        let log = try engine.reviewLog()
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)

        try panel.bury()

        #expect(try engine.cards().map(\.buriedAt) == [time.now])
        time.advance(by: days(365))
        #expect(try engine.reviewNow(settings).isEmpty)
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
        let progress = try engine.progress(settings)
        #expect(progress.due == 0)
        #expect(progress.learned == 0)
        #expect(progress.inInbox == 0)
        #expect(try engine.reviewLog() == log)
    }

    @Test("an unburied card goes back to its step in Lucas's reviews, and counts again")
    func anUnburiedCardGoesBackToItsStep() throws {
        // serendipia gets to the 30-day step, from which a card is learned.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 5, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, on: settings.ladder)
        try engine.bury(serendipia.id)
        time.advance(by: days(30))

        let unburied = try engine.unbury(serendipia.id)

        #expect(unburied.buriedAt == nil)
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == standing)
        #expect(try engine.reviewNow(settings) == [.review(unburied)])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
    }

    // A refine session can bury a flagged card instead of fixing it, and
    // burying is never a loss (#4).
    @Test("burying a flagged card takes it out of the inbox, and unburying puts it back there with its note")
    func anUnburiedFlaggedCardGoesBackToTheInbox() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))

        try engine.bury(serendipia.id)
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.progress(settings).inInbox == 0)

        try engine.unbury(serendipia.id)
        #expect(try engine.inbox().flaggedCards.map(\.flag?.note) == ["Falta decir de dónde viene"])
        #expect(try engine.reviewNow(settings).isEmpty)
    }

    // A refine session can repeat a command, and a buried card keeps when it
    // was buried.
    @Test("a buried card can't be buried again, and only a buried card can be unburied")
    func onlyABuriedCardCanBeUnburied() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let buried = try engine.bury(serendipia.id)
        time.advance(by: hours(1))

        #expect(throws: EngineError.cardBuried(serendipia.id)) {
            try engine.bury(serendipia.id)
        }
        #expect(throws: EngineError.cardNotBuried(ubuntu.id)) {
            try engine.unbury(ubuntu.id)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.bury(99)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.unbury(99)
        }
        #expect(try engine.cards() == [buried, ubuntu])
    }

    // The Cards window buries the cards Lucas selected, at once.
    @Test("burying several cards takes each out of Lucas's reviews, or out of the inbox when it's flagged")
    func buryingSeveralCardsTakesThemAllOut() throws {
        // serendipia and ojalá come due on the first step, and ubuntu is
        // flagged.
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.meet(serendipia)
        try engine.meet(ojala)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        time.advance(by: hours(1))

        let buried = try engine.bury([serendipia.id, ubuntu.id])

        #expect(buried.map(\.front) == ["serendipia", "ubuntu"])
        #expect(try engine.cards().map(\.buriedAt) == [time.now, time.now, nil])
        #expect(try engine.reviewNow(settings).map(\.card.id) == [ojala.id])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.inInbox == 0)
    }

    // The Cards window offers Bury only when no selected card is buried, but
    // a refine session can bury one of them meanwhile.
    @Test("burying several cards buries none of them when one is already buried, or doesn't exist")
    func buryingSeveralCardsIsAllOrNothing() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let buried = try engine.bury(ubuntu.id)
        time.advance(by: hours(1))

        #expect(throws: EngineError.cardBuried(ubuntu.id)) {
            try engine.bury([serendipia.id, ubuntu.id])
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.bury([serendipia.id, 99])
        }
        #expect(try engine.cards() == [serendipia, buried])
    }

    @Test("unburying several cards puts each back where it was: in Lucas's reviews on its step, or in the inbox")
    func unburyingSeveralCardsPutsEachBack() throws {
        // serendipia gets to the 30-day step, from which a card is learned,
        // and ubuntu is flagged.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 5, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, on: settings.ladder)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.bury([serendipia.id, ubuntu.id])
        time.advance(by: days(30))

        let unburied = try engine.unbury([serendipia.id, ubuntu.id])

        #expect(unburied.map(\.buriedAt) == [nil, nil])
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == standing)
        #expect(try engine.reviewNow(settings).map(\.card.id) == [serendipia.id])
        #expect(try engine.inbox().flaggedCards.map(\.flag?.note) == ["Falta un ejemplo"])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
        #expect(progress.inInbox == 1)
    }

    // The Cards window offers Unbury only when every selected card is buried,
    // but a refine session can unbury one of them meanwhile.
    @Test("unburying several cards unburies none of them when one isn't buried, or doesn't exist")
    func unburyingSeveralCardsIsAllOrNothing() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let buried = try engine.bury(serendipia.id)

        #expect(throws: EngineError.cardNotBuried(ubuntu.id)) {
            try engine.unbury([serendipia.id, ubuntu.id])
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.unbury([serendipia.id, 99])
        }
        #expect(try engine.cards() == [buried, ubuntu])
    }
}
