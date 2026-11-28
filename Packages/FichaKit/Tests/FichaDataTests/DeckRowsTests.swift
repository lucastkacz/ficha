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
    // Friday or Saturday, the 17th. Lenguaje, met in full, came in with Arte,
    // so it keeps its place in the queue after Arte, by name, and ahead of
    // Historia. Música is set aside, and Geografía has no card.
    @Test(
        "each deck's row says how far it is and when it's all met, Next for a deck waiting its turn, and whether it's set aside, met in full or empty, while a deck inside another says nothing",
        .bug(id: 491))
    func eachDecksRowSaysWhereItIs() throws {
        time.move(to: try morning(of: 13, in: calendar))
        try engine.meet(try newCardInDeck("ubuntu", deck: "Lenguaje", in: engine))
        try engine.meet(try newCardInDeck("Bach", deck: "Música", in: engine))
        try newCardInDeck("Piazzolla", deck: "Música", in: engine)
        try engine.meet(try newCardInDeck("La Gioconda", deck: "Arte", in: engine))
        try newCardInDeck("Las Meninas", deck: "Arte", in: engine)
        let grito = try newCardInDeck("El Grito", deck: "Arte", in: engine)
        try newCardInDeck("La ronda de noche", deck: "Arte::Barroco", in: engine)
        time.move(to: try morning(of: 14, in: calendar))
        try engine.bury(grito.id)
        try engine.setAside(deck: "Música")
        try newCardInDeck("Coliseo", deck: "Historia", in: engine)
        try newCardInDeck("Partenón", deck: "Historia", in: engine)
        time.advance(by: minutes(1))
        try newCardInDeck("serendipia", in: engine)
        try engine.makeDeck(named: "Geografía")

        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        #expect(
            window.deckRows.map(\.id) == [Deck.defaultName, "Arte", "Lenguaje", "Historia", "Geografía", "Música"])
        #expect(
            try window.deckRows.map(\.line) == [
                .next(finish: .dayOrNext(.weekday(start(of: 16, 10)), .weekday(start(of: 17, 10)))),
                .first(met: 1, of: 4, finish: .day(.today)),
                .metThemAll(cards: 1, days: 1),
                .next(finish: .dayOrNext(.tomorrow, .weekday(start(of: 16, 10)))),
                .noCards,
                .setAside(met: 1, of: 2),
            ])
        #expect(window.deckRows.first { $0.id == "Arte" }?.children.map(\.line) == [nil])
    }

    // Zoología's first card came in the day before Arte's, so it goes first
    // in the queue, though Arte comes first alphabetically. Botánica's one
    // card came in a minute after Zoología's and is met, so the deck keeps
    // its place between them. Geografía has no card, and Cocina is set
    // aside. Put first, Arte takes Zoología's place and Zoología Arte's, as
    // `ficha deck queue --first` saves them, and Botánica keeps its own.
    @Test(
        "the sidebar lists the decks at the top of the tree with cards in the user's reviews in the order of their places in the queue, one met in full at its own, then the others alphabetically, and those set aside last, each with the decks inside it alphabetically",
        .bug(id: 491))
    func theDecksAreListedByTheirPlacesInTheQueue() throws {
        time.move(to: try morning(of: 13, in: calendar))
        try newCardInDeck("tiburón", deck: "Zoología::Mar", in: engine)
        try newCardInDeck("abeja", deck: "Zoología::Aire", in: engine)
        try newCardInDeck("asado", deck: "Cocina", in: engine)
        try engine.setAside(deck: "Cocina")
        time.advance(by: minutes(1))
        try engine.meet(try newCardInDeck("rosa", deck: "Botánica", in: engine))
        time.move(to: try morning(of: 14, in: calendar))
        try newCardInDeck("La Gioconda", deck: "Arte", in: engine)
        try engine.makeDeck(named: "Geografía")
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        let byTheQueue = window.deckRows

        try engine.moveInQueue(deck: "Arte", to: .first)
        window.read(with: scheduler)

        #expect(byTheQueue.map(\.id) == ["Zoología", "Botánica", "Arte", "Geografía", "Cocina"])
        #expect(byTheQueue.first?.children.map(\.title) == ["Aire", "Mar"])
        #expect(byTheQueue.first { $0.id == "Botánica" }?.line == .metThemAll(cards: 1, days: 1))
        #expect(window.deckRows.map(\.id) == ["Arte", "Botánica", "Zoología", "Geografía", "Cocina"])
    }

    // Botánica's one card came in the day before and is met, and Zoología's
    // came in a minute after it. Música's one card came in this morning, and
    // it's a priority deck, so its new card comes first and the queue lists
    // it first, while Botánica, met in full, keeps its place, ahead of
    // Zoología. Once Bach is met, Música is met in full too, and goes back
    // to its own place, after Zoología.
    @Test(
        "the sidebar lists a deck whose new cards are all priority cards first while they come first, as the queue lists it, one met in full at its place among the others, and the priority deck at its own once its new cards are met",
        .bug(id: 491))
    func aPriorityDeckIsListedFirstWhileItsNewCardsComeFirst() throws {
        time.move(to: try morning(of: 13, in: calendar))
        try engine.meet(try newCardInDeck("rosa", deck: "Botánica", in: engine))
        time.advance(by: minutes(1))
        try newCardInDeck("tiburón", deck: "Zoología", in: engine)
        time.move(to: try morning(of: 14, in: calendar))
        let bach = try newCardInDeck("Bach", deck: "Música", in: engine)
        try engine.setPriority(true, ofDeck: "Música")
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        let beforeBach = window.deckRows
        let queue = try engine.queue(.defaults).map(\.deck)

        try engine.meet(bach)
        window.read(with: scheduler)

        #expect(queue == ["Música", "Zoología"])
        #expect(beforeBach.map(\.id) == ["Música", "Botánica", "Zoología"])
        #expect(
            beforeBach.map(\.line) == [
                .first(met: 0, of: 1, finish: .day(.today)),
                .metThemAll(cards: 1, days: 1),
                .next(finish: .day(.today)),
            ])
        #expect(window.deckRows.map(\.id) == ["Botánica", "Zoología", "Música"])
        #expect(
            window.deckRows.map(\.line) == [
                .metThemAll(cards: 1, days: 1),
                .first(met: 0, of: 1, finish: .day(.today)),
                .metThemAll(cards: 1, days: 1),
            ])
    }

    // ubuntu goes both ways, and its front-first way was met the day before,
    // so its back-first way is still to come: Lenguaje, whose one card is
    // met, stays in the queue until that way is met too.
    @Test(
        "a deck's row says it's met them all once the queue no longer has it, as the review panel says it, and not while a card's back-first way is still to come",
        .bug(id: 491))
    func aDeckIsMetInFullWithItsBackFirstWays() throws {
        time.move(to: try morning(of: 13, in: calendar))
        let ubuntu = try newCardInDeck("ubuntu", deck: "Lenguaje", in: engine)
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
        try newCardInDeck("La Gioconda", deck: "Arte", in: engine)
        time.move(to: try morning(of: 14, in: calendar))
        var settings = ReviewSettings.defaults
        settings.activeHours = try #require(ActiveHours(from: 6, to: 9))
        var window = engine.openCardsWindow(with: scheduler, activeHours: settings.activeHours)
        window.read(with: scheduler)
        let overForToday = window.deckRows.first { $0.id == "Arte" }?.line
        let queued = try #require(try engine.queue(settings).first?.finish)
        let queuedWording = queued.wording(now: time.now, dayStartsAtHour: settings.dayStartsAtHour, calendar: calendar)

        window.read(with: scheduler, activeHours: ReviewSettings.defaults.activeHours)

        #expect(overForToday == .first(met: 0, of: 1, finish: queuedWording))
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
        let (friday, saturday) = (try start(of: 16, 10), try start(of: 17, 10))
        let (monday, tuesday) = (try start(of: 19, 10), try start(of: 20, 10))
        #expect(try wording(start(of: 14, 10), start(of: 14, 10)) == .day(.today))
        #expect(wording(friday, friday) == .day(.weekday(friday)))
        #expect(try wording(start(of: 14, 10), start(of: 15, 10)) == .dayOrNext(.today, .tomorrow))
        #expect(try wording(start(of: 15, 10), friday) == .dayOrNext(.tomorrow, .weekday(friday)))
        #expect(wording(friday, monday) == .days(.weekday(friday), to: .weekday(monday)))
        #expect(wording(saturday, tuesday) == .days(.weekday(saturday), to: .weekday(tuesday)))
        #expect(calendar.component(.weekday, from: friday) == 6)
        #expect(try wording(saturday, start(of: 21, 10)) == .thirds(.mid, to: third(.late, of: 21, 10)))
        #expect(try wording(start(of: 22, 10), start(of: 31, 10)) == .third(third(.late, of: 31, 10)))
        #expect(try wording(start(of: 1, 11), start(of: 10, 11)) == .third(third(.early, of: 10, 11)))
        #expect(try wording(start(of: 11, 11), start(of: 20, 11)) == .third(third(.mid, of: 20, 11)))
        #expect(try wording(start(of: 10, 11), start(of: 11, 11)) == .thirds(.early, to: third(.mid, of: 11, 11)))
        #expect(
            try wording(start(of: 28, 10), start(of: 5, 11))
                == .months(third(.late, of: 28, 10), to: third(.early, of: 5, 11)))
        #expect(
            try wording(start(of: 28, 12), start(of: 6, 1, 2027))
                == .months(third(.late, of: 28, 12), to: MonthThird(.early, of: start(of: 6, 1, 2027))))
    }

    /// The third `third` of the month, as a finish date reads it, with the
    /// day `day` of the month `month` of 2026, in Buenos Aires.
    private func third(_ third: FinishDate.Wording.Third, of day: Int, _ month: Int) throws -> MonthThird {
        MonthThird(third, of: try start(of: day, month))
    }

    /// How the finish date from `soonest` to `latest` reads now.
    private func wording(_ soonest: Date, _ latest: Date) -> FinishDate.Wording {
        FinishDate(soonest: soonest, latest: latest).wording(
            now: time.now, dayStartsAtHour: ReviewSettings.defaults.dayStartsAtHour, calendar: calendar)
    }

    /// The start of the day `day` of the month `month` of `year`, in Buenos
    /// Aires.
    private func start(of day: Int, _ month: Int, _ year: Int = 2026) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
