import FichaCore
import FichaData
import Foundation
import Testing

struct RefiningTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("approving a capture into several cards saves them in order and takes the capture out of the inbox")
    func approvingSavesTheCardsAndEmptiesTheInbox() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.capture(text: "serendipia", note: nil, source: "Un ensayo de Borges")
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

        #expect(try engine.inbox().isEmpty)
        #expect(try engine.inboxCount() == 0)
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
        let discarded = try engine.capture(text: "algo que ya no me interesa", note: nil, source: nil)
        try engine.capture(text: "ubuntu", note: nil, source: nil)

        try engine.discard(discarded.id)

        #expect(try engine.inbox().map(\.text) == ["ubuntu"])
        #expect(try engine.inboxCount() == 1)
        #expect(try engine.cards().isEmpty)
    }

    // A refine session can repeat a command, so approving twice mustn't save
    // the cards twice.
    @Test("only a capture in the inbox can be approved or discarded")
    func onlyACaptureInTheInboxCanBeRefined() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let approved = try engine.capture(text: "serendipia", note: nil, source: nil)
        let discarded = try engine.capture(text: "algo que ya no me interesa", note: nil, source: nil)
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
        let capture = try engine.capture(text: "serendipia", note: nil, source: nil)

        #expect(throws: EngineError.noCards) {
            try engine.approve(capture.id, into: [])
        }
        #expect(try engine.inbox().map(\.id) == [capture.id])
    }

    @Test("a card is saved without surrounding spaces, and a blank tag or source is left out")
    func cardsAreSavedCleanedUp() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.capture(text: "ubuntu", note: nil, source: nil)

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
}
