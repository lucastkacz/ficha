import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on what the Cards window lists: Lucas's cards, each with where it
/// stands on his ladder and when he last saw it, and what waits in his inbox.
struct CardsWindowTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("the Cards window lists every card but the buried ones, flagged ones with their flag")
    func theWindowListsEveryCardButTheBuriedOnes() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.bury(ojala.id)

        let rows = try engine.cardRows(in: .all, on: ReviewSettings.defaults.ladder)

        #expect(rows.map(\.card.id) == [serendipia.id, ubuntu.id])
        #expect(rows.map(\.card.flag?.note) == [nil, "Falta un ejemplo"])
    }

    @Test("each card stands on the ladder Lucas set, with its step's wait, and was last seen at its latest answer")
    func eachCardStandsOnLucassLadder() throws {
        // A ladder of 10 minutes, 1 day and 3 days.
        var settings = ReviewSettings.defaults
        settings.ladder = try #require(Ladder(waits: [.seconds(minutes(10)), .seconds(days(1)), .seconds(days(3))]))
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        try engine.record(
            .firstView, of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, settings: settings)
        time.advance(by: minutes(10))
        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)
        let climbedAt = time.now
        time.advance(by: minutes(30))
        try engine.record(.firstView, of: ojala.id, responseTime: .seconds(8), trigger: .reviewNow, settings: settings)
        let metAt = time.now
        // A review ahead, whose good doesn't count, is still the last time
        // Lucas saw it.
        time.advance(by: minutes(30))
        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings,
            reviewingAhead: true)

        let rows = try engine.cardRows(in: .all, on: settings.ladder)

        #expect(
            rows.map(\.frontFirst.standing) == [
                .onLadder(step: 1, due: climbedAt + days(1)), .new, .onLadder(step: 0, due: metAt + minutes(10)),
            ])
        #expect(rows.map(\.frontFirst.step) == [1, nil, 0])
        #expect(rows.map(\.frontFirst.wait) == [.seconds(days(1)), nil, .seconds(minutes(10))])
        #expect(rows.map(\.lastSeen) == [time.now, nil, metAt])
    }

    @Test(
        "a card that goes both ways stands on a step each way, and one that goes one way, or no longer goes both, has no back-first way"
    )
    func aCardThatGoesBothWaysStandsOnAStepEachWay() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.setBothWays(true, of: [serendipia.id, ojala.id, petricor.id])
        let metAt = time.now
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        try engine.meet(petricor)
        try engine.meet(petricor, way: .backFirst)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        let metBackFirstAt = time.now
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        // Switching Both ways off keeps petricor's back-first step, which the
        // Cards window no longer shows.
        try engine.setBothWays(false, of: [petricor.id])

        let rows = try engine.cardRows(in: .all, on: ReviewSettings.defaults.ladder)

        #expect(
            rows.map(\.frontFirst.standing) == [
                .onLadder(step: 1, due: time.now + hours(4)), .onLadder(step: 0, due: metAt + hours(1)), .new,
                .onLadder(step: 0, due: metAt + hours(1)),
            ])
        #expect(
            rows.map(\.backFirst?.standing) == [.onLadder(step: 0, due: metBackFirstAt + hours(1)), nil, .new, nil])
        #expect(rows.map(\.backFirst?.step) == [0, nil, nil, nil])
        #expect(rows.map(\.backFirst?.wait) == [.seconds(hours(1)), nil, nil, nil])
        #expect(rows.map(\.backFirst?.due) == [metBackFirstAt + hours(1), nil, nil, nil])
        #expect(rows.map(\.lastSeen) == [time.now, metAt, nil, metAt])
    }

    @Test("New, Due and Learned list the cards in Lucas's reviews only, as the menu counts them")
    func newDueAndLearnedListCardsInReviews() throws {
        let settings = ReviewSettings.defaults
        // Learned: on the sixth step, which waits 30 days.
        let ojala = try approveCard("ojalá", in: engine)
        try engine.climb(ojala, to: 5, movingForward: time)
        let nunca = try approveCard("nunca", in: engine)
        try engine.climb(nunca, to: 5, movingForward: time)
        try engine.bury(nunca.id)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        let quizas = try approveCard("quizás", in: engine)
        try engine.meet(quizas)
        try engine.bury(quizas.id)
        let jamas = try approveCard("jamás", in: engine)
        try engine.meet(jamas)
        try engine.flag(jamas.id, note: note("El ejemplo no se entiende"))
        // On the first step, due in an hour, as ubuntu was.
        time.advance(by: hours(3))
        let efimero = try approveCard("efímero", in: engine)
        try engine.meet(efimero)
        let serendipia = try approveCard("serendipia", in: engine)
        let acaso = try approveCard("acaso", in: engine)
        try engine.flag(acaso.id, note: note("Falta un ejemplo"))

        let new = try engine.cardRows(in: .new, on: settings.ladder)
        let due = try engine.cardRows(in: .due, on: settings.ladder)
        let learned = try engine.cardRows(in: .learned, on: settings.ladder)

        #expect(new.map(\.card.id) == [serendipia.id])
        #expect(due.map(\.card.id) == [ubuntu.id])
        #expect(learned.map(\.card.id) == [ojala.id])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
        #expect(try engine.cardRows(in: .all, on: settings.ladder).map(\.card.id).contains(efimero.id))
    }

    @Test("Due lists a card when either of its ways is due, and New and Learned go by its front-first way alone")
    func dueGoesByEitherWayAndNewAndLearnedByTheFrontFirstWay() throws {
        let settings = ReviewSettings.defaults
        let ubuntu = try approveCard("ubuntu", in: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        let efimero = try approveCard("efímero", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id, serendipia.id, efimero.id])
        // serendipia is learned back first only, and due front first.
        try engine.meet(serendipia)
        try engine.climb(serendipia, to: 5, way: .backFirst, movingForward: time)
        // ubuntu is learned front first, and due back first only.
        try engine.climb(ubuntu, to: 5, movingForward: time)
        try engine.meet(ubuntu, way: .backFirst)
        // efímero is new back first only.
        try engine.meet(efimero)
        time.advance(by: hours(1))

        let new = try engine.cardRows(in: .new, on: settings.ladder)
        let due = try engine.cardRows(in: .due, on: settings.ladder)
        let learned = try engine.cardRows(in: .learned, on: settings.ladder)

        #expect(new.map(\.card.id) == [ojala.id])
        #expect(due.map(\.card.id) == [ubuntu.id, serendipia.id, efimero.id])
        #expect(learned.map(\.card.id) == [ubuntu.id])
    }

    @Test("Flagged lists the flagged cards that aren't buried, and Buried every buried card, flagged ones too")
    func flaggedAndBuriedListTheirCards() throws {
        let ladder = ReviewSettings.defaults.ladder
        try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let ojala = try approveCard("ojalá", in: engine)
        try engine.bury(ojala.id)
        let acaso = try approveCard("acaso", in: engine)
        try engine.flag(acaso.id, note: note("El dorso es confuso"))
        try engine.bury(acaso.id)

        let flagged = try engine.cardRows(in: .flagged, on: ladder)
        let buried = try engine.cardRows(in: .buried, on: ladder)

        #expect(flagged.map(\.card.id) == [ubuntu.id])
        #expect(buried.map(\.card.id) == [ojala.id, acaso.id])
        #expect(buried.map(\.frontFirst.due) == [nil, nil])
    }

    @Test("a tag lists the cards that have it, and a type the cards of it, flagged ones too but not the buried ones")
    func aTagAndATypeListTheirCards() throws {
        let ladder = ReviewSettings.defaults.ladder
        let mayo = try approve(
            card(.concept, front: "Revolución de Mayo", back: "1810.", tags: ["historia", "política"]), in: engine)
        let ubuntu = try approve(
            card(.word, front: "Ubuntu", back: "Humanidad hacia los otros.", tags: ["filosofía", "lenguaje"]),
            in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let descartes = try approve(
            card(.quote, front: "Pienso, luego existo.", back: "Descartes.", tags: ["filosofía"]), in: engine)
        let estoicismo = try approve(
            card(.concept, front: "Estoicismo", back: "Aceptar lo que no depende de uno.", tags: ["historia"]),
            in: engine)
        try engine.bury(estoicismo.id)
        let serendipia = try approveCard("serendipia", in: engine)

        #expect(try engine.cardRows(in: .tag("historia"), on: ladder).map(\.card.id) == [mayo.id])
        #expect(try engine.cardRows(in: .tag("filosofía"), on: ladder).map(\.card.id) == [ubuntu.id, descartes.id])
        #expect(try engine.cardRows(in: .type(.concept), on: ladder).map(\.card.id) == [mayo.id])
        #expect(try engine.cardRows(in: .type(.word), on: ladder).map(\.card.id) == [ubuntu.id, serendipia.id])
    }

    @Test("the sidebar's tags are every tag of the cards that aren't buried, once each, alphabetically")
    func theSidebarsTagsAreThoseOfTheCardsThatArentBuried() throws {
        try approve(card(.word, front: "Ubuntu", back: "Humanidad.", tags: ["lenguaje", "filosofía"]), in: engine)
        try approve(card(.concept, front: "Eudaimonía", back: "Vida plena.", tags: ["ética", "filosofía"]), in: engine)
        let mercantilismo = try approve(
            card(.concept, front: "Mercantilismo", back: "Acumular metales.", tags: ["economía", "historia"]),
            in: engine)
        try engine.bury(mercantilismo.id)
        try approveCard("serendipia", in: engine)

        #expect(try engine.allTags().map(\.name) == ["ética", "filosofía", "lenguaje"])
    }

    @Test("searching \"fertil\" finds a card whose back says \"fértil\", ignoring case and accents")
    func aSearchFindsTextInTheBackIgnoringCaseAndAccents() throws {
        let ladder = ReviewSettings.defaults.ladder
        let uberrimo = try approve(
            card(.word, front: "Ubérrimo", back: "Muy fértil y abundante: «una tierra ubérrima»."), in: engine)
        try approve(card(.word, front: "Estéril", back: "Que no da fruto."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "fertil", on: ladder).map(\.card.id) == [uberrimo.id])
        #expect(try engine.cardRows(in: .all, matching: " UBERRIMO ", on: ladder).map(\.card.id) == [uberrimo.id])
    }

    @Test("searching \"h2o\" finds a card that says \"H₂O\", and \"x²\" one that says \"x2\"")
    func aSearchIgnoresSuperscriptsAndSubscripts() throws {
        let ladder = ReviewSettings.defaults.ladder
        let water = try approve(card(.word, front: "H₂O", back: "El agua."), in: engine)
        let square = try approve(card(.question, front: "¿Cuánto es x2 si x es 3?", back: "9."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "h2o", on: ladder).map(\.card.id) == [water.id])
        #expect(try engine.cardRows(in: .all, matching: "x²", on: ladder).map(\.card.id) == [square.id])
    }

    @Test("a search finds text in a card's source")
    func aSearchFindsTextInTheSource() throws {
        let ladder = ReviewSettings.defaults.ladder
        let borges = try approve(
            card(
                .quote, front: "El tiempo es la sustancia de que estoy hecho.", back: "Jorge Luis Borges.",
                source: "Nueva refutación del tiempo"),
            in: engine)
        try approveCard("efímero", in: engine)

        #expect(try engine.cardRows(in: .all, matching: "refutacion", on: ladder).map(\.card.id) == [borges.id])
    }

    @Test("searching \"ano\" doesn't find \"año\", since the ñ isn't an n with an accent")
    func aSearchKeepsTheEnye() throws {
        let ladder = ReviewSettings.defaults.ladder
        let anio = try approve(card(.word, front: "Año bisiesto", back: "El que tiene 366 días."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "ano", on: ladder).isEmpty)
        #expect(try engine.cardRows(in: .all, matching: "AÑO", on: ladder).map(\.card.id) == [anio.id])
    }

    @Test("a search narrows the sidebar's choice, and a blank one leaves it whole")
    func aSearchNarrowsTheSidebarsChoice() throws {
        let ladder = ReviewSettings.defaults.ladder
        try approve(card(.word, front: "Ubérrimo", back: "Muy fértil.", tags: ["lenguaje"]), in: engine)
        let fecundo = try approve(card(.word, front: "Fecundo", back: "Fértil, que produce mucho."), in: engine)
        try engine.bury(fecundo.id)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.bury(serendipia.id)

        #expect(try engine.cardRows(in: .buried, matching: "fertil", on: ladder).map(\.card.id) == [fecundo.id])
        #expect(try engine.cardRows(in: .tag("lenguaje"), matching: "fecundo", on: ladder).isEmpty)
        #expect(
            try engine.cardRows(in: .buried, matching: "  ", on: ladder).map(\.card.id) == [fecundo.id, serendipia.id])
    }

    @Test("a flagged card keeps its step but has no due time, since it won't show up until it's fixed")
    func aFlaggedCardHasNoDueTime() throws {
        let ladder = ReviewSettings.defaults.ladder
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("ojalá", in: engine)
        try engine.climb(serendipia, to: 2, movingForward: time)
        try engine.climb(ubuntu, to: 2, movingForward: time)
        let serendipiaStanding = try engine.standing(of: serendipia.id, on: ladder)
        let ubuntuStanding = try engine.standing(of: ubuntu.id, on: ladder)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))

        let rows = try engine.cardRows(in: .all, on: ladder)

        #expect(rows.map(\.frontFirst.standing) == [serendipiaStanding, ubuntuStanding, .new])
        #expect(rows.map(\.frontFirst.due) == [serendipiaStanding.due, nil, nil])
    }

    @Test(
        "the inbox lists the captures, the expansions and the flagged cards that aren't buried, the latest added first, as many as the menu counts"
    )
    func theInboxListsWhatWaitsToBeRefined() throws {
        let ladder = ReviewSettings.defaults.ladder
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        time.advance(by: hours(1))
        let navaja = try engine.newCapture("Navaja de Ockham", note: "Algo de filosofía")
        time.advance(by: hours(1))
        try engine.expand(text: "Serendipia", note: "También es una película", source: nil)
        time.advance(by: hours(1))
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let flaggedAt = time.now
        time.advance(by: hours(1))
        try engine.flag(ojala.id, note: note("El dorso es confuso"))
        try engine.bury(ojala.id)
        time.advance(by: hours(1))
        let bostezo = try engine.newCapture("¿Por qué bostezamos?")
        try engine.discard(try engine.newCapture("algo que ya no me interesa").id)

        let rows = try engine.inboxRows(on: ladder)

        let expansion = try #require(try engine.inbox().expansions.first)
        let flagged = try #require(try engine.cardRows(in: .flagged, on: ladder).first)
        #expect(expansion.card == serendipia)
        #expect(flagged.card.id == ubuntu.id)
        #expect(
            rows.map(\.item) == [.capture(bostezo), .flaggedCard(flagged), .expansion(expansion), .capture(navaja)])
        #expect(rows.map(\.text) == ["¿Por qué bostezamos?", "ubuntu", "Serendipia", "Navaja de Ockham"])
        #expect(rows.map(\.addedAt) == [bostezo.createdAt, flaggedAt, expansion.capture.createdAt, navaja.createdAt])
        #expect(rows.count == (try engine.progress(.defaults).inInbox))
    }

    @Test(
        "a search narrows the inbox: a capture by its text or source, and a flagged card by its front, back or source")
    func aSearchNarrowsTheInbox() throws {
        let ladder = ReviewSettings.defaults.ladder
        let uberrimo = try approve(card(.word, front: "Ubérrimo", back: "Muy fértil y abundante."), in: engine)
        let estoicismo = try approve(
            card(
                .concept, front: "Estoicismo", back: "Aceptar lo que no depende de uno.", source: "Meditaciones"),
            in: engine)
        try engine.flag(uberrimo.id, note: note("Falta un ejemplo"))
        time.advance(by: hours(1))
        try engine.flag(estoicismo.id, note: note("El dorso es confuso"))
        time.advance(by: hours(1))
        try engine.newCapture("Navaja de Ockham", source: "Un podcast de filosofía")
        time.advance(by: hours(1))
        try engine.newCapture("ubuntu")

        #expect(try engine.inboxRows(matching: "OCKHAM", on: ladder).map(\.text) == ["Navaja de Ockham"])
        #expect(try engine.inboxRows(matching: "filosofia", on: ladder).map(\.text) == ["Navaja de Ockham"])
        #expect(try engine.inboxRows(matching: "uberrimo", on: ladder).map(\.text) == ["Ubérrimo"])
        #expect(try engine.inboxRows(matching: "fertil", on: ladder).map(\.text) == ["Ubérrimo"])
        #expect(try engine.inboxRows(matching: "meditaciones", on: ladder).map(\.text) == ["Estoicismo"])
        #expect(
            try engine.inboxRows(matching: "  ", on: ladder).map(\.text) == [
                "ubuntu", "Navaja de Ockham", "Estoicismo", "Ubérrimo",
            ])
    }
}
