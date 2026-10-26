import FichaCore
import FichaData
import Foundation
import Testing

struct RefiningTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("approving a capture into several cards saves them in order and takes the capture out of the inbox")
    func approvingSavesTheCardsAndEmptiesTheInbox() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("serendipia", source: "Un ensayo de Borges")
        time.advance(by: 3_600)

        try engine.approve(
            capture.id,
            into: [
                card(
                    .word,
                    front: "serendipia",
                    back: "Un hallazgo valioso que se da por casualidad.",
                    tags: ["lenguaje"],
                    source: "Un ensayo de Borges"
                ),
                card(
                    .question,
                    front: "¿De dónde viene la palabra «serendipia»?",
                    back: "De «Los tres príncipes de Serendip», un cuento persa.",
                    tags: ["lenguaje", "historia"]
                ),
            ]
        )

        #expect(try engine.inbox().captures.isEmpty)
        #expect(try engine.progress(.defaults).inInbox == 0)
        let cards = try engine.cards()
        #expect(cards.map(\.type) == [.word, .question])
        #expect(cards.map(\.front) == ["serendipia", "¿De dónde viene la palabra «serendipia»?"])
        #expect(
            cards.map(\.back) == [
                "Un hallazgo valioso que se da por casualidad.",
                "De «Los tres príncipes de Serendip», un cuento persa.",
            ]
        )
        #expect(cards.map(\.tags) == [["lenguaje"], ["lenguaje", "historia"]])
        #expect(cards.map(\.source) == ["Un ensayo de Borges", nil])
        #expect(cards.map(\.captureID) == [capture.id, capture.id])
        #expect(cards.map(\.createdAt) == Array(repeating: Date(timeIntervalSince1970: 1_760_003_600), count: 2))
    }

    @Test("discarding a capture takes it out of the inbox without cards")
    func discardingTakesItOutWithoutCards() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let discarded = try engine.newCapture("algo que ya no me interesa")
        try engine.newCapture("ubuntu")

        try engine.discard(discarded.id)

        #expect(try engine.inbox().captures.map(\.text) == ["ubuntu"])
        #expect(try engine.progress(.defaults).inInbox == 1)
        #expect(try engine.cards().isEmpty)
    }

    // A refine session can repeat a command, so approving twice mustn't save
    // the cards twice.
    @Test("only a capture in the inbox can be approved or discarded")
    func onlyACaptureInTheInboxCanBeRefined() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let approved = try engine.newCapture("serendipia")
        let discarded = try engine.newCapture("algo que ya no me interesa")
        let serendipia = try card(.word, front: "serendipia", back: "Un hallazgo valioso que se da por casualidad.")
        try engine.approve(approved.id, into: [serendipia])
        try engine.discard(discarded.id)

        #expect(throws: EngineError.captureNotInInbox(approved.id)) {
            try engine.approve(approved.id, into: [serendipia])
        }
        #expect(throws: EngineError.captureNotInInbox(discarded.id)) {
            try engine.approve(discarded.id, into: [serendipia])
        }
        #expect(throws: EngineError.captureNotInInbox(approved.id)) {
            try engine.discard(approved.id)
        }
        #expect(throws: EngineError.captureNotInInbox(99)) {
            try engine.approve(99, into: [serendipia])
        }
        #expect(try engine.cards().count == 1)
    }

    // A capture that becomes no cards is discarded, so approving one into no
    // cards is a mistake that would lose it.
    @Test("approving a capture into no cards is refused, and the capture stays in the inbox")
    func approvingIntoNoCardsIsRefused() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("serendipia")

        #expect(throws: EngineError.noCards) {
            try engine.approve(capture.id, into: [])
        }
        #expect(try engine.inbox().captures.map(\.id) == [capture.id])
    }

    @Test("a card is saved without surrounding spaces, and a blank tag or source is left out")
    func cardsAreSavedCleanedUp() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("ubuntu")

        try engine.approve(
            capture.id,
            into: [
                card(
                    .concept, front: "  ubuntu\n", back: " Soy porque somos. \n", tags: [" filosofía ", " "],
                    source: "  ")
            ]
        )

        let saved = try #require(try engine.cards().first)
        #expect(saved.front == "ubuntu")
        #expect(saved.back == "Soy porque somos.")
        #expect(saved.tags == ["filosofía"])
        #expect(saved.source == nil)
    }

    // As `ficha cards` prints the cards, so a refine session sees which go
    // both ways.
    @Test("a card's encoding says whether it goes both ways, true or false")
    func aCardsEncodingSaysWhetherItGoesBothWays() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cards()))
        let cards = try #require(encoded as? [[String: Any]])

        #expect(cards.map { $0["bothWays"] as? Bool } == [true, false])
    }

    @Test("approving a capture sets each card's Both ways, off when it's left out")
    func approvingSetsBothWays() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("serendipia")

        let approved = try await engine.approve(
            capture.id,
            into: [
                draft(.word, front: "serendipia", back: "Un hallazgo por casualidad.", bothWays: true),
                draft(.question, front: "¿De dónde viene «serendipia»?", back: "De un cuento persa.", bothWays: false),
                draft(.concept, front: "Serendip", back: "El antiguo nombre de Sri Lanka."),
            ])

        #expect(approved.map(\.bothWays) == [true, false, false])
        #expect(try engine.cards().map(\.bothWays) == [true, false, false])
    }

    // Fixing a card's text must never turn its Both ways off.
    @Test("fixing a card keeps its Both ways when it's left out, and changes it when it's given")
    func fixingKeepsOrChangesBothWays() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.setBothWays(true, of: [serendipia.id, ubuntu.id])
        for card in [serendipia, ubuntu, petricor] {
            try engine.flag(card.id, note: note("Falta un ejemplo"))
        }

        let kept = try await engine.fix(
            serendipia.id, with: draft(.word, front: "serendipia", back: "Un hallazgo por casualidad."))
        let turnedOff = try await engine.fix(
            ubuntu.id, with: draft(.concept, front: "ubuntu", back: "Soy porque somos.", bothWays: false))
        let turnedOn = try await engine.fix(
            petricor.id, with: draft(.word, front: "petricor", back: "El olor de la lluvia.", bothWays: true))

        #expect([kept, turnedOff, turnedOn].map(\.bothWays) == [true, false, true])
        #expect(try engine.cards().map(\.bothWays) == [true, false, true])
        #expect(
            try engine.cards().map(\.back) == [
                "Un hallazgo por casualidad.", "Soy porque somos.", "El olor de la lluvia.",
            ])
        #expect(try engine.inbox().flaggedCards.isEmpty)
    }

    // Expanding a card loses nothing: `ficha approve-expansion` reads a card
    // copied from `ficha cards`, `bothWays` and all, and only `ficha fix`
    // changes it.
    @Test("approving an expansion keeps its card's Both ways, whatever the card it's given says")
    func approvingAnExpansionKeepsBothWays() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.setBothWays(true, of: [serendipia.id, ubuntu.id])
        let expansions = try ["Serendipia", "Ubuntu", "Petricor"].map { text in
            try engine.expand(text: text, note: "Falta el origen", source: nil)
        }

        let kept = try await engine.approveExpansion(
            expansions[0].id, into: draft(.word, front: "serendipia", back: "Un hallazgo por casualidad."))
        let keptOn = try await engine.approveExpansion(
            expansions[1].id, into: draft(.concept, front: "ubuntu", back: "Soy porque somos.", bothWays: false))
        let keptOff = try await engine.approveExpansion(
            expansions[2].id, into: draft(.word, front: "petricor", back: "El olor de la lluvia.", bothWays: true))

        #expect([kept, keptOn, keptOff].map(\.id) == [serendipia.id, ubuntu.id, petricor.id])
        #expect([kept, keptOn, keptOff].map(\.bothWays) == [true, true, false])
        #expect(try engine.cards().map(\.bothWays) == [true, true, false])
        #expect(try engine.inbox().expansions.isEmpty)
    }
}
