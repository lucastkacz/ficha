import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the pace and the queue of decks new cards come from (ADR 0034):
/// the new cards a day, for every deck together, come from the first deck in
/// the queue alone, and each deck in the queue has a finish date. They start
/// at 9 in the morning of Wednesday the 14th in Buenos Aires, when active
/// hours start, on a new install, with Ficha's settings.
struct PaceAndQueueTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    @Test(
        "a new install starts at Steady, of Chill, Steady and Faster, 1, 2 and 4 new cards a day, with a desired retention of 85%",
        .bug(id: 490))
    func aNewInstallStartsAtSteady() throws {
        let progress = try engine.progressSettings()

        #expect(Pace.allCases.map(\.newCardsPerDay) == [1, 2, 4])
        #expect([1, 2, 4, 5].map { Pace(newCardsPerDay: $0) } == [.chill, .steady, .faster, nil])
        #expect(Pace(newCardsPerDay: progress.newCardsPerDay) == .steady)
        #expect(progress.scheduler.desiredRetention == 0.85)
        #expect(progress == settings.progress)
    }

    // Lenguaje's ubuntu was met the day before. Arte's three cards come in,
    // and Historia's one a minute later, so Arte goes ahead of it.
    @Test(
        "at Steady, new cards come from the first deck in the queue alone, 2 a day, until it has none left, and then from the next, while the cards already met keep coming from every deck",
        .bug(id: 490))
    func newCardsComeFromTheFirstDeckAlone() throws {
        time.move(to: try morning(of: 13, in: calendar))
        let ubuntu = try approveInDeck("ubuntu", deck: "Lenguaje", in: engine)
        try engine.meet(ubuntu)
        time.move(to: try morning(of: 14, in: calendar))
        let arte = try ["La Gioconda", "Las Meninas", "El Grito"].map {
            try approveInDeck($0, deck: "Arte", in: engine)
        }
        time.advance(by: minutes(1))
        let coliseo = try approveInDeck("Coliseo", deck: "Historia", in: engine)

        let firstDay = try meetEachNewCard()
        time.move(to: try morning(of: 15, in: calendar))
        let reviewsNextDay = try engine.reviewNow(settings).filter { !$0.isNew }.map(\.card.id)
        let secondDay = try meetEachNewCard()

        #expect(firstDay == arte.prefix(2).map(\.id))
        #expect(reviewsNextDay == [ubuntu.id] + arte.prefix(2).map(\.id))
        #expect(secondDay == [arte[2].id, coliseo.id])
    }

    // Each deck comes in a minute after the one before it; Arte::Barroco
    // comes in inside Arte.
    @Test(
        "a deck that comes in goes last in the queue, or first when asked, and can move to any place, while a deck inside another comes with it",
        .bug(id: 490))
    func aDeckThatComesInGoesLast() throws {
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        time.advance(by: minutes(1))
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        time.advance(by: minutes(1))
        try approveInDeck("Las Meninas", deck: "Arte::Barroco", in: engine)
        let withADeckInside = try queuedDecks()
        try approveInDeck("Bach", deck: "Música", in: engine)
        let lastIn = try queuedDecks()
        time.advance(by: minutes(1))
        let ubuntu = try approveInDeck("ubuntu", deck: "Lenguaje", in: engine)
        try engine.moveInQueue(deck: "Lenguaje", to: .first)
        let firstIn = try queuedDecks()
        let newCards = try engine.reviewNow(settings)
        try engine.moveInQueue(deck: "Lenguaje", to: .at(2))
        let third = try queuedDecks()
        try engine.moveInQueue(deck: "Arte", to: .last)

        #expect(withADeckInside == ["Arte", "Historia"])
        #expect(lastIn == ["Arte", "Historia", "Música"])
        #expect(firstIn == ["Lenguaje", "Arte", "Historia", "Música"])
        #expect(newCards == [.new(ubuntu)])
        #expect(third == ["Arte", "Historia", "Lenguaje", "Música"])
        #expect(try queuedDecks() == ["Historia", "Lenguaje", "Música", "Arte"])
    }

    // Each deck comes in a minute after the one before it.
    @Test(
        "a set-aside deck leaves the queue and comes back to its place, and a priority deck's new cards come first",
        .bug(id: 490))
    func aSetAsideDeckLeavesTheQueue() throws {
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        time.advance(by: minutes(1))
        let coliseo = try approveInDeck("Coliseo", deck: "Historia", in: engine)
        time.advance(by: minutes(1))
        let bach = try approveInDeck("Bach", deck: "Música::Barroco", in: engine)

        try engine.setAside(deck: "Arte")
        let setAside = try queuedDecks()
        let newWhileSetAside = try engine.reviewNow(settings)
        try engine.stopSettingAside(deck: "Arte")
        let back = try queuedDecks()
        try engine.setPriority(true, ofDeck: "Música::Barroco")

        #expect(setAside == ["Historia", "Música"])
        #expect(newWhileSetAside == [.new(coliseo)])
        #expect(back == ["Arte", "Historia", "Música"])
        #expect(try queuedDecks() == ["Música", "Arte", "Historia"])
        #expect(try engine.reviewNow(settings) == [.new(bach)])
    }

    // Nothing is met yet today, so today still brings 2 new cards: Arte's 3
    // are met tomorrow, the 15th, if every day has appearances, or by the
    // 16th if five days a week do; Historia's 4, after them, by the 17th, or
    // the 19th.
    @Test(
        "a deck's finish date is a range from the pace and the new cards of the decks ahead of it in the queue, and moves later as days go by without appearances",
        .bug(id: 490))
    func aDecksFinishDate() throws {
        for front in ["La Gioconda", "Las Meninas", "El Grito"] {
            try approveInDeck(front, deck: "Arte", in: engine)
        }
        time.advance(by: minutes(1))
        for front in ["Coliseo", "Partenón", "Machu Picchu", "Chichén Itzá"] {
            try approveInDeck(front, deck: "Historia", in: engine)
        }
        var faster = settings
        faster.newCardsPerDay = Pace.faster.newCardsPerDay
        var noNewCards = settings
        noNewCards.newCardsPerDay = 0

        let today = try engine.queue(settings)
        let atFaster = try engine.queue(faster)
        let withNoNewCards = try engine.queue(noNewCards)
        time.move(to: try morning(of: 17, in: calendar))

        #expect(
            try today == [
                QueuedDeck(deck: "Arte", newCards: 3, finish: finish(15, 16)),
                QueuedDeck(deck: "Historia", newCards: 4, finish: finish(17, 19)),
            ])
        #expect(
            try atFaster == [
                QueuedDeck(deck: "Arte", newCards: 3, finish: finish(14, 14)),
                QueuedDeck(deck: "Historia", newCards: 4, finish: finish(15, 16)),
            ])
        #expect(withNoNewCards.map(\.finish) == [nil, nil])
        #expect(
            try engine.queue(settings) == [
                QueuedDeck(deck: "Arte", newCards: 3, finish: finish(18, 19)),
                QueuedDeck(deck: "Historia", newCards: 4, finish: finish(20, 22)),
            ])
    }

    /// The decks in the queue now, first to last, by name.
    private func queuedDecks() throws -> [String] {
        try engine.queue(settings).map(\.deck)
    }

    /// Meets each new card review now brings, one after another, until it
    /// brings none, and returns their ids in that order.
    private func meetEachNewCard() throws -> [Int64] {
        var met: [Int64] = []
        while met.count < 10, let new = try engine.reviewNow(settings).first(where: \.isNew) {
            try engine.meet(new.card)
            met.append(new.card.id)
        }
        return met
    }

    /// A finish date from the start of the day `soonest` of October 2026 to
    /// the start of the day `latest`, in Buenos Aires.
    private func finish(_ soonest: Int, _ latest: Int) throws -> FinishDate {
        func start(of day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day)))
        }
        return FinishDate(soonest: try start(of: soonest), latest: try start(of: latest))
    }
}

extension PanelCard {
    /// Whether the review panel brings the card's way new.
    fileprivate var isNew: Bool {
        if case .new = self { true } else { false }
    }
}
