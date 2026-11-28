import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on what the Cards window lists: Lucas's cards, each with where it
/// stands with his scheduling settings and when he last saw it.
struct CardsWindowTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    @Test(
        "a deck lists every card of its own, flagged ones with their flag and those set aside on their own too",
        .bug(id: 539))
    func aDeckListsEveryCardOfItsOwn() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        let ojala = try newCard("ojalá", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.bury(ojala.id)

        let rows = try engine.cardRows(in: .deck(Deck.defaultName), with: ReviewSettings.defaults.scheduler)

        #expect(rows.map(\.card.id) == [serendipia.id, ubuntu.id, ojala.id])
        #expect(rows.map(\.card.flag?.note) == [nil, "Falta un ejemplo", nil])
        #expect(rows.map(\.card.buriedAt) == [nil, nil, time.now])
    }

    @Test(
        "each card stands as the scheduling settings Lucas set space it, with its interval, and was last seen at its latest answer"
    )
    func eachCardStandsAsLucassSettingsSpaceIt() throws {
        // Learning steps of 10 minutes and 6 hours.
        var settings = ReviewSettings.defaults
        settings.scheduler = try #require(
            settings.scheduler.replacing(learningSteps: [.seconds(minutes(10)), .seconds(hours(6))]))
        let serendipia = try newCard("serendipia", in: engine)
        try newCard("ubuntu", in: engine)
        let ojala = try newCard("ojalá", in: engine)
        try engine.record(
            .review(.again), of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow, settings: settings)
        time.advance(by: minutes(10))
        try engine.record(
            .review(.good), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)
        time.advance(by: minutes(30))
        try engine.record(
            .review(.again), of: ojala.id, responseTime: .seconds(8), trigger: .reviewNow, settings: settings)
        let metAt = time.now
        // A review ahead counts as any review, and is the last time Lucas saw
        // the card: hard on the second step waits that step again.
        time.advance(by: minutes(30))
        try engine.record(
            .review(.hard), of: serendipia.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings,
            reviewingAhead: true)

        let rows = try engine.cardRows(in: .all, with: settings.scheduler)

        #expect(
            rows.map(\.frontFirst.standing.stageAndDue) == [
                learning(step: 1, due: time.now + hours(6)), nil, learning(step: 0, due: metAt + minutes(10)),
            ])
        #expect(rows.map(\.frontFirst.interval) == [.seconds(hours(6)), nil, .seconds(minutes(10))])
        #expect(rows.map(\.lastSeen) == [time.now, nil, metAt])
    }

    @Test(
        "a card that goes both ways stands each way on its own, and one that goes one way, or no longer goes both, has no back-first way"
    )
    func aCardThatGoesBothWaysStandsEachWay() throws {
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        let ojala = try newCard("ojalá", in: engine)
        let petricor = try newCard("petricor", in: engine)
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
        // Switching Both ways off keeps petricor's back-first progress, which
        // the Cards window no longer shows.
        try engine.setBothWays(false, of: [petricor.id])

        let rows = try engine.cardRows(in: .all, with: ReviewSettings.defaults.scheduler)

        #expect(
            rows.map(\.frontFirst.standing.stageAndDue) == [
                learning(step: 1, due: time.now + hours(4)), learning(step: 0, due: metAt + hours(1)), nil,
                learning(step: 0, due: metAt + hours(1)),
            ])
        #expect(
            rows.map(\.backFirst?.standing.stageAndDue) == [
                learning(step: 0, due: metBackFirstAt + hours(1)), nil, nil, nil,
            ])
        #expect(rows.map { $0.backFirst.map { $0.standing == .new } } == [false, nil, true, nil])
        #expect(rows.map(\.backFirst?.interval) == [.seconds(hours(1)), nil, nil, nil])
        #expect(rows.map(\.backFirst?.due) == [metBackFirstAt + hours(1), nil, nil, nil])
        #expect(rows.map(\.lastSeen) == [time.now, metAt, nil, metAt])
    }

    // As Anki's Browse says "(learning)" for every card in its learning
    // steps, and the interval of a relearning one.
    @Test(
        "the detail's Interval rows say a way is new, or learning whatever its step's interval, or else its interval"
    )
    func theIntervalRowsSayLearning() throws {
        let ojala = try newCard("ojalá", in: engine)
        let petricor = try newCard("petricor", in: engine)
        let nunca = try newCard("nunca", in: engine)
        try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [ojala.id, petricor.id, ubuntu.id])
        // ojalá waits 21 days or more front first, and is new back first.
        try engine.climbUntilLearned(ojala, movingForward: time)
        // nunca graduated and lapsed: it's on the relearning step, 1 hour.
        try engine.climb(nunca, goods: 2, movingForward: time)
        try engine.reviewWhenDue(nunca, .again, movingForward: time)
        // ubuntu is on the first learning step, 1 hour, both ways.
        try engine.meet(ubuntu)
        try engine.meet(ubuntu, way: .backFirst)
        // petricor is on the second, 4 hours, both ways.
        try engine.climb(petricor, goods: 1, movingForward: time)
        try engine.climb(petricor, goods: 1, way: .backFirst, movingForward: time)

        let rows = try engine.cardRows(in: .all, with: ReviewSettings.defaults.scheduler)

        #expect(rows.map(\.card.front) == ["ojalá", "petricor", "nunca", "serendipia", "ubuntu"])
        guard case .interval(let learned) = rows.first?.frontFirst.intervalWording else {
            Issue.record("ojalá's front-first way doesn't say its interval")
            return
        }
        #expect(learned >= .seconds(days(21)))
        #expect(
            rows.dropFirst().map(\.frontFirst.intervalWording) == [
                .learning(.seconds(hours(4))), .interval(.seconds(hours(1))), .new, .learning(.seconds(hours(1))),
            ])
        #expect(
            rows.map(\.backFirst?.intervalWording) == [
                .new, .learning(.seconds(hours(4))), nil, nil, .learning(.seconds(hours(1))),
            ])
    }

    // A flagged card waits in its deck to be fixed (#540). Set aside on its
    // own too, it stands set aside, and keeps its flag for when it's put
    // back.
    @Test(
        "a deck lists its flagged cards as flagged, and one also set aside on its own as set aside, with its flag",
        .bug(id: 539), .bug(id: 540))
    func aDeckListsItsFlaggedCardsAsTheyStand() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let ojala = try newCard("ojalá", in: engine)
        try engine.bury(ojala.id)
        let acaso = try newCard("acaso", in: engine)
        try engine.flag(acaso.id, note: note("El dorso es confuso"))
        try engine.bury(acaso.id)

        let inDefault = try engine.cardRows(in: .deck(Deck.defaultName), with: scheduler)

        let ubuntuFlag = Flag(note: "Falta un ejemplo", flaggedAt: time.now)
        let acasoFlag = Flag(note: "El dorso es confuso", flaggedAt: time.now)
        #expect(inDefault.map(\.card.id) == [serendipia.id, ubuntu.id, ojala.id, acaso.id])
        #expect(
            inDefault.map(\.cardStanding) == [
                .inReviews, .flagged(ubuntuFlag), .buried(at: time.now, flag: nil),
                .buried(at: time.now, flag: acasoFlag),
            ])
    }

    @Test("searching \"fertil\" finds a card whose back says \"fértil\", ignoring case and accents")
    func aSearchFindsTextInTheBackIgnoringCaseAndAccents() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let uberrimo = try newCard(
            card(.word, front: "Ubérrimo", back: "Muy fértil y abundante: «una tierra ubérrima»."), in: engine)
        try newCard(card(.word, front: "Estéril", back: "Que no da fruto."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "fertil", with: scheduler).map(\.card.id) == [uberrimo.id])
        #expect(try engine.cardRows(in: .all, matching: " UBERRIMO ", with: scheduler).map(\.card.id) == [uberrimo.id])
    }

    @Test("searching \"h2o\" finds a card that says \"H₂O\", and \"x²\" one that says \"x2\"")
    func aSearchIgnoresSuperscriptsAndSubscripts() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let water = try newCard(card(.word, front: "H₂O", back: "El agua."), in: engine)
        let square = try newCard(card(.question, front: "¿Cuánto es x2 si x es 3?", back: "9."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "h2o", with: scheduler).map(\.card.id) == [water.id])
        #expect(try engine.cardRows(in: .all, matching: "x²", with: scheduler).map(\.card.id) == [square.id])
    }

    @Test("a search finds text in a card's source")
    func aSearchFindsTextInTheSource() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let borges = try newCard(
            card(
                .quote, front: "El tiempo es la sustancia de que estoy hecho.", back: "Jorge Luis Borges.",
                source: "Nueva refutación del tiempo"),
            in: engine)
        try newCard("efímero", in: engine)

        #expect(try engine.cardRows(in: .all, matching: "refutacion", with: scheduler).map(\.card.id) == [borges.id])
    }

    @Test("searching \"ano\" doesn't find \"año\", since the ñ isn't an n with an accent")
    func aSearchKeepsTheEnye() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let anio = try newCard(card(.word, front: "Año bisiesto", back: "El que tiene 366 días."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "ano", with: scheduler).isEmpty)
        #expect(try engine.cardRows(in: .all, matching: "AÑO", with: scheduler).map(\.card.id) == [anio.id])
    }

    @Test("a search narrows the sidebar's choice, and a blank one leaves it whole")
    func aSearchNarrowsTheSidebarsChoice() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        try newCard(card(.word, front: "Ubérrimo", back: "Muy fértil."), in: engine)
        let fecundo = try engine.create(
            card(.word, front: "Fecundo", back: "Fértil, que produce mucho."), deck: "Palabras")
        let serendipia = try engine.create(card(nil, front: "serendipia", back: "Un hallazgo."), deck: "Palabras")

        #expect(
            try engine.cardRows(in: .deck("Palabras"), matching: "fertil", with: scheduler).map(\.card.id) == [
                fecundo.id
            ])
        #expect(try engine.cardRows(in: .deck(Deck.defaultName), matching: "fecundo", with: scheduler).isEmpty)
        #expect(
            try engine.cardRows(in: .deck("Palabras"), matching: "  ", with: scheduler).map(\.card.id) == [
                fecundo.id, serendipia.id,
            ])
    }

    @Test("a flagged card keeps its progress but has no due time, since it won't show up until it's fixed")
    func aFlaggedCardHasNoDueTime() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        try newCard("ojalá", in: engine)
        try engine.climb(serendipia, goods: 2, movingForward: time)
        try engine.climb(ubuntu, goods: 2, movingForward: time)
        let serendipiaStanding = try engine.standing(of: serendipia.id, with: scheduler)
        let ubuntuStanding = try engine.standing(of: ubuntu.id, with: scheduler)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))

        let rows = try engine.cardRows(in: .all, with: scheduler)

        #expect(rows.map(\.frontFirst.standing) == [serendipiaStanding, ubuntuStanding, .new])
        #expect(rows.map(\.frontFirst.due) == [serendipiaStanding.due, nil, nil])
    }

    // A flagged card waits in its deck, where a search finds it as it finds
    // any card.
    @Test("a search in a deck finds its flagged cards by their front, back or source", .bug(id: 540))
    func aSearchFindsAFlaggedCardInItsDeck() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let deck = CardGroup.deck(Deck.defaultName)
        let uberrimo = try newCard(card(.word, front: "Ubérrimo", back: "Muy fértil y abundante."), in: engine)
        let estoicismo = try newCard(
            card(
                .concept, front: "Estoicismo", back: "Aceptar lo que no depende de uno.", source: "Meditaciones"),
            in: engine)
        try newCard("ubuntu", in: engine)
        try engine.flag(uberrimo.id, note: note("Falta un ejemplo"))
        try engine.flag(estoicismo.id, note: note("El dorso es confuso"))

        #expect(try engine.cardRows(in: deck, matching: "uberrimo", with: scheduler).map(\.card.id) == [uberrimo.id])
        #expect(try engine.cardRows(in: deck, matching: "fertil", with: scheduler).map(\.card.id) == [uberrimo.id])
        #expect(
            try engine.cardRows(in: deck, matching: "meditaciones", with: scheduler).map(\.card.id) == [estoicismo.id])
    }
}
