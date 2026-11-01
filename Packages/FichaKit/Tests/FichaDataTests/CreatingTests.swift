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
        #expect(try engine.standing(of: created.id, with: ReviewSettings.defaults.scheduler) == .new)
        #expect(try engine.inbox().captures.isEmpty)
        #expect(try engine.reviewNow(.defaults) == [.new(created)])
    }

    // As the Cards window's form opened from a capture makes them: the capture
    // leaves the inbox only once the form closes.
    @Test("a card created from a capture in the inbox remembers it, and the capture stays in the inbox")
    func aCardCreatedFromACaptureRemembersIt() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("ubuntu")

        let created = try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."), from: capture.id)

        #expect(created.captureID == capture.id)
        #expect(try engine.inbox().captures == [capture])
        #expect(try engine.reviewNow(.defaults) == [.new(created)])
    }

    @Test("a card can't be created from a capture that isn't in the inbox, and none is saved")
    func aCardCantBeCreatedFromACaptureOutOfTheInbox() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let discarded = try engine.newCapture("algo que ya no me interesa")
        try engine.discard(discarded.id)
        let ubuntu = try card(nil, front: "ubuntu", back: "Soy porque somos.")

        #expect(throws: EngineError.captureNotInInbox(discarded.id)) {
            try engine.create(ubuntu, from: discarded.id)
        }
        #expect(throws: EngineError.captureNotInInbox(99)) {
            try engine.create(ubuntu, from: 99)
        }
        #expect(try engine.cards().isEmpty)
    }

    // The Cards window's form adds them one at a time, and approves the
    // capture as it closes.
    @Test("a card added from a capture keeps the capture, and the capture stays in the inbox until the form closes")
    func aCardAddedFromACaptureKeepsItUntilTheFormCloses() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("ubuntu, y también ataraxia")
        let ubuntu = try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."), from: capture.id)
        let ataraxia = try engine.create(card(.concept, front: "ataraxia", back: "Serenidad."), from: capture.id)
        #expect(try engine.inbox().captures == [capture])

        let approved = try engine.approve(capture.id)

        #expect(approved == [ubuntu, ataraxia])
        #expect(try engine.cards().map(\.captureID) == [capture.id, capture.id])
        #expect(try engine.inbox().captures.isEmpty)
    }

    @Test("closing after adding cards from a capture takes it out of the inbox, and closing with none leaves it")
    func closingTakesTheCaptureOutOnlyAfterCards() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let withCards = try engine.newCapture("ubuntu")
        let withNone = try engine.newCapture("¿Por qué bostezamos?")
        try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."), from: withCards.id)

        try engine.approve(withCards.id)

        #expect(throws: EngineError.noCards) {
            try engine.approve(withNone.id)
        }
        #expect(try engine.inbox().captures == [withNone])
    }

    @Test("a capture whose text matches a card made from another capture is still a duplicate")
    func aCaptureRepeatingTheCaptureACardWasAddedFromIsADuplicate() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let capture = try engine.newCapture("Ubuntu, lo que dijo Mandela")
        let ubuntu = try engine.create(card(.word, front: "ubuntu", back: "Soy porque somos."), from: capture.id)
        try engine.approve(capture.id)

        let again = try engine.capture(text: "ubuntu, lo que dijo mandela", note: nil, source: nil)

        #expect(again == .duplicate(of: .card(ubuntu)))
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
