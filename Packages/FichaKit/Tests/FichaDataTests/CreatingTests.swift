import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on what comes in as a card wherever it comes from, through
/// `CardContent`: a card with no type, and a card created in the Cards
/// window.
struct CreatingTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("a card created, fixed or edited with no type keeps no type")
    func aCardWithNoTypeKeepsNoType() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let created = try newCard(card(nil, front: "ubuntu", back: "Soy porque somos."), in: engine)
        let fixed = try newCard("serendipia", in: engine)
        let edited = try newCard("petricor", in: engine)
        try engine.flag(fixed.id, note: note("Le falta un ejemplo"))

        try engine.fix(fixed.id, with: card(nil, front: "serendipia", back: "Un hallazgo por casualidad."))
        try engine.edit(edited.id, with: card(nil, front: "petricor", back: "El olor de la lluvia."))

        #expect(created.type == nil)
        #expect(try engine.cards().map(\.type) == [nil, nil, nil])
    }

    @Test("a card created goes into reviews as new, and comes up for its first review like any new card")
    func aCardCreatedComesUpAsNew() throws {
        let engine = try Engine(location: .inMemory, time: time)
        time.advance(by: hours(1))

        let created = try engine.create(
            card(nil, front: "  petricor ", back: "El olor de la lluvia.", tags: ["lenguaje"]))

        #expect(try engine.cards() == [created])
        #expect(created.front == "petricor")
        #expect(created.tags == ["lenguaje"])
        #expect(created.createdAt == time.now)
        #expect(created.standing == .inReviews)
        #expect(try engine.standing(of: created.id, with: ReviewSettings.defaults.scheduler) == .new)
        #expect(try engine.reviewNow(.defaults) == [.new(created)])
    }

    // `ficha cards` prints the cards this way, as it leaves out a source. The
    // capture a card came from went with Capture (#540), though the database
    // keeps it unread.
    @Test("Card's encoding leaves out its type when it's nil, and names no capture", .bug(id: 540))
    func aCardsEncodingLeavesOutTypeWhenNil() throws {
        let engine = try Engine(location: .inMemory, time: time)
        try newCard("serendipia", in: engine)
        try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cards()))
        let cards = try #require(encoded as? [[String: Any]])

        #expect(cards.map { $0["type"] as? String } == ["word", nil])
        #expect(cards.map { $0.keys.contains("type") } == [true, false])
        #expect(cards.map { $0.keys.contains("captureID") } == [false, false])
    }
}
