import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on follow-ups: a question Lucas asks in the review panel about the
/// card in front of him waits in the inbox tied to that card, for a refine
/// session to turn it into new cards beside it.
struct FollowUpTests {
    let calendar: Calendar
    let time: ManualTimeSource
    /// The steady clock the panel times Lucas on.
    let clock = ManualClock()
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("a follow-up waits in the inbox with its card, apart from the captures and the expansions")
    func aFollowUpWaitsInTheInboxWithItsCard() throws {
        let poderes = try approve(
            card(
                .concept, front: "La división de poderes en la Argentina",
                back: "Ejecutivo, legislativo y judicial.", tags: ["derecho"]),
            in: engine)
        try engine.newCapture("ubuntu")
        try engine.expand(text: "la división de poderes en la Argentina", note: nil, source: nil)
        time.advance(by: minutes(5))

        let followUp = try engine.followUp(poderes.id, text: "  ¿Cómo se eligen los jueces?\n")

        #expect(followUp.text == "¿Cómo se eligen los jueces?")
        #expect(followUp.note == nil)
        #expect(followUp.source == nil)
        #expect(followUp.createdAt == time.now)
        #expect(followUp.followsUpCardID == poderes.id)
        #expect(followUp.expandsCardID == nil)
        let inbox = try engine.inbox()
        #expect(inbox.followUps.map(\.capture) == [followUp])
        #expect(inbox.followUps.map(\.card) == [poderes])
        #expect(inbox.captures.map(\.text) == ["ubuntu"])
        #expect(inbox.expansions.map(\.capture.text) == ["la división de poderes en la Argentina"])
        #expect(try engine.progress(settings).inInbox == 3)
    }

    // No alert stops a review: a refine session sees every front.
    @Test("a follow-up is saved even when it repeats a card's front or another follow-up")
    func aFollowUpIsntCheckedForDuplicates() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)

        let first = try engine.followUp(ubuntu.id, text: "Ubuntu")
        let second = try engine.followUp(ubuntu.id, text: "ubuntu")

        #expect(try engine.inbox().followUps.map(\.capture) == [first, second])
    }

    @Test("a blank follow-up isn't saved, nor one about a card that doesn't exist")
    func aBlankFollowUpOrOneWithoutItsCardIsntSaved() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)

        #expect(throws: EngineError.emptyCapture) {
            try engine.followUp(ubuntu.id, text: " \n")
        }
        #expect(throws: EngineError.cardNotFound(99)) {
            try engine.followUp(99, text: "¿De dónde viene?")
        }
        #expect(try engine.inbox().followUps.isEmpty)
        #expect(try engine.inbox().captures.isEmpty)
    }

    // So what Lucas asked isn't lost, as an expansion isn't.
    @Test("deleting a follow-up's card leaves the follow-up in the inbox as a plain capture")
    func aFollowUpOfADeletedCardBecomesACapture() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let followUp = try engine.followUp(ubuntu.id, text: "¿De qué idioma viene?")

        try engine.delete([ubuntu.id])

        let inbox = try engine.inbox()
        #expect(inbox.followUps.isEmpty)
        #expect(inbox.captures.map(\.id) == [followUp.id])
        #expect(inbox.captures.map(\.text) == ["¿De qué idioma viene?"])
        #expect(inbox.captures.map(\.followsUpCardID) == [nil])
        #expect(try engine.progress(settings).inInbox == 1)
    }

    @Test("a follow-up stays tied to its card when the card is buried, flagged or set aside")
    func aFollowUpKeepsItsCard() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        let mayo = try approve(
            card(.concept, front: "Revolución de Mayo", back: "25 de mayo de 1810.", tags: ["historia"]), in: engine)
        let followUps = [
            try engine.followUp(ubuntu.id, text: "¿De qué idioma viene?"),
            try engine.followUp(petricor.id, text: "¿Quién inventó la palabra?"),
            try engine.followUp(mayo.id, text: "¿Quiénes formaron la Primera Junta?"),
        ]

        let buried = try engine.bury(ubuntu.id)
        let flagged = try engine.flag(petricor.id, note: note("Falta un ejemplo"))
        try engine.changeDeck(of: [mayo.id], to: "Historia")
        try engine.setAside(deck: "Historia")

        let inbox = try engine.inbox()
        #expect(inbox.followUps.map(\.capture) == followUps)
        #expect(inbox.followUps.map(\.card) == [buried, flagged, try engine.cards()[2]])
        #expect(try engine.cards()[2].standing == .setAside(by: ["Historia"]))
    }

    // A follow-up never changes the card it came from.
    @Test("approving a follow-up creates new cards and leaves its card as it is")
    func approvingAFollowUpCreatesNewCards() throws {
        let poderes = try approve(
            card(
                .concept, front: "La división de poderes en la Argentina",
                back: "Ejecutivo, legislativo y judicial.", tags: ["derecho"]),
            in: engine)
        let followUp = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        let jueces = try card(
            .question, front: "¿Cómo se eligen los jueces de la Corte Suprema?",
            back: "Los propone el Presidente y los aprueba el Senado con dos tercios.", tags: ["derecho"])

        let approved = try engine.approve(followUp.id, into: [jueces])

        #expect(approved.map(content(of:)) == [jueces])
        #expect(approved.map(\.captureID) == [followUp.id])
        #expect(try engine.cards() == [poderes] + approved)
        #expect(try engine.inbox().followUps.isEmpty)
        #expect(try engine.progress(settings).inInbox == 0)
    }

    // A refine session approves an expansion into its card instead.
    @Test("a follow-up can't be approved as an expansion, so its card keeps its content")
    func aFollowUpIsntAnExpansion() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let followUp = try engine.followUp(ubuntu.id, text: "¿De qué idioma viene?")

        #expect(throws: EngineError.notAnExpansion(followUp.id)) {
            try engine.approveExpansion(followUp.id, into: card(.word, front: "ubuntu", back: "Del zulú."))
        }
        #expect(try engine.cards() == [ubuntu])
        #expect(try engine.inbox().followUps.map(\.capture) == [followUp])
    }

    @Test("editing a follow-up keeps it tied to its card")
    func editingAFollowUpKeepsItsCard() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let followUp = try engine.followUp(ubuntu.id, text: "¿De qué idioma viene?")

        let edited = try engine.editCapture(
            followUp.id, text: "¿De qué idioma viene «ubuntu»?", note: "Lo escuché en una charla", source: nil)

        #expect(edited.followsUpCardID == ubuntu.id)
        #expect(try engine.inbox().followUps.map(\.capture) == [edited])
        #expect(try engine.inbox().followUps.map(\.card) == [ubuntu])
    }

    @Test(
        "asking on a card's first view, front or back saves a follow-up without rating it, and the panel stays on the card, its side as it was"
    )
    func askingStaysOnTheCard() throws {
        let petricor = try approveCard("petricor", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        let log = try engine.reviewLog()
        var panel = try engine.openPanel(
            .reviewNow, with: [.new(petricor), .review(ubuntu)], settings: settings, clock: clock)

        panel.startAsking()
        panel.write(question: "¿Quién inventó la palabra?")
        panel.finishAsking()
        #expect(panel.content == .upperSide(petricor, isNew: true))
        #expect(try engine.reviewLog() == log)
        panel.flip()
        panel.rate(.good)
        panel.startAsking()
        panel.write(question: "¿De qué idioma viene?")
        panel.finishAsking()
        #expect(panel.content == .upperSide(ubuntu))
        panel.flip()
        panel.startAsking()
        panel.write(question: "¿Qué otras palabras zulúes usamos?")
        panel.finishAsking()

        #expect(panel.content == .bothSides(ubuntu))
        #expect(panel.question == nil)
        #expect(try engine.reviewLog().count == log.count + 1)
        let followUps = try engine.inbox().followUps
        #expect(
            followUps.map(\.capture.text) == [
                "¿Quién inventó la palabra?", "¿De qué idioma viene?", "¿Qué otras palabras zulúes usamos?",
            ])
        #expect(followUps.map(\.card.id) == [petricor.id, ubuntu.id, ubuntu.id])
    }

    @Test("while Lucas writes a question, the panel shows the card as it showed, and cancelling saves nothing")
    func cancellingAQuestionSavesNothing() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        panel.startAsking()
        panel.write(question: "¿De qué idioma viene?")
        #expect(panel.content == .asking(ubuntu, showsLowerSide: false))
        #expect(panel.question == "¿De qué idioma viene?")
        panel.cancelAsking()

        #expect(panel.content == .upperSide(ubuntu))
        #expect(panel.question == nil)
        #expect(try engine.inbox().followUps.isEmpty)
    }

    @Test("a blank question isn't saved as a follow-up, and the panel keeps asking")
    func aBlankQuestionIsntSaved() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        panel.startAsking()
        panel.write(question: "  \n ")
        #expect(!panel.questionAsksSomething)
        panel.finishAsking()

        #expect(panel.content == .asking(ubuntu, showsLowerSide: false))
        #expect(try engine.inbox().followUps.isEmpty)
        #expect(try engine.inbox().captures.isEmpty)
    }

    @Test(
        "writing a question leaves its time out of the card's response time, whether it's saved or cancelled"
    )
    func writingAQuestionWaits() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings, clock: clock)

        clock.advance(by: .seconds(3))
        panel.startAsking()
        panel.write(question: "¿De qué idioma viene?")
        clock.advance(by: .seconds(20))
        panel.finishAsking()
        clock.advance(by: .seconds(2))
        panel.flip()
        panel.startAsking()
        panel.write(question: "¿Qué otras palabras zulúes usamos?")
        clock.advance(by: .seconds(30))
        panel.cancelAsking()
        clock.advance(by: .seconds(1))
        panel.rate(.good)

        #expect(try engine.reviewLog().last?.responseTime == .seconds(6))
    }

    // So that typing a question or a note never flags, buries or undoes.
    @Test("flagging, burying, asking and undoing do nothing while Lucas writes a question or a note")
    func nothingElseHappensWhileLucasWrites() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        try engine.meet(petricor)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        panel.flip()
        panel.rate(.good)
        panel.flip()
        panel.rate(.good)
        panel.undoLastCard()
        #expect(panel.content == .bothSides(petricor))
        let log = try engine.reviewLog()

        panel.startAsking()
        panel.write(question: "¿Quién inventó la palabra?")
        panel.startFlagging()
        panel.buryCard()
        panel.startAsking()
        panel.undoLastCard()
        #expect(!panel.canUndo)
        #expect(panel.content == .asking(petricor, showsLowerSide: true))
        #expect(panel.question == "¿Quién inventó la palabra?")
        panel.cancelAsking()
        panel.startFlagging()
        panel.startAsking()
        panel.undoLastCard()

        #expect(!panel.canUndo)
        #expect(panel.content == .flagging(petricor, showsLowerSide: true))
        #expect(panel.question == nil)
        #expect(try engine.reviewLog() == log)
        #expect(try engine.cards() == [ubuntu, petricor])
        #expect(try engine.inbox().followUps.isEmpty)
    }

    // The Cards window can delete the card the panel shows.
    @Test("a follow-up about a card deleted meanwhile isn't saved: the panel keeps its question, and says why")
    func aFollowUpAboutADeletedCardIsntSaved() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        try engine.delete([ubuntu.id])

        panel.startAsking()
        panel.write(question: "¿De qué idioma viene?")
        panel.finishAsking()

        #expect(panel.failure?.action == .ask)
        #expect(panel.failure?.error == .cardNotFound(ubuntu.id))
        #expect(panel.content == .asking(ubuntu, showsLowerSide: false))
        #expect(panel.question == "¿De qué idioma viene?")
        #expect(try engine.inbox().captures.isEmpty)
    }
}
