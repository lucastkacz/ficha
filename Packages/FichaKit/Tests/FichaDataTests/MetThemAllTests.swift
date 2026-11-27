import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the review panel's "You've met them all" (ADR 0034, #491): once
/// the panel went through its cards, the decks an answer in it met in full,
/// and what comes next in the queue new cards come from, with the default
/// settings, or, with nothing there, one of Ficha's decks (#458). They start
/// at 9 in the morning of Wednesday the 14th in Buenos Aires, when active
/// hours start.
struct MetThemAllTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // La Gioconda was met the day before, so Las Meninas is Arte's last new
    // card. Historia came in a minute after Arte, so it's next. Answered
    // again after ⌘Z, Arte is met in full once, not twice.
    @Test(
        "the answer that meets a deck's last new card makes the done panel say you've met them all, with the next deck in the queue, and undoing it forgets it",
        .bug(id: 491))
    func theAnswerThatMeetsADecksLastNewCard() throws {
        time.move(to: try morning(of: 13, in: calendar))
        try engine.meet(try approveInDeck("La Gioconda", deck: "Arte", in: engine))
        let meninas = try approveInDeck("Las Meninas", deck: "Arte", in: engine)
        time.advance(by: minutes(1))
        try approveInDeck("Coliseo", deck: "Historia", in: engine)
        try engine.setEmoji(try Emoji("🎨"), ofDeck: "Arte")
        try engine.setEmoji(try Emoji("📜"), ofDeck: "Historia")
        time.move(to: try morning(of: 14, in: calendar))
        var panel = try engine.openPanel(.reviewNow, with: [.new(meninas)], settings: settings)
        let beforeAnswering = panel.metThemAll

        try panel.answer(.review(.good), responseTime: .seconds(3))
        let met = panel.metThemAll
        try panel.undo()
        let undone = panel.metThemAll
        try panel.answer(.review(.good), responseTime: .seconds(3))

        #expect(beforeAnswering == nil)
        #expect(met?.decks.map(\.name) == ["Arte"])
        #expect(met?.decks.map(\.shownEmoji) == ["🎨"])
        #expect(met?.nextInQueue?.name == "Historia")
        #expect(met?.nextInQueue?.shownEmoji == "📜")
        #expect(undone == nil)
        #expect(panel.content == .done)
        #expect(panel.metThemAll == met)
    }

    // Arte has two new cards, La Gioconda and Las Meninas, so meeting the
    // first leaves the second in the queue.
    @Test(
        "the answer that meets the first of a deck's two new cards makes the done panel say nothing of the deck",
        .bug(id: 491))
    func theFirstOfTwoNewCardsMeetsNothingInFull() throws {
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        try approveInDeck("Las Meninas", deck: "Arte", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: [.new(gioconda)], settings: settings)

        try panel.answer(.review(.good), responseTime: .seconds(3))

        #expect(panel.content == .done)
        #expect(panel.metThemAll == nil)
        #expect(try engine.queue(settings).map(\.deck) == ["Arte"])
    }

    // El Grito, Arte's other new card, is buried, so it's out of the
    // reviews, and the queue: the Cards window's row of Arte says it's met
    // them all too, by the same rule.
    @Test(
        "the answer that meets a deck's last new card in the reviews makes the done panel say you've met them all, with a buried new card left, as the deck's row in the Cards window says",
        .bug(id: 491))
    func aBuriedNewCardLeavesTheDeckMetInFull() throws {
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        let grito = try approveInDeck("El Grito", deck: "Arte", in: engine)
        try engine.bury(grito.id)
        var panel = try engine.openPanel(.reviewNow, with: [.new(gioconda)], settings: settings)

        try panel.answer(.review(.good), responseTime: .seconds(3))
        var window = engine.openCardsWindow(with: settings.scheduler)
        window.read(with: settings.scheduler)

        #expect(panel.metThemAll?.decks.map(\.name) == ["Arte"])
        #expect(window.deckRows.first { $0.id == "Arte" }?.line == .metThemAll(cards: 2, days: 1))
    }

    // Lenguaje's ubuntu was met already, so Arte is the only deck in the
    // queue.
    @Test(
        "once the answer that meets a deck's last new card leaves no deck in the queue, the done panel says nothing waits",
        .bug(id: 491))
    func nothingWaitsOnceTheLastDeckIsMet() throws {
        try engine.meet(try approveInDeck("ubuntu", deck: "Lenguaje", in: engine))
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: [.new(gioconda)], settings: settings)

        try panel.answer(.review(.good), responseTime: .seconds(3))

        #expect(panel.content == .done)
        let met = try #require(panel.metThemAll)
        #expect(met.decks.map(\.name) == ["Arte"])
        #expect(met.nextInQueue == nil)
    }

    // Small files of Ficha's decks, a card each, in a folder of the test's
    // own: Lenguaje's ubuntu, met already, is Palabras lindas' card, front
    // and back, so the user has added that deck, and Arte argentino is the
    // first they haven't.
    @Test(
        "once nothing waits in the queue, the done panel asks for Ficha's decks, and offers the first the user hasn't added",
        .bug(id: 458))
    func nothingWaitsOffersOneOfFichasDecks() async throws {
        let folder = URL.temporaryDirectory.appending(
            path: "MetThemAllTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fronts: [FichaDeck: String] = [
            .palabrasLindas: "ubuntu", .arteArgentino: "Las Meninas", .floresDeBuenosAires: "Jacarandá",
        ]
        var files: [FichaDeck: Result<FichaDeckFile, EngineError>] = [:]
        for deck in FichaDeck.allCases {
            let front = try #require(fronts[deck])
            let file = folder.appending(path: "\(deck.fileName).txt")
            let text =
                "#separator:tab\n#html:false\n#columns:Front\tBack\tDeck\n#deck column:3\n"
                + "\(front)\tLo que quiere decir «\(front)».\t\(deck.name)\n"
            try Data(text.utf8).write(to: file)
            files[deck] = .success(try await engine.readFichaDeck(deck, at: file))
        }
        try engine.meet(try approveInDeck("ubuntu", deck: "Lenguaje", in: engine))
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: [.new(gioconda)], settings: settings)

        try panel.answer(.review(.good), responseTime: .seconds(3))
        let asked = panel.asksForFichaDecks
        let beforeOffering = try #require(panel.metThemAll)
        panel.offerFichaDecks(files)

        #expect(asked)
        #expect(beforeOffering.fichaDeck == nil)
        #expect(panel.metThemAll?.fichaDeck == .arteArgentino)
        #expect(!panel.asksForFichaDecks)
    }
}
