import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a card's Both ways switch (ADR 0016): off for a new card, turned
/// on or off for one card or several at once, and kept by whatever changes
/// the card's content.
struct BothWaysTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test(
        "a new card goes one way, and Both ways turns on and off for one card or several at once, keeping their progress"
    )
    func bothWaysTurnsOnAndOffForOneCardOrSeveral() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        try engine.climb(serendipia, goods: 2, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: settings.scheduler)
        let log = try engine.reviewLog()
        let newCards = try engine.cards()

        let one = try engine.setBothWays(true, of: [ubuntu.id])
        let afterOne = try engine.cards().map(\.bothWays)
        let several = try engine.setBothWays(true, of: [serendipia.id, ubuntu.id, petricor.id])
        let afterSeveral = try engine.cards().map(\.bothWays)
        try engine.setBothWays(false, of: [serendipia.id, petricor.id])

        #expect(newCards.map(\.bothWays) == [false, false, false])
        #expect(one.map(\.id) == [ubuntu.id])
        #expect(one.map(\.bothWays) == [true])
        #expect(afterOne == [false, true, false])
        #expect(several.map(\.id) == [serendipia.id, ubuntu.id, petricor.id])
        #expect(afterSeveral == [true, true, true])
        #expect(try engine.cards().map(\.bothWays) == [false, true, false])
        #expect(try engine.reviewLog() == log)
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == standing)
    }

    // Changing what a card holds, in the Cards window or in a refine session,
    // leaves the switch alone unless it's given, as RefiningTests checks for
    // `ficha fix`.
    @Test("editing, fixing, approving an expansion and putting a sound on a side keep a card's Both ways")
    func changingTheContentKeepsBothWays() async throws {
        let la = try await addTone(440, to: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        let coloratura = try approveCard("coloratura", in: engine)
        try engine.setBothWays(true, of: [serendipia.id, ubuntu.id, petricor.id, coloratura.id])
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let expansion = try engine.expand(text: "Petricor", note: "Viene del griego", source: nil)

        let edited = try engine.edit(
            serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo por casualidad."))
        let fixed = try engine.fix(ubuntu.id, with: card(.concept, front: "ubuntu", back: "Soy porque somos."))
        let expanded = try engine.approveExpansion(
            expansion.id, into: card(.word, front: "petricor", back: "El olor de la lluvia, del griego."))
        let withSound = try await engine.attach(.sound(la), to: .front, of: coloratura.id)

        #expect([edited, fixed, expanded, withSound].map(\.bothWays) == [true, true, true, true])
        #expect(try engine.cards().map(\.bothWays) == [true, true, true, true])
    }

    @Test(
        "switching Both ways off takes the back-first way out of reviews, and switching it on picks it up where it was")
    func switchingBothWaysOffAndOnKeepsTheBackFirstWay() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        time.advance(by: hours(1))
        let backFirst = try engine.standing(of: serendipia.id, way: .backFirst, with: settings.scheduler)

        let oneWay = try engine.setBothWays(false, of: [serendipia.id])
        let whileOff = try engine.reviewNow(settings)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])

        #expect(whileOff == [.review(oneWay[0])])
        #expect(try engine.reviewNow(settings) == [.review(bothWays[0]), .review(bothWays[0], .backFirst)])
        #expect(try engine.standing(of: serendipia.id, way: .backFirst, with: settings.scheduler) == backFirst)
    }

    @Test("Both ways turns on for none of the cards when one of them doesn't exist")
    func bothWaysTurnsOnForNoneWhenACardIsMissing() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.delete([ubuntu.id])

        #expect(throws: EngineError.cardNotFound(ubuntu.id)) {
            try engine.setBothWays(true, of: [serendipia.id, ubuntu.id])
        }
        #expect(try engine.cards().map(\.bothWays) == [false])
    }
}
