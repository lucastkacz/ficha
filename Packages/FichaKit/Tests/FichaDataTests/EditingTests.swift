import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on editing a card in the Cards window, which changes its content and
/// keeps its place on the ladder, and fixes it when it's flagged.
struct EditingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("an edit changes a card's content and keeps its step, its due time and its review log")
    func anEditKeepsTheCardsStep() throws {
        // serendipia climbs to the third step, 2 days, and Lucas edits it
        // before it's due.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, on: settings.ladder)
        let log = try engine.reviewLog()
        time.advance(by: hours(1))

        let edited = try engine.edit(
            serendipia.id,
            with: card(
                .concept, front: "serendipia", back: "Un hallazgo valioso por casualidad.", tags: ["lenguaje"],
                source: "Un podcast de etimología")
        )

        #expect(edited.type == .concept)
        #expect(edited.front == "serendipia")
        #expect(edited.back == "Un hallazgo valioso por casualidad.")
        #expect(edited.tags == ["lenguaje"])
        #expect(edited.source == "Un podcast de etimología")
        #expect(edited.createdAt == serendipia.createdAt)
        #expect(edited.captureID == serendipia.captureID)
        #expect(try engine.cards() == [edited])
        #expect(try engine.reviewLog() == log)
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == standing)
        time.move(to: try #require(standing.due))
        #expect(try engine.reviewNow(settings) == [.review(edited)])
    }

    // The Cards window (#87) has no button to unflag a card flagged by
    // mistake: Lucas saves it as it is.
    @Test("editing a flagged card fixes it, even with its content unchanged: it's back on its step in Lucas's reviews")
    func editingAFlaggedCardFixesIt() throws {
        // serendipia climbs to the second step, 4 hours, and Lucas flags it
        // before it's due.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, to: 1, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, on: settings.ladder)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))
        time.advance(by: hours(1))

        let edited = try engine.edit(
            serendipia.id,
            with: card(
                serendipia.type, front: serendipia.front, back: serendipia.back, tags: serendipia.tags,
                source: serendipia.source)
        )

        #expect(edited == serendipia)
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.progress(settings).inInbox == 0)
        #expect(try engine.standing(of: serendipia.id, on: settings.ladder) == standing)
        time.move(to: try #require(standing.due))
        #expect(try engine.reviewNow(settings) == [.review(edited)])
    }

    // Lucas can correct a buried card before deciding whether to unbury it.
    @Test("an edited buried card stays buried, and once unburied it's back in Lucas's reviews, fixed if it was flagged")
    func anEditedBuriedCardStaysBuried() throws {
        // serendipia and ubuntu are due on the first step, and ubuntu was
        // flagged before Lucas buried it.
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let buried = try engine.bury([serendipia.id, ubuntu.id])
        time.advance(by: hours(1))

        let edited = [
            try engine.edit(
                serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad.")),
            try engine.edit(
                ubuntu.id,
                with: card(.concept, front: "ubuntu", back: "Soy porque somos: una persona lo es por las demás.")),
        ]

        #expect(edited.map(\.buriedAt) == buried.map(\.buriedAt))
        #expect(edited.map(\.flag) == [nil, nil])
        #expect(try engine.reviewNow(settings).isEmpty)
        #expect(try engine.inbox().flaggedCards.isEmpty)
        try engine.unbury([serendipia.id, ubuntu.id])
        #expect(try engine.reviewNow(settings).map(\.card.front) == ["serendipia", "ubuntu"])
        #expect(try engine.inbox().flaggedCards.isEmpty)
    }
}
