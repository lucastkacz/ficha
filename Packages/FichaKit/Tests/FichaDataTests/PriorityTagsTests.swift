import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on priority tags, whose cards come first when cards show up, while
/// the others still come when there's room (ADR 0011), with the default
/// settings: 5 cards per appearance and 5 new cards a day. They start at 9 in
/// the morning in Buenos Aires, when active hours start.
struct PriorityTagsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("due priority cards come before the other due cards, each group in today's order")
    func duePriorityCardsComeFirst() throws {
        // Each card is met a minute after the one before it, so on the same
        // step, the first met is the longest overdue.
        let ubuntu = try meetCard("ubuntu", tags: ["lenguaje"])
        let eudaimonia = try meetCard("eudaimonía", tags: ["filosofía"])
        let petricor = try meetCard("petricor", tags: [])
        let ataraxia = try meetCard("ataraxia", tags: ["filosofía"])
        time.advance(by: hours(1))
        #expect(try engine.reviewNow(settings) == [ubuntu, eudaimonia, petricor, ataraxia].map(PanelCard.review))

        try engine.togglePriority(of: "filosofía")

        #expect(try engine.reviewNow(settings) == [eudaimonia, ataraxia, ubuntu, petricor].map(PanelCard.review))
    }

    @Test(
        "with 5 cards per appearance, 5 other cards due and a new priority card, under the daily limit, an appearance brings the new priority card and 4 of the other due cards, and review now does the same"
    )
    func aNewPriorityCardTakesASlotAheadOfTheOtherDueCards() throws {
        // Met the day before, so none of the day's new cards is met yet.
        let due = try ["uno", "dos", "tres", "cuatro", "cinco"].map { try meetCard($0, tags: ["lenguaje"]) }
        try approveCard("ataraxia", tags: [])
        let eudaimonia = try approveCard("eudaimonía", tags: ["filosofía"])
        time.move(to: try morning(of: 15, in: calendar))
        #expect(try engine.reviewNow(settings) == due.map(PanelCard.review))

        try engine.togglePriority(of: "filosofía")

        let expected = due.prefix(4).map(PanelCard.review) + [.firstView(eudaimonia)]
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show(expected))
        #expect(try engine.reviewNow(settings) == expected)
    }

    /// Approves a card with this front and these tags and meets it now, so
    /// that it's due an hour later, after the first step's wait, and then
    /// moves time a minute forward, so the next card met comes due after it.
    @discardableResult
    private func meetCard(_ front: String, tags: [String]) throws -> Card {
        let card = try approveCard(front, tags: tags)
        try engine.meet(card)
        time.advance(by: minutes(1))
        return card
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card: a new card,
    /// after the ones approved before it.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
