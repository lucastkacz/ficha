import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the review panel's "You've met them all" (ADR 0034, #491): once
/// the panel went through its cards, the decks an answer in it met in full,
/// and what comes next in the queue new cards come from, with the default
/// settings. They start at 9 in the morning of Wednesday the 14th in Buenos
/// Aires, when active hours start.
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
}
