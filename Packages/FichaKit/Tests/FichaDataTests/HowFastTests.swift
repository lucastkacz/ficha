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
    /// A folder of the test's own, for the files it imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaHowFastTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    /// Historia's three cards, as a file with a Deck column brings a deck in.
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
    // more new card at Steady. Historia comes in a minute later, from an
    // import, last. `ficha` does the same in another Ficha, on the same
    // clock: its pace and its move are what the window's Start must match.
    @Test(
        "How fast?, for a deck that came in behind one the user is meeting, says when it's all met at each pace, where it is and, ticked, first, and Start with Faster and Put it first sets the pace and the deck's place as ficha pace and ficha deck queue --first do",
        .bug(id: 491))
    func startSetsThePaceAndPutsTheDeckFirst() async throws {
        let ficha = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try meetArte(in: engine)
        try meetArte(in: ficha)
        time.advance(by: minutes(1))
        let historiaFile = try write("Historia.txt", historia)
        var window = openWindow()
        await window.importThroughTheSheet(historiaFile)
        let preview = try await ficha.previewImport(of: historiaFile)
        try ficha.importCards(preview, choosing: ImportChoices())
        let whereItIs = try Pace.allCases.map { try finish(of: "Historia", at: $0, in: engine) }
        let wordings = whereItIs.map { $0?.wording(now: time.now, calendar: calendar) }

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

        #expect(asked.subject == .deck("Historia"))
        #expect(asked.line == .imported(cardCount: 3))
        #expect(asked.pace == .steady)
        #expect(asked.paces.map(\.pace) == [.chill, .steady, .faster])
        #expect(asked.paces.map(\.finish) == whereItIs)
        #expect(asked.paces.map(\.wording) == wordings)
        #expect(asked.decksAhead == ["Arte"])
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

    // As above, Historia comes in a minute after Arte, which the user is
    // meeting.
    @Test(
        "How fast?'s Cancel leaves the pace and the queue as they were, with the deck last, where it came in, whatever was chosen",
        .bug(id: 491))
    func cancelChangesNothing() async throws {
        try meetArte(in: engine)
        time.advance(by: minutes(1))
        let historiaFile = try write("Historia.txt", historia)
        var window = openWindow()
        await window.importThroughTheSheet(historiaFile)
        let progress = try engine.progressSettings()
        let queue = try engine.queue(settings)

        let asked = window.howFast
        window.chooseHowFastPace(.faster)
        window.putHowFastFirst(true)
        window.cancelQuestion()

        #expect(asked?.subject == .deck("Historia"))
        #expect(window.question == nil)
        #expect(try engine.progressSettings() == progress)
        #expect(try engine.queue(settings) == queue)
        #expect(queue.map(\.deck) == ["Arte", "Historia"])
    }

    // Three new cards a day are no pace, as a version of Ficha before the
    // pace could leave them.
    @Test(
        "after New Deck…'s OK, How fast? offers the paces alone, with no finish date and no Put it first, at Steady while the user's new cards a day are no pace, and Start sets the pace",
        .bug(id: 491))
    func howFastAfterNewDeck() throws {
        try approveInDeck("La Gioconda", deck: "Arte", in: engine)
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
        #expect(!howFast.offersPutItFirst)
        #expect(howFast.hasOtherDecks)
        #expect(window.question == nil)
        #expect(try engine.progressSettings().newCardsPerDay == Pace.chill.newCardsPerDay)
        #expect(try engine.decks().map(\.name) == ["Arte", "Historia"])
    }

    // Coliseo waits in Historia, new, from a minute before the imports, so
    // Historia goes ahead of a deck they bring. The first file only updates
    // it; the second brings two cards into Arte, one of them inside
    // Arte::Barroco.
    @Test(
        "How fast? opens once the Import sheet's Done closes it after an import that brought new cards into one deck, for that deck, and not after one that brought none",
        .bug(id: 491))
    func howFastAfterAnImport() async throws {
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        time.advance(by: minutes(1))
        let update = try write("Repaso.txt", "Coliseo\tEn Roma, del siglo I.\n")
        let arte = try write(
            "Arte.txt",
            """
            #separator:tab
            #html:false
            #columns:Front\tBack\tDeck
            La Gioconda\tDe Leonardo.\tArte
            Las Meninas\tDe Velázquez.\tArte::Barroco

            """)
        var window = openWindow()

        await window.importThroughTheSheet(update)
        let afterTheUpdate = window.question
        window.startImport()
        await window.previewImportAndWait(of: arte)
        await window.importCardsAndWait()
        let beforeDone = window.question
        window.closeImport()
        let asked = window.howFast
        let whereItIs = try Pace.allCases.map { try finish(of: "Arte", at: $0, in: engine) }

        #expect(afterTheUpdate == nil)
        #expect(beforeDone == nil)
        let howFast = try #require(asked)
        #expect(howFast.subject == .deck("Arte"))
        #expect(howFast.line == .imported(cardCount: 2))
        #expect(howFast.decksAhead == ["Historia"])
        #expect(howFast.paces.map(\.finish) == whereItIs)
    }

    /// The window as it opens, on All cards, with the cards read.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        return window
    }

    /// Arte's three cards, in `engine`, with La Gioconda met now: the deck
    /// the user is meeting.
    private func meetArte(in engine: Engine) throws {
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        try approveInDeck("Las Meninas", deck: "Arte", in: engine)
        try approveInDeck("El Grito", deck: "Arte", in: engine)
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

    /// Writes `text` as UTF-8 to a file named `name` in the test's folder,
    /// and returns the file.
    private func write(_ name: String, _ text: String) throws -> URL {
        let file = folder.appending(path: name)
        try Data(text.utf8).write(to: file)
        return file
    }
}

extension CardsWindowState {
    /// Imports `file` through the Import sheet, as the user does: chooses
    /// it, imports its cards and closes the sheet with Done.
    fileprivate mutating func importThroughTheSheet(_ file: URL) async {
        startImport()
        await previewImportAndWait(of: file)
        await importCardsAndWait()
        closeImport()
    }
}
