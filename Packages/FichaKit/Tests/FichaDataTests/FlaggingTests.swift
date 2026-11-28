import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on flagging a card in the review panel, which takes it out of
/// Lucas's reviews to wait in its deck with his note on what to fix, and on
/// fixing it with `ficha fix`, which brings it back to his reviews.
struct FlaggingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    @Test(
        "a card flagged in the review panel stops showing up and waits in its deck with Lucas's note",
        .bug(id: 540))
    func aFlaggedCardWaitsInItsDeck() throws {
        let serendipia = try newCardInDeck("serendipia", deck: "Palabras lindas", in: engine)
        try engine.meet(serendipia)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        try panel.flag(note: note("Falta decir de dónde viene"))

        let flag = Flag(note: "Falta decir de dónde viene", flaggedAt: time.now)
        #expect(try engine.reviewNow(settings).isEmpty)
        #expect(try engine.flaggedCards().map(\.front) == ["serendipia"])
        #expect(try engine.flaggedCards().map(\.deck) == ["Palabras lindas"])
        #expect(try engine.flaggedCards().map(\.standing) == [.flagged(flag)])
    }

    @Test("a flagged card doesn't bring an appearance, even once it's due")
    func aFlaggedCardBringsNoAppearance() throws {
        let serendipia = try newCard("serendipia", in: engine)
        try engine.meet(serendipia)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))

        time.advance(by: hours(1))

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
    }

    @Test("a flagged card counts neither as due nor as learned until it's fixed", .bug(id: 540))
    func aFlaggedCardCountsNowhereUntilItsFixed() throws {
        // serendipia gets learned: graduated, to wait 21 days or more.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climbUntilLearned(serendipia, movingForward: time)
        try engine.flag(serendipia.id, note: note("La definición está incompleta"))
        time.move(to: try #require(try engine.standing(of: serendipia.id, with: settings.scheduler).due))

        let flagged = try engine.progress(settings)
        try engine.fix(
            serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad."))
        let fixed = try engine.progress(settings)

        #expect(flagged.due == 0)
        #expect(flagged.learned == 0)
        #expect(fixed.due == 1)
        #expect(fixed.learned == 1)
    }

    // The panel's cards were picked when it opened, and the Cards window can
    // flag or set aside one of them meanwhile.
    @Test("a flagged or buried card can't be answered or flagged")
    func onlyACardInTheReviewsCanBeAnsweredOrFlagged() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
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
        #expect(try engine.flaggedCards().map(\.flag?.note) == ["Falta un ejemplo"])
        #expect(try engine.reviewLog().map(\.kind) == [.review(.again), .review(.again)])
    }

    // Setting a card aside on its own wins over its flag: it stands set
    // aside, and waits to be put back before it can be fixed.
    @Test("a card that's both flagged and buried is refused as buried")
    func aFlaggedBuriedCardIsRefusedAsBuried() throws {
        let serendipia = try newCard("serendipia", in: engine)
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
        #expect(try engine.flaggedCards().isEmpty)
    }

    @Test("fixing a flagged card changes its content and brings it back to Lucas's reviews as it stood")
    func fixingBringsTheCardBackAsItStood() throws {
        // serendipia climbs to the second step, 4 hours, and Lucas flags it
        // before it's due.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 1, movingForward: time)
        let due = try #require(try engine.standing(of: serendipia.id, with: settings.scheduler).due)
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
        #expect(try engine.flaggedCards().isEmpty)
        #expect(
            try engine.standing(of: serendipia.id, with: settings.scheduler).stageAndDue == learning(step: 1, due: due))
        time.move(to: due)
        #expect(try engine.reviewNow(settings) == [.review(fixed)])
    }

    @Test("flagging a card from its back-first way flags it both ways, and fixing it brings both back as they stood")
    func flaggingFromTheBackFirstWayFlagsBothWays() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        try engine.meet(serendipia, way: .backFirst)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: [.review(bothWays[0], .backFirst)], settings: settings)

        try panel.flag(note: note("La definición da la palabra"))
        let whileFlagged = try engine.reviewNow(settings)
        let flagged = try engine.flaggedCards().map(\.id)
        let fixed = try engine.fix(
            serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad."))

        #expect(whileFlagged.isEmpty)
        #expect(flagged == [serendipia.id])
        #expect(try engine.reviewNow(settings) == [.review(fixed), .review(fixed, .backFirst)])
    }

    // `ficha fix` can be run again, and every change to a card's content
    // through `ficha` goes through a flag (#4). A card set aside on its own
    // waits to be put back first.
    @Test("only a flagged card can be fixed: not one in the reviews, nor a buried one", .bug(id: 540))
    func onlyAFlaggedCardCanBeFixed() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
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

    // The review panel's ⌘Z unflags a card Lucas flagged there.
    @Test("unflagging a flagged card keeps its content and brings it back to Lucas's reviews as it stood")
    func unflaggingBringsTheCardBackAsItStood() throws {
        // serendipia climbs to the second step, 4 hours, and Lucas flags it
        // before it's due.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 1, movingForward: time)
        let due = try #require(try engine.standing(of: serendipia.id, with: settings.scheduler).due)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))
        time.advance(by: hours(1))

        let unflagged = try engine.unflag(serendipia.id)

        #expect(unflagged == serendipia)
        #expect(try engine.cards() == [serendipia])
        #expect(try engine.flaggedCards().isEmpty)
        #expect(
            try engine.standing(of: serendipia.id, with: settings.scheduler).stageAndDue == learning(step: 1, due: due))
        time.move(to: due)
        #expect(try engine.reviewNow(settings) == [.review(serendipia)])
    }

    // The panel's ⌘Z unflags a card it flagged, which `ficha fix` can fix,
    // or the Cards window set aside, meanwhile. Setting it aside on its own
    // wins over its flag.
    @Test("only a flagged card can be unflagged: not one in the reviews, nor a buried one", .bug(id: 540))
    func onlyAFlaggedCardCanBeUnflagged() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let buried = try engine.bury(ubuntu.id)

        #expect(throws: EngineError.cardNotFlagged(serendipia.id)) {
            try engine.unflag(serendipia.id)
        }
        #expect(throws: EngineError.cardBuried(ubuntu.id)) {
            try engine.unflag(ubuntu.id)
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.unflag(99)
        }
        #expect(try engine.cards() == [serendipia, buried])
    }

    // The panel passes the note as Lucas typed it.
    @Test("a flag's note is saved without surrounding spaces, and a blank one is no note")
    func theNoteIsSavedCleanedUp() throws {
        let serendipia = try newCard("serendipia", in: engine)

        try engine.flag(serendipia.id, note: note("  La fecha está mal\n"))

        #expect(try engine.flaggedCards().map(\.flag?.note) == ["La fecha está mal"])
        #expect(FlagNote(" \n") == nil)
    }

    // So that typing a note never sets the card aside or undoes. Asking a
    // question went with the inbox (#540).
    @Test("setting aside and undoing do nothing while Lucas writes a note", .bug(id: 540))
    func nothingElseHappensWhileLucasWrites() throws {
        let ubuntu = try newCard("ubuntu", in: engine)
        let petricor = try newCard("petricor", in: engine)
        try engine.meet(ubuntu)
        try engine.meet(petricor)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        panel.flip()
        panel.rate(.good)
        panel.flip()
        let log = try engine.reviewLog()

        panel.startFlagging()
        panel.write(note: "Falta un ejemplo")
        panel.setCardAside()
        panel.choose(.setAside)
        panel.choose(.flag)
        panel.undoLastCard()

        #expect(!panel.canUndo)
        #expect(panel.content == .flagging(petricor, showsLowerSide: true))
        #expect(panel.note == "Falta un ejemplo")
        #expect(try engine.reviewLog() == log)
        #expect(try engine.cards() == [ubuntu, petricor])
    }
}
