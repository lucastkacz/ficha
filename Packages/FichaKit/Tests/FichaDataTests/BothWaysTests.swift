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

    @Test("a new card goes one way, and Both ways turns on and off for one card or several at once, on their steps")
    func bothWaysTurnsOnAndOffForOneCardOrSeveral() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        try engine.climb(serendipia, to: 2, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, on: settings.ladder)
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
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == standing)
    }

    // A refine session's `ficha fix` and `ficha approve-expansion` don't know
    // the switch yet, nor does a side's image or sound put on or taken off.
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
