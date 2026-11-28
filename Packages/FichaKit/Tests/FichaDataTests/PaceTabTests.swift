import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on Settings' Pace tab (#492, ADR 0034): How fast?, with when every
/// deck in the queue is all met at each pace, and the queue new cards come
/// from, with Put it first, into an engine in memory. They start at 9 in the
/// morning of Wednesday the 14th of October in Buenos Aires, when active
/// hours start, on a new install, at Steady, as `PaceAndQueueTests` do.
struct PaceTabTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // The user is meeting Arte, whose La Gioconda was met now, so today
    // brings one more new card at Steady. Historia came in a minute later,
    // last in the queue.
    @Test(
        "the Pace tab ticks the user's pace, and says at each pace when every deck in the queue is all met, as ficha queue does",
        .bug(id: 492))
    func itSaysWhenTheQueueIsMetAtEachPace() throws {
        try meetArte(in: engine)
        time.advance(by: minutes(1))
        try newCardInDeck("Coliseo", deck: "Historia", in: engine)
        try newCardInDeck("Partenón", deck: "Historia", in: engine)
        let finishes = try Pace.allCases.map { try lastFinish(at: $0) }

        let tab = engine.openPaceTab(settings)

        #expect(tab.pace == .steady)
        #expect(tab.paces.map(\.pace) == [.chill, .steady, .faster])
        #expect(tab.paces.map(\.finish) == finishes)
        #expect(tab.paces.map(\.wording) == finishes.map { wording(of: $0) })
        #expect(finishes.allSatisfy { $0 != nil })
        #expect(tab.queueMet == tab.paces[1].wording)
        #expect(tab.unreadable == nil)
    }

    // Música is a priority deck with a new card, so its cards come first
    // wherever the other decks go. Arte, with its emoji, came in a minute
    // later, and Historia a minute after it. Put first, Historia would pass
    // Arte, and Arte, only Música, which stays ahead of it.
    @Test(
        "the Pace tab lists the queue's decks in its order, each with its emoji, its new cards and when they're all met, the first now, and offers Put it first only for a deck it would move ahead of another",
        .bug(id: 492))
    func itListsTheQueue() throws {
        try newCardInDeck("Bach", deck: "Música", in: engine)
        try engine.setPriority(true, ofDeck: "Música")
        time.advance(by: minutes(1))
        try meetArte(in: engine)
        try engine.setEmoji(try Emoji("🎨"), ofDeck: "Arte")
        time.advance(by: minutes(1))
        try newCardInDeck("Coliseo", deck: "Historia", in: engine)
        let queue = try engine.queue(settings)

        let tab = engine.openPaceTab(settings)

        #expect(tab.queue.map(\.deck.name) == ["Música", "Arte", "Historia"])
        #expect(tab.queue.map(\.deck.name) == queue.map(\.deck))
        #expect(tab.queue.map(\.newCards) == queue.map(\.newCards))
        #expect(tab.queue.map(\.finish) == queue.map(\.finish))
        #expect(tab.queue.map(\.wording) == queue.map { wording(of: $0.finish) })
        #expect(tab.queue.map(\.deck.shownEmoji) == [nil, "🎨", nil])
        #expect(tab.queue.map(\.isNow) == [true, false, false])
        #expect(tab.queue.map(\.offersPutItFirst) == [false, false, true])
    }

    // As above, Historia came in a minute after Arte, which the user is
    // meeting. `ficha` does the same in another Ficha, on the same clock.
    @Test(
        "Put it first, in the Pace tab, moves the deck first in the queue as ficha deck queue --first does, and the tab lists it first",
        .bug(id: 492))
    func putItFirstMovesTheDeckFirst() throws {
        let ficha = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try meetArte(in: engine)
        try meetArte(in: ficha)
        time.advance(by: minutes(1))
        try newCardInDeck("Coliseo", deck: "Historia", in: engine)
        try newCardInDeck("Coliseo", deck: "Historia", in: ficha)
        var tab = engine.openPaceTab(settings)

        let offered = tab.queue.map(\.offersPutItFirst)
        tab.putFirst("Historia", with: settings)
        try ficha.moveInQueue(deck: "Historia", to: .first)

        #expect(offered == [false, true])
        #expect(try engine.queue(settings) == ficha.queue(settings))
        #expect(tab.queue.map(\.deck.name) == ["Historia", "Arte"])
        #expect(tab.queue.map(\.isNow) == [true, false])
        #expect(tab.failure == nil)
    }

    // A name of nothing but the separator is no deck's, so the engine
    // refuses to move it, as `ficha deck queue --first` would.
    @Test(
        "when Put it first fails, the Pace tab says why for that deck, with the queue as it was, until the user closes it",
        .bug(id: 492))
    func putItFirstSaysWhyItFailed() throws {
        try meetArte(in: engine)
        var tab = engine.openPaceTab(settings)

        tab.putFirst("::", with: settings)
        let failure = tab.failure
        tab.dismissFailure()

        #expect(failure?.deck == "::")
        #expect(failure?.error == .blankDeckName)
        #expect(tab.queue.map(\.deck.name) == ["Arte"])
        #expect(tab.failure == nil)
    }

    // 8 new cards a day, as the Appearances tab could set before the pace.
    @Test(
        "with new cards a day that are no pace, the Pace tab ticks none, and still says when the queue is all met at each pace",
        .bug(id: 492))
    func itTicksNoPaceForANumberThatIsNone() throws {
        try meetArte(in: engine)
        var eight = settings
        eight.newCardsPerDay = 8

        let tab = engine.openPaceTab(eight)

        #expect(tab.pace == nil)
        #expect(tab.paces.map(\.pace) == [.chill, .steady, .faster])
        #expect(tab.paces.allSatisfy { $0.finish != nil })
    }

    /// Arte's three cards, in `engine`, with La Gioconda met now: the deck
    /// the user is meeting.
    private func meetArte(in engine: Engine) throws {
        let gioconda = try newCardInDeck("La Gioconda", deck: "Arte", in: engine)
        try newCardInDeck("Las Meninas", deck: "Arte", in: engine)
        try newCardInDeck("El Grito", deck: "Arte", in: engine)
        try engine.meet(gioconda)
    }

    /// How the app says `finish` now, with the settings' Ficha's day.
    private func wording(of finish: FinishDate?) -> FinishDate.Wording? {
        finish?.wording(now: time.now, dayStartsAtHour: settings.dayStartsAtHour, calendar: calendar)
    }

    /// When the last deck in the engine's queue is all met at `pace`, now,
    /// with Ficha's other settings, as `ficha queue` says it.
    private func lastFinish(at pace: Pace) throws -> FinishDate? {
        var paced = settings
        paced.newCardsPerDay = pace.newCardsPerDay
        return try engine.queue(paced).last?.finish
    }
}
