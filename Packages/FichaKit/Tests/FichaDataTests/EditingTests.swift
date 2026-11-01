import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on editing in the Cards window: a card changes its content and keeps
/// its progress, and is fixed when it's flagged; a capture in the
/// inbox changes its text, note and source, and stays in the inbox.
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

    @Test("an edit changes a card's content and keeps its progress, its due time and its review log")
    func anEditKeepsTheCardsProgress() throws {
        // serendipia graduates with two goods, due a day later, and Lucas
        // edits it before it's due.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 2, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: settings.scheduler)
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
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == standing)
        time.move(to: try #require(standing.due))
        #expect(try engine.reviewNow(settings) == [.review(edited)])
    }

    // The Cards window (#87) has no button to unflag a card flagged by
    // mistake: Lucas saves it as it is.
    @Test(
        "editing a flagged card fixes it, even with its content unchanged: it's back where it stood in Lucas's reviews")
    func editingAFlaggedCardFixesIt() throws {
        // serendipia climbs to the second step, 4 hours, and Lucas flags it
        // before it's due.
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 1, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: settings.scheduler)
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
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == standing)
        time.move(to: try #require(standing.due))
        #expect(try engine.reviewNow(settings) == [.review(edited)])
    }

    // Lucas can edit a buried card before deciding whether to unbury it.
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

    // The Cards window passes what each field holds, as the capture window
    // does, so a field left empty arrives as a blank string.
    @Test(
        "editing a capture replaces its text, note and source, cleaned up as capturing does, and keeps when it was captured"
    )
    func editingACaptureReplacesItsContent() throws {
        let capture = try engine.newCapture("navaja de okham", note: "Algo de filosofía", source: "Un podcast")
        time.advance(by: hours(1))

        let edited = try engine.editCapture(
            capture.id, text: "  Navaja de Ockham\n", note: "La explicación más simple suele ser la mejor.",
            source: "  ")

        #expect(edited.id == capture.id)
        #expect(edited.text == "Navaja de Ockham")
        #expect(edited.note == "La explicación más simple suele ser la mejor.")
        #expect(edited.source == nil)
        #expect(edited.createdAt == capture.createdAt)
        #expect(try engine.inbox().captures == [edited])
    }

    // A refine session can approve or discard a capture while Lucas edits it
    // in the Cards window.
    @Test("only a capture in the inbox can be edited: one approved, discarded or that doesn't exist is refused")
    func onlyACaptureInTheInboxCanBeEdited() throws {
        let approved = try engine.newCapture("serendipia")
        try engine.approve(
            approved.id, into: [card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad.")])
        let discarded = try engine.newCapture("algo que ya no me interesa")
        try engine.discard(discarded.id)

        #expect(throws: EngineError.captureNotInInbox(approved.id)) {
            try engine.editCapture(approved.id, text: "serendipia", note: "Otra acepción", source: nil)
        }
        #expect(throws: EngineError.captureNotInInbox(discarded.id)) {
            try engine.editCapture(discarded.id, text: "algo que sí me interesa", note: nil, source: nil)
        }
        #expect(throws: EngineError.captureNotInInbox(99)) {
            try engine.editCapture(99, text: "ubuntu", note: nil, source: nil)
        }
    }

    // Editing doesn't check for duplicates, as capturing does: an expansion
    // waits attached to the card it repeated when Lucas expanded it.
    @Test("an edited expansion stays attached to its card, even when its text now repeats another card's front")
    func anEditedExpansionStaysAttachedToItsCard() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("ubuntu", in: engine)
        let expansion = try engine.expand(text: "Serendipia", note: "También es una película", source: nil)

        let edited = try engine.editCapture(expansion.id, text: "ubuntu", note: "Otra acepción", source: "Una charla")

        #expect(edited.expandsCardID == serendipia.id)
        let inbox = try engine.inbox()
        #expect(inbox.captures.isEmpty)
        #expect(inbox.expansions.map(\.capture) == [edited])
        #expect(inbox.expansions.map(\.card) == [serendipia])
    }

    @Test("editing a capture with a blank text is refused, and the capture stays as it was")
    func editingACaptureWithABlankTextIsRefused() throws {
        let capture = try engine.newCapture("serendipia", note: "Lo opuesto a buscar algo")

        #expect(throws: EngineError.emptyCapture) {
            try engine.editCapture(capture.id, text: " \n", note: "Una nota sin texto", source: nil)
        }
        #expect(try engine.inbox().captures == [capture])
    }
}
