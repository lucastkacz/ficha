import FichaCore
import FichaData
import Foundation
import Testing

struct SampleCardsTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("Ficha Dev's sample cards load as fifty new cards, and the inbox stays as it was")
    func sampleCardsLoadAsNewCards() throws {
        let engine = try Engine(location: .inMemory, time: time)
        try engine.newCapture("algo que anoté")

        try SampleCards.load(into: engine)

        let cards = try engine.cards()
        #expect(cards.count == 50)
        #expect(try cards.allSatisfy { try engine.standing(of: $0.id, on: ReviewSettings.defaults.ladder) == .new })
        #expect(try engine.inbox().captures.map(\.text) == ["algo que anoté"])
    }

    // Chamuyo sits three levels down, in Idiomas › Español › Rioplatense, and
    // Sociedad holds cards of its own beside its deck inside.
    @Test("the sample cards sit in decks, some inside others, one in Default, each keeping its tags")
    func sampleCardsSitInDecks() throws {
        let engine = try Engine(location: .inMemory, time: time)

        try SampleCards.load(into: engine)

        #expect(
            try engine.decks().map(\.name) == [
                Deck.defaultName, "Ciencias", "Ciencias::Naturales", "Ciencias::Psicología", "Humanidades",
                "Humanidades::Filosofía", "Humanidades::Historia", "Humanidades::Literatura", "Idiomas",
                "Idiomas::Español", "Idiomas::Español::Rioplatense", "Idiomas::Palabras prestadas", "Sociedad",
                "Sociedad::Economía",
            ])
        let chamuyo = try #require(try engine.cards().first { $0.front == "chamuyo" })
        #expect(chamuyo.deck == "Idiomas::Español::Rioplatense")
        #expect(chamuyo.tags == ["lenguaje", "argentina"])
        #expect(try engine.cards().filter { $0.deck == Deck.defaultName }.map(\.front) == ["petricor"])
        #expect(try engine.cards().filter { $0.deck == "Sociedad" }.count == 2)
    }

    @Test("the sample cards load into a database with no cards, the first time the iPhone app opens, and never again")
    func sampleCardsLoadOnlyWithoutCards() throws {
        let engine = try Engine(location: .inMemory, time: time)

        try SampleCards.loadIfThereAreNoCards(into: engine)
        try SampleCards.loadIfThereAreNoCards(into: engine)

        #expect(try engine.cards().count == 50)
    }
}
