import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on how a card's content is saved, created in the Cards window or
/// added and fixed through the `ficha` CLI, and how `ficha cards` encodes
/// it.
struct SavingCardsTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test(
        "adding several cards saves them in order, in Default, each with its content and when it came in",
        .bug(id: 540))
    func addingSavesTheCardsInOrder() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        time.advance(by: 3_600)

        let result = try await engine.add([
            draft(
                .word, front: "serendipia", back: "Un hallazgo valioso que se da por casualidad.",
                tags: ["lenguaje"], source: "Un ensayo de Borges"),
            draft(
                .question, front: "¿De dónde viene la palabra «serendipia»?",
                back: "De «Los tres príncipes de Serendip», un cuento persa.", tags: ["lenguaje", "historia"]),
        ])

        let cards = try engine.cards()
        #expect(result == .added(cards))
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
        #expect(cards.map(\.deck) == [Deck.defaultName, Deck.defaultName])
        #expect(cards.map(\.createdAt) == Array(repeating: Date(timeIntervalSince1970: 1_760_003_600), count: 2))
    }

    @Test("a card is saved without surrounding spaces, and a blank tag or source is left out")
    func cardsAreSavedCleanedUp() throws {
        let engine = try Engine(location: .inMemory, time: time)

        try engine.create(
            card(
                .concept, front: "  ubuntu\n", back: " Soy porque somos. \n", tags: [" filosofía ", " "],
                source: "  "))

        let saved = try #require(try engine.cards().first)
        #expect(saved.front == "ubuntu")
        #expect(saved.back == "Soy porque somos.")
        #expect(saved.tags == ["filosofía"])
        #expect(saved.source == nil)
    }

    // As `ficha cards` prints the cards, so an agent sees which go both ways.
    @Test("a card's encoding says whether it goes both ways, true or false")
    func aCardsEncodingSaysWhetherItGoesBothWays() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try newCard("serendipia", in: engine)
        try newCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cards()))
        let cards = try #require(encoded as? [[String: Any]])

        #expect(cards.map { $0["bothWays"] as? Bool } == [true, false])
    }

    @Test("adding cards sets each card's Both ways, off when it's left out", .bug(id: 540))
    func addingSetsBothWays() async throws {
        let engine = try Engine(location: .inMemory, time: time)

        let result = try await engine.add([
            draft(.word, front: "serendipia", back: "Un hallazgo por casualidad.", bothWays: true),
            draft(.question, front: "¿De dónde viene «serendipia»?", back: "De un cuento persa.", bothWays: false),
            draft(.concept, front: "Serendip", back: "El antiguo nombre de Sri Lanka."),
        ])

        #expect(result == .added(try engine.cards()))
        #expect(try engine.cards().map(\.bothWays) == [true, false, false])
    }

    // Fixing a card's text must never turn its Both ways off.
    @Test("fixing a card keeps its Both ways when it's left out, and changes it when it's given")
    func fixingKeepsOrChangesBothWays() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        let petricor = try newCard("petricor", in: engine)
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
        #expect(try engine.flaggedCards().isEmpty)
    }
}
