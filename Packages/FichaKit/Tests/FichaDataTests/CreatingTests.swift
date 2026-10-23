import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on what comes in as a card wherever it comes from, through
/// `CardContent`: a card with no type, and a card created with no capture.
struct CreatingTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("a card approved, fixed or edited with no type keeps no type")
    func aCardWithNoTypeKeepsNoType() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let approved = try approve(card(nil, front: "ubuntu", back: "Soy porque somos."), in: engine)
        let fixed = try approveCard("serendipia", in: engine)
        let edited = try approveCard("petricor", in: engine)
        try engine.flag(fixed.id, note: note("Le falta un ejemplo"))

        try engine.fix(fixed.id, with: card(nil, front: "serendipia", back: "Un hallazgo por casualidad."))
        try engine.edit(edited.id, with: card(nil, front: "petricor", back: "El olor de la lluvia."))

        #expect(approved.type == nil)
        #expect(try engine.cards().map(\.type) == [nil, nil, nil])
    }

    @Test("a card created with no capture goes into reviews as new, and comes up for its first view like any new card")
    func aCardCreatedWithNoCaptureComesUpAsNew() throws {
        let engine = try Engine(location: .inMemory, time: time)
        time.advance(by: hours(1))

        let created = try engine.create(
            card(nil, front: "  petricor ", back: "El olor de la lluvia.", tags: ["lenguaje"]))

        #expect(try engine.cards() == [created])
        #expect(created.front == "petricor")
        #expect(created.tags == ["lenguaje"])
        #expect(created.captureID == nil)
        #expect(created.createdAt == time.now)
        #expect(created.standing == .inReviews)
        #expect(try engine.standing(of: created.id, on: ReviewSettings.defaults.ladder) == .new)
        #expect(try engine.inbox().captures.isEmpty)
        #expect(try engine.reviewNow(.defaults) == [.firstView(created)])
    }

    // `ficha cards` prints the cards this way, as it leaves out a source.
    @Test("Card's encoding leaves out type and captureID when they're nil")
    func aCardsEncodingLeavesOutTypeAndCaptureIDWhenNil() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let approved = try approveCard("serendipia", in: engine)
        try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cards()))
        let cards = try #require(encoded as? [[String: Any]])

        #expect(cards.map { $0["type"] as? String } == ["word", nil])
        #expect(cards.map { $0["captureID"] as? Int64 } == [approved.captureID, nil])
        #expect(cards.map { $0.keys.contains("type") } == [true, false])
        #expect(cards.map { $0.keys.contains("captureID") } == [true, false])
    }
}
