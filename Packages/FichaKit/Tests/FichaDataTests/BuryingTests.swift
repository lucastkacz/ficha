import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on setting cards aside on their own, which takes them out of
/// Lucas's reviews until he puts them back, without deleting them, one in the
/// review panel or several at once in the Cards window, and on putting them
/// back, there or with `ficha set-aside --off`. The engine keeps a card set
/// aside on its own as its burial, under that name, so these tests call its
/// `bury(_:)` and `unbury(_:)` (#539).
struct BuryingTests {
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
        "a card set aside in the review panel shows up no more, counts nowhere, and keeps its review log",
        .bug(id: 539))
    func aCardSetAsideShowsUpNoMore() throws {
        // serendipia gets learned, graduated to wait 21 days or more, and
        // comes due.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climbUntilLearned(serendipia, movingForward: time)
        time.move(to: try #require(try engine.standing(of: serendipia.id, with: settings.scheduler).due))
        let log = try engine.reviewLog()
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        try panel.setAside()

        #expect(try engine.cards().map(\.buriedAt) == [time.now])
        time.advance(by: days(365))
        #expect(try engine.reviewNow(settings).isEmpty)
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
        let progress = try engine.progress(settings)
        #expect(progress.due == 0)
        #expect(progress.learned == 0)
        #expect(try engine.reviewLog() == log)
    }

    @Test("burying a card from its back-first way buries it both ways, and unburying brings both back where they were")
    func buryingFromTheBackFirstWayBuriesBothWays() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        try engine.meet(serendipia, way: .backFirst)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: [.review(bothWays[0], .backFirst)], settings: settings)

        try panel.setAside()
        let whileBuried = try engine.reviewNow(settings)
        let unburied = try engine.unbury(serendipia.id)

        #expect(whileBuried.isEmpty)
        #expect(try engine.reviewNow(settings) == [.review(unburied), .review(unburied, .backFirst)])
    }

    @Test("an unburied card goes back to where it stood in Lucas's reviews, and counts again")
    func anUnburiedCardGoesBackToWhereItStood() throws {
        // serendipia gets learned: graduated, to wait 21 days or more.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climbUntilLearned(serendipia, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: settings.scheduler)
        try engine.bury(serendipia.id)
        time.move(to: try #require(standing.due))

        let unburied = try engine.unbury(serendipia.id)

        #expect(unburied.buriedAt == nil)
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == standing)
        #expect(try engine.reviewNow(settings) == [.review(unburied)])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
    }

    // `ficha set-aside` can set a flagged card aside instead of fixing it, and
    // setting aside is never a loss (#4).
    @Test(
        "burying a flagged card sets it aside with its flag, and unburying leaves it waiting in its deck with its note",
        .bug(id: 540))
    func anUnburiedFlaggedCardWaitsInItsDeckAgain() throws {
        let serendipia = try newCard("serendipia", in: engine)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))

        let buried = try engine.bury(serendipia.id)
        let flag = try #require(buried.flag)
        #expect(buried.standing == .buried(at: time.now, flag: flag))
        #expect(try engine.flaggedCards().isEmpty)

        try engine.unbury(serendipia.id)
        #expect(try engine.flaggedCards().map(\.flag?.note) == ["Falta decir de dónde viene"])
        #expect(try engine.reviewNow(settings).isEmpty)
    }

    // An agent can repeat a `ficha` command, and a buried card keeps when it
    // was buried.
    @Test("a buried card can't be buried again, and only a buried card can be unburied")
    func onlyABuriedCardCanBeUnburied() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
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
    @Test(
        "burying several cards takes each out of Lucas's reviews, and a flagged one stands set aside, with its flag",
        .bug(id: 540))
    func buryingSeveralCardsTakesThemAllOut() throws {
        // serendipia and ojalá come due on the first step, and ubuntu is
        // flagged.
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        let ojala = try newCard("ojalá", in: engine)
        try engine.meet(serendipia)
        try engine.meet(ojala)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        time.advance(by: hours(1))

        let buried = try engine.bury([serendipia.id, ubuntu.id])

        #expect(buried.map(\.front) == ["serendipia", "ubuntu"])
        #expect(buried.map(\.flag?.note) == [nil, "Falta un ejemplo"])
        #expect(try engine.cards().map(\.buriedAt) == [time.now, time.now, nil])
        #expect(try engine.reviewNow(settings).map(\.card.id) == [ojala.id])
        #expect(try engine.flaggedCards().isEmpty)
        #expect(try engine.progress(settings).due == 1)
    }

    // The Cards window offers Set Aside only when no selected card is set
    // aside on its own, but `ficha set-aside` can set one aside meanwhile.
    @Test("burying several cards buries none of them when one is already buried, or doesn't exist")
    func buryingSeveralCardsIsAllOrNothing() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
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

    @Test(
        "unburying several cards puts each back where it was: in Lucas's reviews where it stood, or waiting in its deck to be fixed",
        .bug(id: 540))
    func unburyingSeveralCardsPutsEachBack() throws {
        // serendipia gets learned, graduated to wait 21 days or more, and
        // ubuntu is flagged.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climbUntilLearned(serendipia, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: settings.scheduler)
        let ubuntu = try newCard("ubuntu", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.bury([serendipia.id, ubuntu.id])
        time.move(to: try #require(standing.due))

        let unburied = try engine.unbury([serendipia.id, ubuntu.id])

        #expect(unburied.map(\.buriedAt) == [nil, nil])
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == standing)
        #expect(try engine.reviewNow(settings).map(\.card.id) == [serendipia.id])
        #expect(try engine.flaggedCards().map(\.flag?.note) == ["Falta un ejemplo"])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
    }

    // The Cards window offers Put Back only when every selected card is set
    // aside on its own, but `ficha set-aside --off` can put one of them back
    // meanwhile.
    @Test("unburying several cards unburies none of them when one isn't buried, or doesn't exist")
    func unburyingSeveralCardsIsAllOrNothing() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
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
