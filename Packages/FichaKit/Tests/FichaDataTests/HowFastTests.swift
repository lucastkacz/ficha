import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on How fast? (ADR 0034, #491), the sheet over the Cards window that
/// asks for the pace as a deck comes in, and where the deck goes in the queue
/// new cards come from, with files the tests write in a folder of their own,
/// into an engine in memory. They start at 9 in the morning of Wednesday the
/// 14th in Buenos Aires, when active hours start, on a new install, at
/// Steady, as `PaceAndQueueTests` do.
final class HowFastTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults
    let scheduler = ReviewSettings.defaults.scheduler
    /// A folder of the test's own, for the decks' `.ficha`s it opens.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaHowFastTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    /// Historia's three cards, as the text file of a deck's `.ficha`, with a
    /// Deck column.
    let historia = """
        #separator:tab
        #html:false
        #columns:Front\tBack\tDeck
        Coliseo\tEn Roma.\tHistoria
        Partenón\tEn Atenas.\tHistoria
        Machu Picchu\tEn Perú.\tHistoria

        """

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // The user is meeting Arte: La Gioconda was met now, so today brings 1
    // more new card at Steady. Historia's .ficha opens a minute later, so its
    // deck would come in last. Another Ficha adds the same deck on the same
    // clock, and `ficha` then sets its pace and moves it: what the window's
    // Start must match.
    @Test(
        "How fast?, for a deck's .ficha that comes in behind a deck the user is meeting, says when it's all met at each pace, where it is and, ticked, first, and Start with Faster and Put it first adds it and sets the pace and the deck's place as ficha pace and ficha deck queue --first do",
        .bug(id: 491), .bug(id: 542))
    func startSetsThePaceAndPutsTheDeckFirst() async throws {
        let ficha = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try meetArte(in: engine)
        try meetArte(in: ficha)
        time.advance(by: minutes(1))
        let historiaFile = try writeDeck("Historia.ficha", historia)
        var window = openWindow()
        await window.openDeckAndWait(historiaFile)
        try await ficha.addDeck(at: historiaFile)
        let whereItIs = try Pace.allCases.map { try finish(of: "Historia", at: $0, in: ficha) }
        let wordings = whereItIs.map {
            $0?.wording(now: time.now, dayStartsAtHour: settings.dayStartsAtHour, calendar: calendar)
        }

        let asked = try #require(window.howFast)
        window.putHowFastFirst(true)
        let ticked = window.howFast
        window.chooseHowFastPace(.faster)
        window.startHowFast()
        // What `ficha pace faster` and `ficha deck queue Historia --first` do.
        let old = try ficha.progressSettings()
        var faster = old
        faster.newCardsPerDay = Pace.faster.newCardsPerDay
        try ficha.saveProgressSettings(faster, changedFrom: old)
        try ficha.moveInQueue(deck: "Historia", to: .first)
        let first = try Pace.allCases.map { try finish(of: "Historia", at: $0, in: ficha) }

        #expect(deckOfTheFile(asked) == "Historia")
        #expect(asked.line == .deckFile(cardCount: 3, fileName: "Historia.ficha"))
        #expect(asked.pace == .steady)
        #expect(asked.paces.map(\.pace) == [.chill, .steady, .faster])
        #expect(asked.paces.map(\.finish) == whereItIs)
        #expect(asked.paces.map(\.wording) == wordings)
        #expect(asked.decksAhead == ["Arte"])
        #expect(asked.decksPassed == ["Arte"])
        #expect(asked.decksStillAhead == [])
        #expect(asked.offersPutItFirst)
        #expect(!asked.putsFirst)
        #expect(asked.hasOtherDecks)
        #expect(ticked?.putsFirst == true)
        #expect(ticked?.paces.map(\.finish) == first)
        #expect(window.question == nil)
        #expect(try engine.progressSettings() == ficha.progressSettings())
        #expect(try engine.progressSettings().newCardsPerDay == Pace.faster.newCardsPerDay)
        #expect(try engine.queue(settings) == ficha.queue(settings))
        #expect(try engine.queue(settings).map(\.deck) == ["Historia", "Arte"])
    }

    // As above, Historia's .ficha opens a minute after Arte, which the user
    // is meeting, comes in.
    @Test(
        "How fast?'s Cancel leaves the pace and the queue as they were, and a deck's .ficha out, whatever was chosen",
        .bug(id: 491), .bug(id: 542))
    func cancelChangesNothing() async throws {
        try meetArte(in: engine)
        time.advance(by: minutes(1))
        let historiaFile = try writeDeck("Historia.ficha", historia)
        var window = openWindow()
        await window.openDeckAndWait(historiaFile)
        let progress = try engine.progressSettings()
        let queue = try engine.queue(settings)

        let asked = window.howFast
        window.chooseHowFastPace(.faster)
        window.putHowFastFirst(true)
        window.cancelQuestion()

        #expect(deckOfTheFile(asked) == "Historia")
        #expect(window.question == nil)
        #expect(try engine.progressSettings() == progress)
        #expect(try engine.queue(settings) == queue)
        #expect(queue.map(\.deck) == ["Arte"])
        #expect(try engine.cards().allSatisfy { $0.deck != "Historia" })
    }

    // Música, a priority deck, has a new card from a minute before Historia's
    // .ficha opens, so its deck would come in last.
    @Test(
        "How fast?, for a deck whose only deck ahead is a priority deck, says it goes after that deck, and offers no Put it first, as the priority deck's new cards come first wherever the deck goes",
        .bug(id: 491), .bug(id: 542))
    func itGoesAfterAPriorityDeckWithNoPutItFirst() async throws {
        try newCardInDeck("Bach", deck: "Música", in: engine)
        try engine.setPriority(true, ofDeck: "Música")
        time.advance(by: minutes(1))
        let historiaFile = try writeDeck("Historia.ficha", historia)
        var window = openWindow()

        await window.openDeckAndWait(historiaFile)
        let asked = try #require(window.howFast)
        window.putHowFastFirst(true)

        #expect(deckOfTheFile(asked) == "Historia")
        #expect(asked.decksAhead == ["Música"])
        #expect(asked.decksPassed == [])
        #expect(asked.decksStillAhead == ["Música"])
        #expect(asked.saysWhereItGoes)
        #expect(!asked.offersPutItFirst)
        #expect(window.howFast?.putsFirst == false)
    }

    // Three new cards a day are no pace, as a version of Ficha before the
    // pace could leave them.
    @Test(
        "after New Deck…'s OK, How fast? offers the paces alone, with no finish date and no Put it first, at Steady while the user's new cards a day are no pace, and Start sets the pace",
        .bug(id: 491))
    func howFastAfterNewDeck() throws {
        try newCardInDeck("La Gioconda", deck: "Arte", in: engine)
        let old = try engine.progressSettings()
        var noPace = old
        noPace.newCardsPerDay = 3
        try engine.saveProgressSettings(noPace, changedFrom: old)
        var window = openWindow()

        window.askToMakeDeck()
        window.chooseNewDeck("Historia")
        let asked = window.howFast
        window.chooseHowFastPace(.chill)
        window.startHowFast()

        let howFast = try #require(asked)
        #expect(howFast.subject == .deck("Historia"))
        #expect(howFast.line == .noCards)
        #expect(howFast.pace == .steady)
        #expect(howFast.paces.map(\.pace) == [.chill, .steady, .faster])
        #expect(howFast.paces.map(\.finish) == [nil, nil, nil])
        #expect(!howFast.saysWhereItGoes)
        #expect(!howFast.offersPutItFirst)
        #expect(howFast.hasOtherDecks)
        #expect(window.question == nil)
        #expect(try engine.progressSettings().newCardsPerDay == Pace.chill.newCardsPerDay)
        #expect(try engine.decks().map(\.name) == ["Arte", "Historia"])
    }

    // At 2:00 on Thursday the 15th, Ficha's day is still Wednesday's, whose
    // active hours, 9 to 22, are over: the three cards of Historia's .ficha
    // would start coming on Thursday, from 4:00, all that day at Faster if it
    // has appearances, or by Friday.
    @Test(
        "How fast? at 2:00 counts days from 4:00: at Faster, a deck that comes in then is all met tomorrow or Friday, not today",
        .bug(id: 562), .bug(id: 542))
    func howFastCountsDaysFromFour() async throws {
        time.move(to: try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 2))))
        let historiaFile = try writeDeck("Historia.ficha", historia)
        var window = openWindow()

        await window.openDeckAndWait(historiaFile)

        let faster = try #require(window.howFast?.paces.first { $0.pace == .faster })
        let friday = calendar.startOfDay(for: try morning(of: 16, in: calendar))
        #expect(faster.wording == .dayOrNext(.tomorrow, .weekday(friday)))
        #expect(faster.wording?.startsToday == false)
    }

    /// The window as it opens, on the first deck of the queue new cards come
    /// from, with the cards read.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        return window
    }

    /// Arte's three cards, in `engine`, with La Gioconda met now: the deck
    /// the user is meeting.
    private func meetArte(in engine: Engine) throws {
        let gioconda = try newCardInDeck("La Gioconda", deck: "Arte", in: engine)
        try newCardInDeck("Las Meninas", deck: "Arte", in: engine)
        try newCardInDeck("El Grito", deck: "Arte", in: engine)
        try engine.meet(gioconda)
    }

    /// When the new cards of `deck` in `engine`'s queue are all met at
    /// `pace`, now, with Ficha's other settings, as `ficha queue` says it:
    /// nil while the deck isn't in the queue.
    private func finish(of deck: String, at pace: Pace, in engine: Engine) throws -> FinishDate? {
        var paced = settings
        paced.newCardsPerDay = pace.newCardsPerDay
        return try engine.queue(paced).first { $0.deck == deck }?.finish
    }

    /// Writes a deck's `.ficha` named `name` in the test's folder, with
    /// `text` as its text file, and returns the file.
    private func writeDeck(_ name: String, _ text: String) throws -> URL {
        let file = folder.appending(path: name)
        try writeDeckFile(at: file, text: text)
        return file
    }

    /// The deck of the `.ficha` `howFast` asks about, or nil when it asks
    /// about none.
    private func deckOfTheFile(_ howFast: CardsWindowState.HowFast?) -> String? {
        guard case .deckFile(let file)? = howFast?.subject else { return nil }
        return file.deck
    }
}
