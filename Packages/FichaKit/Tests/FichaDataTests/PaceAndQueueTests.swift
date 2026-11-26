import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the pace and the queue of decks new cards come from (ADR 0034):
/// the new cards a day, for every deck together, come from the first deck in
/// the queue alone, and each deck in the queue has a finish date. They start
/// at 9 in the morning of Wednesday the 14th in Buenos Aires, when active
/// hours start, on a new install, with Ficha's settings.
/// `mockups/tools/check-engine.js` copies some of these cases into the web
/// mocks' toy engine: run it after changing one (`mockups/README.md`).
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

    // Lenguaje's ubuntu was met the day before. Two of Arte's cards come in,
    // Historia's one a minute later, and Arte's third a minute after that:
    // Arte came in first, so all its cards go ahead of Historia's.
    @Test(
        "at Steady, new cards come from the first deck in the queue alone, 2 a day, until it has none left, and then from the next, while the cards already met keep coming from every deck",
        .bug(id: 490))
    func newCardsComeFromTheFirstDeckAlone() throws {
        time.move(to: try morning(of: 13, in: calendar))
        let ubuntu = try approveInDeck("ubuntu", deck: "Lenguaje", in: engine)
        try engine.meet(ubuntu)
        time.move(to: try morning(of: 14, in: calendar))
        var arte = try ["La Gioconda", "Las Meninas"].map { try approveInDeck($0, deck: "Arte", in: engine) }
        time.advance(by: minutes(1))
        let coliseo = try approveInDeck("Coliseo", deck: "Historia", in: engine)
        time.advance(by: minutes(1))
        arte.append(try approveInDeck("El Grito", deck: "Arte", in: engine))

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
    // 16th if five days in seven do; Historia's 4, after them, by the 17th,
    // or the 19th.
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

    // La Gioconda goes both ways, so its back-first way, still to come,
    // counts beside it: Arte has 3 new ways, of which today brings 2 at
    // Steady, and the last tomorrow, the 15th; at Faster, all 3 today. Met
    // front first, it leaves its back-first way and Las Meninas, and today
    // still brings 1 at Steady, 3 at Faster. At 22:00, when active hours
    // end, today brings none.
    @Test(
        "a deck's finish date counts a card's back-first way still to come and the new cards met today, and today brings none once active hours are over",
        .bug(id: 490))
    func aDecksFinishDateCountsWhatTodayStillBrings() throws {
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        try approveInDeck("Las Meninas", deck: "Arte", in: engine)
        let bothWays = try #require(try engine.setBothWays(true, of: [gioconda.id]).first)
        var faster = settings
        faster.newCardsPerDay = Pace.faster.newCardsPerDay

        let beforeMeetingIt = try engine.queue(settings)
        let beforeMeetingItAtFaster = try engine.queue(faster)
        try engine.meet(bothWays)
        let afterMeetingIt = try engine.queue(settings)
        let afterMeetingItAtFaster = try engine.queue(faster)
        time.advance(by: hours(13))

        #expect(try beforeMeetingIt == [QueuedDeck(deck: "Arte", newCards: 3, finish: finish(15, 16))])
        #expect(try beforeMeetingItAtFaster == [QueuedDeck(deck: "Arte", newCards: 3, finish: finish(14, 14))])
        #expect(try afterMeetingIt == [QueuedDeck(deck: "Arte", newCards: 2, finish: finish(15, 16))])
        #expect(try afterMeetingItAtFaster == [QueuedDeck(deck: "Arte", newCards: 2, finish: finish(14, 14))])
        #expect(try engine.queue(faster) == [QueuedDeck(deck: "Arte", newCards: 2, finish: finish(15, 16))])
    }

    // Música, Historia and Arte come in at once, as an import's decks do.
    @Test("decks that came in at once go in the queue by name, and a move parts them", .bug(id: 490))
    func decksThatCameInAtOnceGoByName() throws {
        for deck in ["Música", "Historia", "Arte"] {
            try approveInDeck("Una de \(deck)", deck: deck, in: engine)
        }
        let atOnce = try queuedDecks()
        try engine.moveInQueue(deck: "Música", to: .at(1))

        #expect(atOnce == ["Arte", "Historia", "Música"])
        #expect(try queuedDecks() == ["Arte", "Música", "Historia"])
    }

    // Arte, Biología and Música come in at once, as an import's decks do,
    // and Historia a minute later. Historia moves last, where it is, while
    // Música is set aside, so the move passes no deck: back, Música goes
    // between Biología and Historia again.
    @Test("a move that passes no deck changes no place, not even of decks that came in at once", .bug(id: 490))
    func aMoveThatPassesNoDeckChangesNoPlace() throws {
        for deck in ["Arte", "Biología", "Música"] {
            try approveInDeck("Una de \(deck)", deck: deck, in: engine)
        }
        time.advance(by: minutes(1))
        try approveInDeck("Coliseo", deck: "Historia", in: engine)

        try engine.setAside(deck: "Música")
        try engine.moveInQueue(deck: "Historia", to: .last)
        try engine.stopSettingAside(deck: "Música")

        #expect(try queuedDecks() == ["Arte", "Biología", "Música", "Historia"])
    }

    // Arte, Biología, Historia and Música come in at once, and Música is set
    // aside. Arte moves after Biología, which goes a second earlier, so
    // Historia keeps its place: back, Música goes last again.
    @Test("a move among decks that came in at once parts those it passes, not the deck after them", .bug(id: 490))
    func aMoveAmongDecksThatCameInAtOncePartsThoseItPasses() throws {
        for deck in ["Arte", "Biología", "Historia", "Música"] {
            try approveInDeck("Una de \(deck)", deck: deck, in: engine)
        }

        try engine.setAside(deck: "Música")
        try engine.moveInQueue(deck: "Arte", to: .at(1))
        try engine.stopSettingAside(deck: "Música")

        #expect(try queuedDecks() == ["Biología", "Arte", "Historia", "Música"])
    }

    // Arte, Biología, Historia and Música come in at once. Biología moves
    // after Historia, with Arte before them and Música after, both at their
    // place, so Música goes later too.
    @Test("a move with decks at one place on either side parts the decks after it too", .bug(id: 490))
    func aMoveWithDecksAtOnePlaceOnEitherSidePartsTheDecksAfterIt() throws {
        for deck in ["Arte", "Biología", "Historia", "Música"] {
            try approveInDeck("Una de \(deck)", deck: deck, in: engine)
        }

        try engine.moveInQueue(deck: "Biología", to: .at(2))

        #expect(try queuedDecks() == ["Arte", "Historia", "Biología", "Música"])
    }

    // Historia comes in first, with 2 cards; then Arte, with 1 in
    // Arte::Barroco, a priority deck, and 2 in Arte::Renacimiento; then
    // Música, a priority deck at the top, each a minute after the one
    // before. The priority cards come first, Arte's ahead, then Historia's,
    // and then Arte's others, 2 a day. Arte passes Historia alone, so once
    // Música is a priority deck no more, it goes last, where it came in.
    @Test(
        "a priority deck at the top goes first in the queue, a deck with one inside it where its other new cards come, and a move counts places as the queue lists them, leaving a priority deck's place alone",
        .bug(id: 490))
    func priorityDecksInTheQueue() throws {
        for front in ["Coliseo", "Partenón"] {
            try approveInDeck(front, deck: "Historia", in: engine)
        }
        time.advance(by: minutes(1))
        try approveInDeck("Las Meninas", deck: "Arte::Barroco", in: engine)
        for front in ["La Gioconda", "El nacimiento de Venus"] {
            try approveInDeck(front, deck: "Arte::Renacimiento", in: engine)
        }
        time.advance(by: minutes(1))
        try approveInDeck("Bach", deck: "Música", in: engine)
        try engine.setPriority(true, ofDeck: "Arte::Barroco")
        try engine.setPriority(true, ofDeck: "Música")

        let queue = try engine.queue(settings)
        try engine.moveInQueue(deck: "Arte", to: .at(1))
        let moved = try queuedDecks()
        try engine.setPriority(false, ofDeck: "Música")

        #expect(
            try queue == [
                QueuedDeck(deck: "Música", newCards: 1, finish: finish(14, 14)),
                QueuedDeck(deck: "Historia", newCards: 2, finish: finish(15, 16)),
                QueuedDeck(deck: "Arte", newCards: 3, finish: finish(16, 17)),
            ])
        #expect(moved == ["Música", "Arte", "Historia"])
        #expect(try queuedDecks() == ["Arte", "Historia", "Música"])
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
