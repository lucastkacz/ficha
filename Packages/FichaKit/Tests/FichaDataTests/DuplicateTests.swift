import FichaCore
import FichaData
import Foundation
import Testing

struct DuplicateTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("a capture that repeats a card's front, ignoring case, accents and surrounding spaces, isn't saved")
    func repeatingACardsFrontIsADuplicate() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let card = try approveCard("Pensamiento crítico", in: engine)

        let result = try engine.capture(text: "  pensamiento CRITICO\n", note: "Otra acepción", source: nil)

        #expect(result == .duplicate(.card(card)))
        #expect(try engine.inbox().captures.isEmpty)
    }

    @Test("a capture that repeats a capture in the inbox isn't saved")
    func repeatingACaptureInTheInboxIsADuplicate() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let first = try engine.newCapture("Ubuntu", note: "Una filosofía africana")

        let result = try engine.capture(text: "ubuntu", note: "El sistema operativo", source: nil)

        #expect(result == .duplicate(.capture(first)))
        #expect(try engine.inbox().captures == [first])
    }

    // In Spanish, ñ is a letter of its own, not an n with an accent.
    @Test("words that differ only in ñ and n aren't duplicates")
    func eñeIsALetterOfItsOwn() throws {
        let engine = try Engine(location: .inMemory, time: time)
        try approveCard("año", in: engine)

        let result = try engine.capture(text: "ano", note: nil, source: nil)

        #expect(result.saved?.text == "ano")
    }

    // Lucas discarded it, or it's in the cards it was approved into, whose
    // fronts are what count.
    @Test("a capture that repeats a capture already refined is saved")
    func refinedCapturesAreNotDuplicates() throws {
        let engine = try Engine(location: .inMemory, time: time)
        try engine.discard(try engine.newCapture("serendipia").id)
        let approved = try engine.newCapture("ubuntu")
        try engine.approve(approved.id, into: [card(.concept, front: "¿Qué es el ubuntu?", back: "Soy porque somos.")])

        #expect(try engine.capture(text: "serendipia", note: nil, source: nil).saved != nil)
        #expect(try engine.capture(text: "ubuntu", note: nil, source: nil).saved != nil)
    }

    @Test("expanding a capture that repeats a card keeps it in the inbox, attached to that card")
    func expandingAttachesTheCaptureToItsCard() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let card = try approveCard("serendipia", in: engine)

        let expansion = try engine.expand(
            text: "Serendipia", note: "También es una película", source: "Una charla")

        let inbox = try engine.inbox()
        #expect(inbox.captures.isEmpty)
        #expect(inbox.expansions.map(\.capture) == [expansion])
        #expect(inbox.expansions.map(\.card) == [card])
        #expect(expansion.text == "Serendipia")
        #expect(expansion.note == "También es una película")
        #expect(expansion.source == "Una charla")
        #expect(try engine.progress(.defaults).inInbox == 1)
    }

    @Test("expanding a capture that repeats a capture in the inbox keeps both there, to refine together")
    func expandingACaptureKeepsBoth() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let first = try engine.newCapture("ubuntu", note: "Una filosofía africana")

        let second = try engine.expand(text: "Ubuntu", note: "El sistema operativo", source: nil)

        let inbox = try engine.inbox()
        #expect(inbox.captures == [first, second])
        #expect(inbox.expansions.isEmpty)
        #expect(second.expandsCardID == nil)
    }

    @Test("approving an expansion changes its card's content, keeps its step and takes it out of the inbox")
    func approvingAnExpansionChangesItsCard() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        let standingBefore = try engine.standing(of: serendipia.id, on: ReviewSettings.defaults.ladder)
        let expansion = try engine.expand(text: "serendipia", note: "También es una película", source: nil)

        let expanded = try engine.approveExpansion(
            expansion.id,
            into: card(
                .word, front: "serendipia",
                back: "Un hallazgo valioso que se da por casualidad. También, una película de 2001.",
                tags: ["lenguaje", "cine"]
            )
        )

        #expect(expanded.id == serendipia.id)
        #expect(expanded.back == "Un hallazgo valioso que se da por casualidad. También, una película de 2001.")
        #expect(expanded.tags == ["lenguaje", "cine"])
        #expect(try engine.cards() == [expanded])
        #expect(try engine.standing(of: serendipia.id, on: ReviewSettings.defaults.ladder) == standingBefore)
        let inbox = try engine.inbox()
        #expect(inbox.expansions.isEmpty)
        #expect(inbox.captures.isEmpty)
    }

    @Test("only an expansion in the inbox can be approved as one")
    func onlyAnExpansionCanBeApprovedAsOne() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try approveCard("serendipia", in: engine)
        let plain = try engine.newCapture("ubuntu")
        let expansion = try engine.expand(text: "serendipia", note: nil, source: nil)
        let content = try card(.word, front: "serendipia", back: "Un hallazgo por casualidad.")
        try engine.approveExpansion(expansion.id, into: content)

        #expect(throws: EngineError.notAnExpansion(plain.id)) {
            try engine.approveExpansion(plain.id, into: content)
        }
        #expect(throws: EngineError.captureNotInInbox(expansion.id)) {
            try engine.approveExpansion(expansion.id, into: content)
        }
        #expect(try engine.inbox().captures == [plain])
        #expect(try engine.cards().map(\.id) == [serendipia.id])
    }

    // Refining unburies it first, if Lucas wants it back.
    @Test("an expansion of a buried card can't be approved until the card is unburied")
    func anExpansionOfABuriedCardWaits() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.bury(serendipia.id)
        let expansion = try engine.expand(text: "serendipia", note: nil, source: nil)
        let content = try card(.word, front: "serendipia", back: "Un hallazgo por casualidad.")

        #expect(throws: EngineError.cardBuried(serendipia.id)) {
            try engine.approveExpansion(expansion.id, into: content)
        }
        #expect(try engine.inbox().expansions.map(\.capture) == [expansion])

        try engine.unbury(serendipia.id)
        #expect(try engine.approveExpansion(expansion.id, into: content).back == "Un hallazgo por casualidad.")
    }
}
