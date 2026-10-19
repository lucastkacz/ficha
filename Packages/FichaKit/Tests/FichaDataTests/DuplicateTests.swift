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

        #expect(result == .duplicate(of: .card(card)))
        #expect(try engine.inbox().captures.isEmpty)
    }

    @Test("a capture that repeats a capture in the inbox isn't saved")
    func repeatingACaptureInTheInboxIsADuplicate() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let first = try engine.newCapture("Ubuntu", note: "Una filosofía africana")

        let result = try engine.capture(text: "ubuntu", note: "El sistema operativo", source: nil)

        #expect(result == .duplicate(of: .capture(first)))
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

    // Fronts rarely repeat the capture word for word: "ubuntu" becomes "¿Qué
    // es el ubuntu?".
    @Test("a capture that repeats the capture a card was approved from repeats that card")
    func repeatingAnApprovedCaptureRepeatsItsCard() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let approved = try engine.newCapture("Ubuntu")
        let cards = try engine.approve(
            approved.id, into: [card(.concept, front: "¿Qué es el ubuntu?", back: "Soy porque somos.")])

        let result = try engine.capture(text: "ubuntu", note: nil, source: nil)

        #expect(result == .duplicate(of: .card(try #require(cards.first))))
    }

    @Test("a capture that repeats a discarded capture is saved")
    func discardedCapturesAreNotRepeated() throws {
        let engine = try Engine(location: .inMemory, time: time)
        try engine.discard(try engine.newCapture("serendipia").id)

        #expect(try engine.capture(text: "serendipia", note: nil, source: nil).saved != nil)
    }

    @Test("flagged and buried cards count as repeated too")
    func flaggedAndBuriedCardsCount() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let flagged = try approveCard("serendipia", in: engine)
        let buried = try approveCard("ubuntu", in: engine)
        try engine.flag(flagged.id, note: note("El dorso es confuso"))
        try engine.bury(buried.id)

        let serendipia = try engine.capture(text: "serendipia", note: nil, source: nil)
        let ubuntu = try engine.capture(text: "ubuntu", note: nil, source: nil)

        #expect(serendipia == .duplicate(of: .card(try existing(flagged, in: engine))))
        #expect(ubuntu == .duplicate(of: .card(try existing(buried, in: engine))))
    }

    // Only a card can be expanded.
    @Test("a capture that repeats both a card and a capture in the inbox repeats the card")
    func aCardCountsBeforeACapture() throws {
        let engine = try Engine(location: .inMemory, time: time)
        try engine.newCapture("serendipia")
        let other = try engine.newCapture("un hallazgo por casualidad")
        let card = try #require(
            try engine.approve(other.id, into: [card(.word, front: "Serendipia", back: "Un hallazgo por casualidad.")])
                .first)

        #expect(try engine.capture(text: "serendipia", note: nil, source: nil) == .duplicate(of: .card(card)))
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

    // Its card's front changed after it was expanded, so the new capture only
    // repeats the expansion.
    @Test("expanding a capture that repeats an expansion attaches it to that expansion's card")
    func expandingAnExpansionAttachesToItsCard() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let ubuntu = try engine.newCapture("ubuntu")
        let concept = try card(.concept, front: "¿Qué es el ubuntu?", back: "Soy porque somos.")
        let fixed = try card(.concept, front: "El ubuntu, la filosofía", back: "Soy porque somos.")
        let approved = try #require(try engine.approve(ubuntu.id, into: [concept]).first)
        try engine.expand(text: "¿Qué es el ubuntu?", note: "La distribución de Linux", source: nil)
        try engine.flag(approved.id, note: note("Que diga de dónde viene"))
        try engine.fix(approved.id, with: fixed)

        let expansion = try engine.expand(text: "¿que es el ubuntu?", note: nil, source: nil)

        #expect(expansion.expandsCardID == approved.id)
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

    // One idea per card: a second meaning can make a card of its own.
    @Test("an expansion can be approved into new cards instead")
    func anExpansionCanBecomeNewCards() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try approveCard("serendipia", in: engine)
        let expansion = try engine.expand(text: "serendipia", note: "También es una película", source: nil)

        let new = try engine.approve(
            expansion.id,
            into: [
                card(.question, front: "¿Qué película se llama «Serendipia»?", back: "Una comedia romántica de 2001.")
            ]
        )

        #expect(try engine.cards().map(\.id) == [serendipia.id] + new.map(\.id))
        #expect(try engine.inbox().expansions.isEmpty)
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

    /// The card as the engine has it now.
    private func existing(_ card: Card, in engine: Engine) throws -> Card {
        try #require(try engine.cards().first { $0.id == card.id })
    }
}
