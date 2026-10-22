import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on flagging a card in the review panel, which sends it to the inbox
/// with Lucas's note on what to fix, and on fixing it in a refine session,
/// which brings it back to his reviews.
struct FlaggingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("a card flagged in the review panel stops showing up and waits in the inbox with Lucas's note")
    func aFlaggedCardWaitsInTheInbox() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        time.advance(by: hours(1))
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)

        try panel.flag(note: note("Falta decir de dónde viene"))

        #expect(try engine.reviewNow(settings).isEmpty)
        #expect(try engine.inbox().flaggedCards.map(\.front) == ["serendipia"])
        #expect(
            try engine.inbox().flaggedCards.map(\.flag) == [
                Flag(note: "Falta decir de dónde viene", flaggedAt: time.now)
            ]
        )
    }

    @Test("a flagged card doesn't bring an appearance, even once it's due")
    func aFlaggedCardBringsNoAppearance() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))

        time.advance(by: hours(1))

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
    }

    // Lucas, 2026-10-15: each card counts in one place.
    @Test("a flagged card counts in the inbox, and neither as due nor as learned until it's fixed")
    func aFlaggedCardCountsInTheInbox() throws {
        // serendipia gets to the 30-day step, from which a card is learned.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 5, movingForward: time)
        try engine.newCapture("algo para refinar")
        try engine.flag(serendipia.id, note: note("La definición está incompleta"))
        time.advance(by: days(30))

        let flagged = try engine.progress(settings)
        try engine.fix(
            serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad."))
        let fixed = try engine.progress(settings)

        #expect(flagged.due == 0)
        #expect(flagged.learned == 0)
        #expect(flagged.inInbox == 2)
        #expect(fixed.due == 1)
        #expect(fixed.learned == 1)
        #expect(fixed.inInbox == 1)
    }

    // The panel's cards were picked when it opened, and a refine session can
    // flag or bury one of them meanwhile.
    @Test("a flagged or buried card can't be answered or flagged")
    func onlyACardInTheReviewsCanBeAnsweredOrFlagged() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        try engine.flag(serendipia.id, note: note("Falta un ejemplo"))
        try engine.bury(ubuntu.id)

        #expect(throws: EngineError.cardFlagged(serendipia.id)) {
            try engine.review(serendipia, .good)
        }
        #expect(throws: EngineError.cardFlagged(serendipia.id)) {
            try engine.flag(serendipia.id, note: note("Otra nota"))
        }
        #expect(throws: EngineError.cardBuried(ubuntu.id)) {
            try engine.review(ubuntu, .good)
        }
        #expect(throws: EngineError.cardBuried(ubuntu.id)) {
            try engine.flag(ubuntu.id, note: note("Otra nota"))
        }
        #expect(try engine.inbox().flaggedCards.map(\.flag?.note) == ["Falta un ejemplo"])
        #expect(try engine.reviewLog().map(\.kind) == [.firstView, .firstView])
    }

    // A burial wins over a flag: the card is out of the inbox too.
    @Test("a card that's both flagged and buried is refused as buried")
    func aFlaggedBuriedCardIsRefusedAsBuried() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        time.advance(by: hours(1))
        try engine.flag(serendipia.id, note: note("Falta un ejemplo"))
        try engine.bury(serendipia.id)

        #expect(throws: EngineError.cardBuried(serendipia.id)) {
            try engine.review(serendipia, .good)
        }
        #expect(throws: EngineError.cardBuried(serendipia.id)) {
            try engine.flag(serendipia.id, note: note("Otra nota"))
        }
        #expect(try engine.inbox().flaggedCards.isEmpty)
    }

    @Test("fixing a flagged card changes its content and brings it back to its step in Lucas's reviews")
    func fixingBringsTheCardBackToItsStep() throws {
        // serendipia climbs to the second step, 4 hours, and Lucas flags it
        // before it's due.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 1, movingForward: time)
        let due = try #require(try engine.standing(of: serendipia.id, on: settings.ladder).due)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))
        time.advance(by: hours(1))

        let fixed = try engine.fix(
            serendipia.id,
            with: card(
                .concept, front: "serendipia", back: "Un hallazgo valioso por casualidad. Viene de «serendipity».",
                tags: ["lenguaje"], source: "Un podcast de etimología")
        )

        #expect(fixed.type == .concept)
        #expect(fixed.front == "serendipia")
        #expect(fixed.back == "Un hallazgo valioso por casualidad. Viene de «serendipity».")
        #expect(fixed.tags == ["lenguaje"])
        #expect(fixed.source == "Un podcast de etimología")
        #expect(fixed.flag == nil)
        #expect(try engine.cards() == [fixed])
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == .onLadder(step: 1, due: due))
        time.move(to: due)
        #expect(try engine.reviewNow(settings) == [.review(fixed)])
    }

    // A refine session can repeat a command, and every change to a card's
    // content goes through a flag (#4). A buried card isn't in the inbox.
    @Test("only a flagged card in the inbox can be fixed: not one in the reviews, nor a buried one")
    func onlyAFlaggedCardCanBeFixed() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let buried = try engine.bury(ubuntu.id)
        let fix = try card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad.")

        #expect(throws: EngineError.cardNotFlagged(serendipia.id)) {
            try engine.fix(serendipia.id, with: fix)
        }
        #expect(throws: EngineError.cardBuried(ubuntu.id)) {
            try engine.fix(ubuntu.id, with: fix)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.fix(99, with: fix)
        }
        #expect(try engine.cards() == [serendipia, buried])
    }

    // The panel passes the note as Lucas typed it.
    @Test("a flag's note is saved without surrounding spaces, and a blank one is no note")
    func theNoteIsSavedCleanedUp() throws {
        let serendipia = try approveCard("serendipia", in: engine)

        try engine.flag(serendipia.id, note: note("  La fecha está mal\n"))

        #expect(try engine.inbox().flaggedCards.map(\.flag?.note) == ["La fecha está mal"])
        #expect(FlagNote(" \n") == nil)
    }
}
