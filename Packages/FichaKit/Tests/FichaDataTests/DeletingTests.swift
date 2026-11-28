import FichaCore
import Foundation
import Testing

@testable import FichaData

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
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        let ojala = try newCard("ojalá", in: engine)
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

    // An older version of Ficha, on another device, may still expand a card or
    // follow it up, and the database keeps what it saved, unread (#540).
    @Test(
        "deleting a card lets go of the captures that expand it or follow it up, which stay as they were but for that",
        .bug(id: 540))
    func deletingACardLetsGoOfItsCaptures() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let refined = try engine.olderCapture("Serendipia", note: "También es una película", expanding: serendipia.id)
        try engine.refineOlderCapture(refined.id)
        try engine.olderCapture(
            "serendipia", note: "Viene de un cuento persa", source: "Un podcast", expanding: serendipia.id)
        try engine.olderCapture("¿Quién inventó la palabra?", followingUp: serendipia.id)

        try engine.delete([serendipia.id])

        let captures = try engine.olderCaptures()
        #expect(captures.map(\.capture.expandsCardID) == [nil, nil, nil])
        #expect(captures.map(\.capture.followsUpCardID) == [nil, nil, nil])
        #expect(captures.map(\.capture.text) == ["Serendipia", "serendipia", "¿Quién inventó la palabra?"])
        #expect(captures.map(\.capture.note) == ["También es una película", "Viene de un cuento persa", nil])
        #expect(captures.map(\.capture.source) == [nil, "Un podcast", nil])
        #expect(captures.map(\.isRefined) == [true, false, false])
    }

    @Test("the menu's counts leave the deleted cards out: a due one and a learned one", .bug(id: 540))
    func theMenusCountsLeaveTheDeletedCardsOut() throws {
        // serendipia gets learned, graduated to wait 21 days or more, and
        // comes due, as ubuntu does on the first learning step. ojalá is
        // flagged, so it counts nowhere.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climbUntilLearned(serendipia, movingForward: time)
        let ubuntu = try newCard("ubuntu", in: engine)
        let ojala = try newCard("ojalá", in: engine)
        try engine.meet(ubuntu)
        try engine.flag(ojala.id, note: note("Falta un ejemplo"))
        time.move(to: try #require(try engine.standing(of: serendipia.id, with: settings.scheduler).due))
        let before = try engine.progress(settings)

        try engine.delete([serendipia.id, ojala.id])

        let after = try engine.progress(settings)
        #expect(before.due == 2)
        #expect(before.learned == 1)
        #expect(after.due == 1)
        #expect(after.learned == 0)
        #expect(try engine.reviewNow(settings) == [.review(ubuntu)])
    }

    // Lucas confirms the cards together, so they're deleted together or not
    // at all.
    @Test("deleting several cards deletes none of them when one doesn't exist")
    func deletingSeveralCardsIsAllOrNothing() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        try engine.meet(serendipia)
        try engine.olderCapture("Serendipia", note: "También es una película", expanding: serendipia.id)
        let log = try engine.reviewLog()
        let captures = try engine.olderCaptures().map(\.capture)

        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.delete([serendipia.id, ubuntu.id, 99])
        }
        #expect(try engine.cards() == [serendipia, ubuntu])
        #expect(try engine.reviewLog() == log)
        #expect(try engine.olderCaptures().map(\.capture) == captures)
    }

    // A card's step can't be reset: Lucas deletes it and adds it again (#87).
    @Test("once a card is deleted, adding its front again makes a new card", .bug(id: 540))
    func aDeletedCardsFrontCanBeAddedAgain() async throws {
        let serendipia = try newCard("serendipia", in: engine)
        try engine.delete([serendipia.id])

        let result = try await engine.add([draft(.word, front: "Serendipia", back: "Un hallazgo por casualidad.")])

        let cards = try engine.cards()
        #expect(result == .added(cards))
        #expect(cards.map(\.front) == ["Serendipia"])
    }

    // The panel's cards were picked when it opened, and Lucas can delete one
    // of them in the Cards window meanwhile, or set one aside.
    @Test("the review panel can't answer, flag or set aside a card deleted meanwhile, and stays on it until it closes")
    func thePanelRefusesACardDeletedMeanwhile() throws {
        let ubuntu = try newCard("ubuntu", in: engine)
        let petricor = try newCard("petricor", in: engine)
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
            try panel.setAside()
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
        let ubuntu = try newCard("ubuntu", in: engine)
        let petricor = try newCard("petricor", in: engine)
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
