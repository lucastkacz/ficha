import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on what the Cards window lists: Lucas's cards, each with where it
/// stands with his scheduling settings and when he last saw it, and what
/// waits in his inbox.
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

        let rows = try engine.cardRows(in: .all, with: ReviewSettings.defaults.scheduler)

        #expect(rows.map(\.card.id) == [serendipia.id, ubuntu.id])
        #expect(rows.map(\.card.flag?.note) == [nil, "Falta un ejemplo"])
    }

    @Test(
        "each card stands as the scheduling settings Lucas set space it, with its interval, and was last seen at its latest answer"
    )
    func eachCardStandsAsLucassSettingsSpaceIt() throws {
        // Learning steps of 10 minutes and 6 hours.
        var settings = ReviewSettings.defaults
        settings.scheduler = try #require(
            settings.scheduler.replacing(learningSteps: [.seconds(minutes(10)), .seconds(hours(6))]))
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
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

    // The Interval and Back-first interval columns sort by it in the app's
    // `CardRowOrder`, since a table's order stays in the app.
    @Test("the Cards window's rows sort by interval, shortest first, new ways first")
    func theRowsSortByIntervalNewWaysFirst() throws {
        let ojala = try approveCard("ojalá", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [ojala.id, petricor.id, ubuntu.id])
        // ojalá waits 21 days or more front first, and is new back first.
        try engine.climbUntilLearned(ojala, movingForward: time)
        // ubuntu is on the first learning step, 1 hour, both ways.
        try engine.meet(ubuntu)
        try engine.meet(ubuntu, way: .backFirst)
        // petricor is on the second, 4 hours, both ways.
        try engine.climb(petricor, goods: 1, movingForward: time)
        try engine.climb(petricor, goods: 1, way: .backFirst, movingForward: time)

        let rows = try engine.cardRows(in: .all, with: ReviewSettings.defaults.scheduler)
        let frontFirst = rows.sorted(using: KeyPathComparator(\.frontFirst.intervalToSortBy))
        let backFirst = rows.filter { $0.backFirst != nil }.sorted { lhs, rhs in
            (lhs.backFirst?.intervalToSortBy ?? .zero) < (rhs.backFirst?.intervalToSortBy ?? .zero)
        }

        #expect(frontFirst.map(\.card.front) == ["serendipia", "ubuntu", "petricor", "ojalá"])
        #expect(backFirst.map(\.card.front) == ["ojalá", "ubuntu", "petricor"])
    }

    @Test("New, Due and Learned list the cards in Lucas's reviews only, as the menu counts them")
    func newDueAndLearnedListCardsInReviews() throws {
        let settings = ReviewSettings.defaults
        // Learned: graduated, waiting 21 days or more.
        let ojala = try approveCard("ojalá", in: engine)
        try engine.climbUntilLearned(ojala, movingForward: time)
        let nunca = try approveCard("nunca", in: engine)
        try engine.climbUntilLearned(nunca, movingForward: time)
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

        let new = try engine.cardRows(in: .new, with: settings.scheduler)
        let due = try engine.cardRows(in: .due, with: settings.scheduler)
        let learned = try engine.cardRows(in: .learned, with: settings.scheduler)

        #expect(new.map(\.card.id) == [serendipia.id])
        #expect(due.map(\.card.id) == [ubuntu.id])
        #expect(learned.map(\.card.id) == [ojala.id])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.learned == 1)
        #expect(try engine.cardRows(in: .all, with: settings.scheduler).map(\.card.id).contains(efimero.id))
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
        try engine.climbUntilLearned(serendipia, way: .backFirst, movingForward: time)
        // ubuntu is learned front first, and due back first only.
        try engine.climbUntilLearned(ubuntu, movingForward: time)
        try engine.meet(ubuntu, way: .backFirst)
        // efímero is new back first only.
        try engine.meet(efimero)
        time.advance(by: hours(1))

        let new = try engine.cardRows(in: .new, with: settings.scheduler)
        let due = try engine.cardRows(in: .due, with: settings.scheduler)
        let learned = try engine.cardRows(in: .learned, with: settings.scheduler)

        #expect(new.map(\.card.id) == [ojala.id])
        #expect(due.map(\.card.id) == [ubuntu.id, serendipia.id, efimero.id])
        #expect(learned.map(\.card.id) == [ubuntu.id])
    }

    @Test("Flagged lists the flagged cards that aren't buried, and Buried every buried card, flagged ones too")
    func flaggedAndBuriedListTheirCards() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let ojala = try approveCard("ojalá", in: engine)
        try engine.bury(ojala.id)
        let acaso = try approveCard("acaso", in: engine)
        try engine.flag(acaso.id, note: note("El dorso es confuso"))
        try engine.bury(acaso.id)

        let flagged = try engine.cardRows(in: .flagged, with: scheduler)
        let buried = try engine.cardRows(in: .buried, with: scheduler)

        #expect(flagged.map(\.card.id) == [ubuntu.id])
        #expect(buried.map(\.card.id) == [ojala.id, acaso.id])
        #expect(buried.map(\.frontFirst.due) == [nil, nil])
    }

    @Test("a tag lists the cards that have it, and a type the cards of it, flagged ones too but not the buried ones")
    func aTagAndATypeListTheirCards() throws {
        let scheduler = ReviewSettings.defaults.scheduler
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

        #expect(try engine.cardRows(in: .tag("historia"), with: scheduler).map(\.card.id) == [mayo.id])
        #expect(
            try engine.cardRows(in: .tag("filosofía"), with: scheduler).map(\.card.id) == [ubuntu.id, descartes.id])
        #expect(try engine.cardRows(in: .type(.concept), with: scheduler).map(\.card.id) == [mayo.id])
        #expect(try engine.cardRows(in: .type(.word), with: scheduler).map(\.card.id) == [ubuntu.id, serendipia.id])
    }

    @Test("All Tags lists every tag of the cards, buried ones too, once each, alphabetically")
    func allTagsListsEveryTagOfTheCards() throws {
        try approve(card(.word, front: "Ubuntu", back: "Humanidad.", tags: ["lenguaje", "filosofía"]), in: engine)
        try approve(card(.concept, front: "Eudaimonía", back: "Vida plena.", tags: ["ética", "filosofía"]), in: engine)
        let mercantilismo = try approve(
            card(.concept, front: "Mercantilismo", back: "Acumular metales.", tags: ["economía", "historia"]),
            in: engine)
        try engine.bury(mercantilismo.id)
        try approveCard("serendipia", in: engine)

        #expect(try engine.allTags().map(\.name) == ["economía", "ética", "filosofía", "historia", "lenguaje"])
    }

    @Test("searching \"fertil\" finds a card whose back says \"fértil\", ignoring case and accents")
    func aSearchFindsTextInTheBackIgnoringCaseAndAccents() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let uberrimo = try approve(
            card(.word, front: "Ubérrimo", back: "Muy fértil y abundante: «una tierra ubérrima»."), in: engine)
        try approve(card(.word, front: "Estéril", back: "Que no da fruto."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "fertil", with: scheduler).map(\.card.id) == [uberrimo.id])
        #expect(try engine.cardRows(in: .all, matching: " UBERRIMO ", with: scheduler).map(\.card.id) == [uberrimo.id])
    }

    @Test("searching \"h2o\" finds a card that says \"H₂O\", and \"x²\" one that says \"x2\"")
    func aSearchIgnoresSuperscriptsAndSubscripts() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let water = try approve(card(.word, front: "H₂O", back: "El agua."), in: engine)
        let square = try approve(card(.question, front: "¿Cuánto es x2 si x es 3?", back: "9."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "h2o", with: scheduler).map(\.card.id) == [water.id])
        #expect(try engine.cardRows(in: .all, matching: "x²", with: scheduler).map(\.card.id) == [square.id])
    }

    @Test("a search finds text in a card's source")
    func aSearchFindsTextInTheSource() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let borges = try approve(
            card(
                .quote, front: "El tiempo es la sustancia de que estoy hecho.", back: "Jorge Luis Borges.",
                source: "Nueva refutación del tiempo"),
            in: engine)
        try approveCard("efímero", in: engine)

        #expect(try engine.cardRows(in: .all, matching: "refutacion", with: scheduler).map(\.card.id) == [borges.id])
    }

    @Test("searching \"ano\" doesn't find \"año\", since the ñ isn't an n with an accent")
    func aSearchKeepsTheEnye() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let anio = try approve(card(.word, front: "Año bisiesto", back: "El que tiene 366 días."), in: engine)

        #expect(try engine.cardRows(in: .all, matching: "ano", with: scheduler).isEmpty)
        #expect(try engine.cardRows(in: .all, matching: "AÑO", with: scheduler).map(\.card.id) == [anio.id])
    }

    @Test("a search narrows the sidebar's choice, and a blank one leaves it whole")
    func aSearchNarrowsTheSidebarsChoice() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        try approve(card(.word, front: "Ubérrimo", back: "Muy fértil.", tags: ["lenguaje"]), in: engine)
        let fecundo = try approve(card(.word, front: "Fecundo", back: "Fértil, que produce mucho."), in: engine)
        try engine.bury(fecundo.id)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.bury(serendipia.id)

        #expect(try engine.cardRows(in: .buried, matching: "fertil", with: scheduler).map(\.card.id) == [fecundo.id])
        #expect(try engine.cardRows(in: .tag("lenguaje"), matching: "fecundo", with: scheduler).isEmpty)
        #expect(
            try engine.cardRows(in: .buried, matching: "  ", with: scheduler).map(\.card.id) == [
                fecundo.id, serendipia.id,
            ])
    }

    @Test("a flagged card keeps its progress but has no due time, since it won't show up until it's fixed")
    func aFlaggedCardHasNoDueTime() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("ojalá", in: engine)
        try engine.climb(serendipia, goods: 2, movingForward: time)
        try engine.climb(ubuntu, goods: 2, movingForward: time)
        let serendipiaStanding = try engine.standing(of: serendipia.id, with: scheduler)
        let ubuntuStanding = try engine.standing(of: ubuntu.id, with: scheduler)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))

        let rows = try engine.cardRows(in: .all, with: scheduler)

        #expect(rows.map(\.frontFirst.standing) == [serendipiaStanding, ubuntuStanding, .new])
        #expect(rows.map(\.frontFirst.due) == [serendipiaStanding.due, nil, nil])
    }

    @Test(
        "the inbox lists the captures, the expansions and the flagged cards that aren't buried, the latest added first, as many as the menu counts"
    )
    func theInboxListsWhatWaitsToBeRefined() throws {
        let scheduler = ReviewSettings.defaults.scheduler
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

        let rows = try engine.inboxRows(with: scheduler)

        let expansion = try #require(try engine.inbox().expansions.first)
        let flagged = try #require(try engine.cardRows(in: .flagged, with: scheduler).first)
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
        let scheduler = ReviewSettings.defaults.scheduler
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

        #expect(try engine.inboxRows(matching: "OCKHAM", with: scheduler).map(\.text) == ["Navaja de Ockham"])
        #expect(try engine.inboxRows(matching: "filosofia", with: scheduler).map(\.text) == ["Navaja de Ockham"])
        #expect(try engine.inboxRows(matching: "uberrimo", with: scheduler).map(\.text) == ["Ubérrimo"])
        #expect(try engine.inboxRows(matching: "fertil", with: scheduler).map(\.text) == ["Ubérrimo"])
        #expect(try engine.inboxRows(matching: "meditaciones", with: scheduler).map(\.text) == ["Estoicismo"])
        #expect(
            try engine.inboxRows(matching: "  ", with: scheduler).map(\.text) == [
                "ubuntu", "Navaja de Ockham", "Estoicismo", "Ubérrimo",
            ])
    }
}
