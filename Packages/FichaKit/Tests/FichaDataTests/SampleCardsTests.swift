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

    @Test("the sample cards load into a database with no cards, the first time the iPhone app opens, and never again")
    func sampleCardsLoadOnlyWithoutCards() throws {
        let engine = try Engine(location: .inMemory, time: time)

        try SampleCards.loadIfThereAreNoCards(into: engine)
        try SampleCards.loadIfThereAreNoCards(into: engine)

        #expect(try engine.cards().count == 50)
    }
}
