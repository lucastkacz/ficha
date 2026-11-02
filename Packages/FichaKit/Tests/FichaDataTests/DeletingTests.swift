import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on deleting cards in the Cards window, one or several at once: they
/// leave Ficha for good with their review logs, which burying keeps, and
/// nothing Lucas jotted down about them is lost.
struct DeletingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    @Test("deleting cards takes them out of Ficha with their review logs, and leaves the other cards as they were")
    func deletingTakesTheCardsAndTheirReviewLogs() throws {
        // serendipia and ojalá have their first reviews, and ubuntu is buried.
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.meet(serendipia)
        try engine.meet(ojala)
        try engine.bury(ubuntu.id)
        let standing = try engine.standing(of: ojala.id, with: settings.scheduler)
        time.advance(by: hours(1))

        let deleted = try engine.delete([serendipia.id, ubuntu.id])

        #expect(deleted.map(\.front) == ["serendipia", "ubuntu"])
        #expect(try engine.cards() == [ojala])
        #expect(try engine.reviewLog().map(\.cardID) == [ojala.id])
        #expect(try engine.standing(of: ojala.id, with: settings.scheduler) == standing)
        #expect(throws: EngineError.cardNotFound(serendipia.id)) {
            try engine.standing(of: serendipia.id, with: settings.scheduler)
        }
        #expect(try engine.reviewNow(settings) == [.review(ojala)])
    }

    // The capture serendipia was approved from, and its expansion approved
    // into it, were refined already, so they stay out of the inbox.
    @Test("deleting a card leaves its expansion in the inbox as a plain capture, and what was refined out of it")
    func anExpansionOfADeletedCardBecomesACapture() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let approved = try engine.expand(text: "Serendipia", note: "También es una película", source: nil)
        try engine.approveExpansion(
            approved.id, into: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad."))
        let waiting = try engine.expand(text: "serendipia", note: "Viene de un cuento persa", source: "Un podcast")

        try engine.delete([serendipia.id])

        let inbox = try engine.inbox()
        #expect(inbox.expansions.isEmpty)
        #expect(inbox.captures.map(\.id) == [waiting.id])
        #expect(inbox.captures.map(\.expandsCardID) == [nil])
        #expect(inbox.captures.map(\.text) == ["serendipia"])
        #expect(inbox.captures.map(\.note) == ["Viene de un cuento persa"])
        #expect(inbox.captures.map(\.source) == ["Un podcast"])
        #expect(try engine.progress(settings).inInbox == 1)
    }

    @Test("the menu's counts leave the deleted cards out: a due one, a learned one and a flagged one")
    func theMenusCountsLeaveTheDeletedCardsOut() throws {
        // serendipia gets learned, graduated to wait 21 days or more, and
        // comes due, as ubuntu does on the first learning step. ojalá is
        // flagged.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climbUntilLearned(serendipia, movingForward: time)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.meet(ubuntu)
        try engine.flag(ojala.id, note: note("Falta un ejemplo"))
        time.move(to: try #require(try engine.standing(of: serendipia.id, with: settings.scheduler).due))
        let before = try engine.progress(settings)

        try engine.delete([serendipia.id, ojala.id])

        let after = try engine.progress(settings)
        #expect(before.due == 2)
        #expect(before.learned == 1)
        #expect(before.inInbox == 1)
        #expect(after.due == 1)
        #expect(after.learned == 0)
        #expect(after.inInbox == 0)
        #expect(try engine.reviewNow(settings) == [.review(ubuntu)])
    }

    // Lucas confirms the cards together, so they're deleted together or not
    // at all.
    @Test("deleting several cards deletes none of them when one doesn't exist")
    func deletingSeveralCardsIsAllOrNothing() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(serendipia)
        try engine.expand(text: "Serendipia", note: "También es una película", source: nil)
        let log = try engine.reviewLog()
        let inbox = try engine.inbox()

        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.delete([serendipia.id, ubuntu.id, 99])
        }
        #expect(try engine.cards() == [serendipia, ubuntu])
        #expect(try engine.reviewLog() == log)
        #expect(try engine.inbox().expansions == inbox.expansions)
    }

    // A card's step can't be reset: Lucas deletes it and captures it again
    // (#87).
    @Test("once a card is deleted, capturing its front again saves a new capture in the inbox")
    func aDeletedCardsFrontCanBeCapturedAgain() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.delete([serendipia.id])

        let result = try engine.capture(text: "Serendipia", note: nil, source: nil)

        let capture = try #require(result.saved)
        #expect(try engine.inbox().captures == [capture])
    }

    // The panel's cards were picked when it opened, and Lucas can delete one
    // of them in the Cards window meanwhile, as a refine session can bury one.
    @Test("the review panel can't answer, flag or bury a card deleted meanwhile, and stays on it until it closes")
    func thePanelRefusesACardDeletedMeanwhile() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        try engine.meet(petricor)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        try engine.delete([ubuntu.id])

        #expect(throws: EngineError.cardNotFound(ubuntu.id)) {
            try panel.answer(.review(.good), responseTime: .seconds(3))
        }
        #expect(throws: EngineError.cardNotFound(ubuntu.id)) {
            try panel.flag(note: note("Falta un ejemplo"))
        }
        #expect(throws: EngineError.cardNotFound(ubuntu.id)) {
            try panel.bury()
        }
        #expect(panel.current == .review(ubuntu))
        #expect(!panel.canUndo)
        #expect(try engine.reviewLog().map(\.cardID) == [petricor.id])
        panel.close(.byLucas)
        #expect(try engine.appearanceLog().map(\.outcome) == [.snoozed])
        #expect(try engine.reviewNow(settings) == [.review(petricor)])
    }

    @Test("⌘Z can't undo what Lucas did with a card deleted meanwhile, and says so")
    func undoRefusesACardDeletedMeanwhile() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        try engine.meet(petricor)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        try panel.answer(.review(.good), responseTime: .seconds(3))
        try engine.delete([ubuntu.id])

        #expect(throws: EngineError.cardNotFound(ubuntu.id)) {
            try panel.undo()
        }
        #expect(panel.current == .review(petricor))
        #expect(try engine.reviewLog().map(\.cardID) == [petricor.id])
    }
}
