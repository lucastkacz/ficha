import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on when a card's front or back last changed: an edit in the Cards
/// window, a fix, an approved expansion and an import that updates a
/// duplicate keep it, and a change to anything else leaves it as it was.
struct EditedTimeTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("editing a card's front, its back or a side's image keeps when, each time")
    func editingAFrontOrABackKeepsWhen() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let hornero = try approve(card(.word, front: "hornero", back: "Un pájaro."), in: engine)
        #expect(hornero.editedAt == nil)
        var edits: [Date?] = []

        for (front, back, frontImage, backImage) in [
            ("Hornero", "Un pájaro.", nil, nil),
            ("Hornero", "Un pájaro que hace su nido de barro.", nil, nil),
            ("Hornero", "Un pájaro que hace su nido de barro.", bird, nil),
            ("Hornero", "Un pájaro que hace su nido de barro.", bird, nest),
        ] as [(String, String, ImageName?, ImageName?)] {
            time.advance(by: hours(1))
            edits.append(
                try engine.edit(
                    hornero.id,
                    with: card(.word, front: front, back: back, frontImage: frontImage, backImage: backImage)
                ).editedAt)
        }

        let start = try morning(of: 14, in: calendar)
        #expect(edits == [start + hours(1), start + hours(2), start + hours(3), start + hours(4)])
        #expect(try engine.cards().map(\.editedAt) == [start + hours(4)])
    }

    @Test("putting, replacing or removing a side's sound keeps when, each time")
    func changingASoundKeepsWhen() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let coloratura = try approve(card(.word, front: "coloratura", back: "Ornamentos del canto."), in: engine)
        var edits: [Date?] = []

        for (frontSound, backSound) in [(nil, la), (mi, la), (mi, nil), (mi, nil)] as [(SoundName?, SoundName?)] {
            time.advance(by: hours(1))
            edits.append(
                try engine.edit(
                    coloratura.id,
                    with: card(
                        .word, front: "coloratura", back: "Ornamentos del canto.", frontSound: frontSound,
                        backSound: backSound)
                ).editedAt)
        }

        let start = try morning(of: 14, in: calendar)
        #expect(edits == [start + hours(1), start + hours(2), start + hours(3), start + hours(3)])
    }

    @Test(
        "changing only a card's tags, type or source, or saving it as it was, leaves when its front or back last changed"
    )
    func otherChangesLeaveTheEditedTime() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        time.advance(by: hours(1))
        let rewritten = try engine.edit(
            serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad."))
        time.advance(by: hours(1))

        for (cardID, content) in [
            (serendipia.id, try card(.concept, front: "serendipia", back: "Un hallazgo valioso por casualidad.")),
            (
                serendipia.id,
                try card(
                    .concept, front: "serendipia", back: "Un hallazgo valioso por casualidad.", tags: ["lenguaje"],
                    source: "Un ensayo de Borges")
            ),
            (ubuntu.id, try card(.concept, front: ubuntu.front, back: ubuntu.back, tags: ["filosofía"])),
            (ubuntu.id, try card(.concept, front: ubuntu.front, back: ubuntu.back, tags: ["filosofía"])),
        ] {
            try engine.edit(cardID, with: content)
            time.advance(by: hours(1))
        }

        let cards = try engine.cards()
        #expect(cards.map(\.editedAt) == [rewritten.editedAt, nil])
        #expect(cards.map(\.tags) == [["lenguaje"], ["filosofía"]])
        #expect(rewritten.editedAt == serendipia.createdAt + hours(1))
    }

    // So that forgotten often doesn't start over (#230).
    @Test("turning Both ways on or off, alone or in an edit, leaves when the card's front or back last changed")
    func bothWaysLeavesTheEditedTime() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        time.advance(by: hours(1))
        let rewritten = try engine.edit(
            serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad."))
        time.advance(by: hours(1))

        let switched = try engine.setBothWays(true, of: [serendipia.id, ubuntu.id])
        time.advance(by: hours(1))
        let edited = try engine.edit(
            ubuntu.id, with: card(.word, front: ubuntu.front, back: ubuntu.back), bothWays: false)

        #expect(switched.map(\.editedAt) == [rewritten.editedAt, nil])
        #expect(edited.bothWays == false)
        #expect(edited.editedAt == nil)
    }

    // `ficha fix`, in a refine session.
    @Test("fixing a flagged card with a new front or back keeps when; fixing it with only new tags doesn't")
    func fixingAFlaggedCard() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))
        time.advance(by: hours(1))
        let rewritten = try engine.fix(
            serendipia.id,
            with: card(.word, front: "serendipia", back: "Un hallazgo por casualidad. De un cuento persa."))
        let fixedAt = time.now
        try engine.flag(serendipia.id, note: note("Le falta un tag"))
        time.advance(by: hours(1))

        let retagged = try engine.fix(
            serendipia.id,
            with: card(
                .word, front: "serendipia", back: "Un hallazgo por casualidad. De un cuento persa.",
                tags: ["lenguaje"]))

        #expect(rewritten.editedAt == fixedAt)
        #expect(retagged.editedAt == fixedAt)
        #expect(retagged.tags == ["lenguaje"])
    }

    // `ficha approve-expansion`, in a refine session.
    @Test("approving an expansion that gives its card a new back keeps when; one that only adds a tag doesn't")
    func approvingAnExpansion() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let longer = try engine.expand(text: "Serendipia", note: "Viene de un cuento persa", source: nil)
        let tagged = try engine.expand(text: "Ubuntu", note: "Es de filosofía", source: nil)
        time.advance(by: hours(1))

        let expanded = try engine.approveExpansion(
            longer.id, into: card(.word, front: "serendipia", back: "Un hallazgo por casualidad, de un cuento persa."))
        let retagged = try engine.approveExpansion(
            tagged.id, into: card(.word, front: ubuntu.front, back: ubuntu.back, tags: ["filosofía"]))

        #expect(expanded.id == serendipia.id)
        #expect(expanded.editedAt == time.now)
        #expect(retagged.tags == ["filosofía"])
        #expect(retagged.editedAt == nil)
    }

    // `ficha cards` prints the cards this way, so a refine session can tell
    // a rewritten card.
    @Test("a card's encoding has editedAt once its front or back changed, and leaves it out otherwise")
    func aCardsEncodingHasEditedAtWhenSet() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("ubuntu", in: engine)
        try engine.edit(serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo por casualidad."))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try JSONSerialization.jsonObject(with: encoder.encode(try engine.cards()))
        let cards = try #require(encoded as? [[String: Any]])

        #expect(cards.map { $0["editedAt"] as? String } == ["2026-10-14T12:00:00Z", nil])
        #expect(cards.map { $0.keys.contains("editedAt") } == [true, false])
    }
}
