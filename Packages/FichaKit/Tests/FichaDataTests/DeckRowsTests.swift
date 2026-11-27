import FichaCore
import FichaData
import Foundation
import Testing

/// A third of a month, as a finish date reads.
private typealias MonthThird = FinishDate.Wording.MonthThird

/// Tests on what each deck's row says under its title in the Cards window's
/// sidebar (#491), from where the deck stands and the queue new cards come
/// from (ADR 0034), and on how a finish date reads, into an engine in memory.
/// They start at 9 in the morning of Wednesday the 14th of October in Buenos
/// Aires, when active hours start, on a new install, at Steady.
struct DeckRowsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // The day before, ubuntu, Bach and La Gioconda were met, so today still
    // brings 2 new cards. Arte has 2 new cards in the reviews, one of them
    // in Arte::Barroco, and El Grito buried, which counts among its 4 cards:
    // it's all met today. Historia's 2, after it, are met tomorrow or Friday,
    // the 16th, and Default's serendipia, which came in a minute after them,
    // Friday or Saturday, the 17th. Música is set aside, and Geografía has no
    // card.
    @Test(
        "each deck's row says how far it is and when it's all met, Next for a deck waiting its turn, and whether it's set aside, met in full or empty, while a deck inside another says nothing",
        .bug(id: 491))
    func eachDecksRowSaysWhereItIs() throws {
        time.move(to: try morning(of: 13, in: calendar))
        try engine.meet(try approveInDeck("ubuntu", deck: "Lenguaje", in: engine))
        try engine.meet(try approveInDeck("Bach", deck: "Música", in: engine))
        try approveInDeck("Piazzolla", deck: "Música", in: engine)
        try engine.meet(try approveInDeck("La Gioconda", deck: "Arte", in: engine))
        try approveInDeck("Las Meninas", deck: "Arte", in: engine)
        let grito = try approveInDeck("El Grito", deck: "Arte", in: engine)
        try approveInDeck("La ronda de noche", deck: "Arte::Barroco", in: engine)
        time.move(to: try morning(of: 14, in: calendar))
        try engine.bury(grito.id)
        try engine.setAside(deck: "Música")
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        try approveInDeck("Partenón", deck: "Historia", in: engine)
        time.advance(by: minutes(1))
        try approveInDeck("serendipia", in: engine)
        try engine.makeDeck(named: "Geografía")

        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        #expect(
            window.deckRows.map(\.id) == [Deck.defaultName, "Arte", "Historia", "Geografía", "Lenguaje", "Música"])
        #expect(
            window.deckRows.map(\.line) == [
                .next(finish: .dayOrNext(.weekday(6), .weekday(7))),
                .first(met: 1, of: 4, finish: .day(.today)),
                .next(finish: .dayOrNext(.tomorrow, .weekday(6))),
                .noCards,
                .metThemAll(cards: 1, days: 1),
                .setAside(met: 1, of: 2),
            ])
        #expect(window.deckRows.first { $0.id == "Arte" }?.children.map(\.line) == [nil])
    }

    // Zoología's first card came in the day before Arte's, so it goes first
    // in the queue, though Arte comes first alphabetically. Botánica's one
    // card is met, Geografía has none, and Cocina is set aside.
    @Test(
        "the sidebar lists the decks at the top of the tree in the queue's order, the one new cards come from now first, then the others alphabetically, and those set aside last, each with the decks inside it alphabetically",
        .bug(id: 491))
    func theDecksAreListedInTheQueuesOrder() throws {
        time.move(to: try morning(of: 13, in: calendar))
        try approveInDeck("tiburón", deck: "Zoología::Mar", in: engine)
        try approveInDeck("abeja", deck: "Zoología::Aire", in: engine)
        try engine.meet(try approveInDeck("rosa", deck: "Botánica", in: engine))
        try approveInDeck("asado", deck: "Cocina", in: engine)
        try engine.setAside(deck: "Cocina")
        time.move(to: try morning(of: 14, in: calendar))
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        try engine.makeDeck(named: "Geografía")
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        let byTheQueue = window.deckRows

        try engine.moveInQueue(deck: "Arte", to: .first)
        window.read(with: scheduler)

        #expect(byTheQueue.map(\.id) == ["Zoología", "Arte", "Botánica", "Geografía", "Cocina"])
        #expect(byTheQueue.first?.children.map(\.title) == ["Aire", "Mar"])
        #expect(window.deckRows.map(\.id) == ["Arte", "Zoología", "Botánica", "Geografía", "Cocina"])
    }

    // ubuntu goes both ways, and its front-first way was met the day before,
    // so its back-first way is still to come: Lenguaje, whose one card is
    // met, stays in the queue until that way is met too.
    @Test(
        "a deck's row says it's met them all once the queue no longer has it, as the review panel says it, and not while a card's back-first way is still to come",
        .bug(id: 491))
    func aDeckIsMetInFullWithItsBackFirstWays() throws {
        time.move(to: try morning(of: 13, in: calendar))
        let ubuntu = try approveInDeck("ubuntu", deck: "Lenguaje", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id])
        try engine.meet(ubuntu)
        time.move(to: try morning(of: 14, in: calendar))
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        let beforeBackFirst = window.deckRows.first { $0.id == "Lenguaje" }?.line

        try engine.meet(ubuntu, way: .backFirst)
        window.read(with: scheduler)

        #expect(beforeBackFirst == .first(met: 1, of: 1, finish: .day(.today)))
        #expect(window.deckRows.first { $0.id == "Lenguaje" }?.line == .metThemAll(cards: 1, days: 2))
    }

    // La Gioconda came in the day before. At 9 in the morning, active hours
    // that end at 9 bring no new card today, and those that end at 22 bring
    // it today.
    @Test(
        "a deck's finish date counts today's new cards by the active hours the window is given, those in Settings, as the review panel's queue counts them",
        .bug(id: 491))
    func aFinishDateCountsTodayByTheActiveHours() throws {
        time.move(to: try morning(of: 13, in: calendar))
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        time.move(to: try morning(of: 14, in: calendar))
        var settings = ReviewSettings.defaults
        settings.activeHours = 6..<9
        var window = engine.openCardsWindow(with: scheduler, activeHours: settings.activeHours)
        window.read(with: scheduler)
        let overForToday = window.deckRows.first { $0.id == "Arte" }?.line
        let queued = try #require(try engine.queue(settings).first?.finish)

        window.read(with: scheduler, activeHours: ReviewSettings.defaults.activeHours)

        #expect(overForToday == .first(met: 0, of: 1, finish: queued.wording(now: time.now, calendar: calendar)))
        #expect(overForToday != .first(met: 0, of: 1, finish: .day(.today)))
        #expect(window.deckRows.first { $0.id == "Arte" }?.line == .first(met: 0, of: 1, finish: .day(.today)))
    }

    // The Wednesday the 14th is today; the 20th, a Tuesday, is the last day
    // less than 7 days from today's start. Days 1 to 10 of a month are its
    // early third, 11 to 20 its mid third, and 21 on its late third.
    @Test(
        "a finish date reads by its days within the week, as one day, two days in a row with or, or a range with to, and further on by the thirds of its months",
        .bug(id: 491))
    func aFinishDateReadsByItsDaysOrItsThirds() throws {
        #expect(try wording(start(of: 14, 10), start(of: 14, 10)) == .day(.today))
        #expect(try wording(start(of: 16, 10), start(of: 16, 10)) == .day(.weekday(6)))
        #expect(try wording(start(of: 14, 10), start(of: 15, 10)) == .dayOrNext(.today, .tomorrow))
        #expect(try wording(start(of: 15, 10), start(of: 16, 10)) == .dayOrNext(.tomorrow, .weekday(6)))
        #expect(try wording(start(of: 16, 10), start(of: 19, 10)) == .days(.weekday(6), to: .weekday(2)))
        #expect(try wording(start(of: 17, 10), start(of: 20, 10)) == .days(.weekday(7), to: .weekday(3)))
        #expect(try wording(start(of: 17, 10), start(of: 21, 10)) == .thirds(.mid, to: MonthThird(.late, month: 10)))
        #expect(try wording(start(of: 22, 10), start(of: 31, 10)) == .third(MonthThird(.late, month: 10)))
        #expect(try wording(start(of: 1, 11), start(of: 10, 11)) == .third(MonthThird(.early, month: 11)))
        #expect(try wording(start(of: 11, 11), start(of: 20, 11)) == .third(MonthThird(.mid, month: 11)))
        #expect(
            try wording(start(of: 10, 11), start(of: 11, 11)) == .thirds(.early, to: MonthThird(.mid, month: 11)))
        #expect(
            try wording(start(of: 28, 10), start(of: 5, 11))
                == .months(MonthThird(.late, month: 10), to: MonthThird(.early, month: 11)))
        #expect(
            try wording(start(of: 28, 12), start(of: 6, 1, 2027))
                == .months(MonthThird(.late, month: 12), to: MonthThird(.early, month: 1)))
    }

    /// How the finish date from `soonest` to `latest` reads now.
    private func wording(_ soonest: Date, _ latest: Date) -> FinishDate.Wording {
        FinishDate(soonest: soonest, latest: latest).wording(now: time.now, calendar: calendar)
    }

    /// The start of the day `day` of the month `month` of `year`, in Buenos
    /// Aires.
    private func start(of day: Int, _ month: Int, _ year: Int = 2026) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
