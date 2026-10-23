import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on setting a tag aside, which takes every card with it out of
/// Lucas's reviews for now, without burying them, and on no longer setting
/// it aside, which brings them back where they'd be without it (ADR 0011),
/// with the default settings. They start at 9 in the morning in Buenos
/// Aires, when active hours start.
struct SettingAsideTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("a set-aside tag's cards leave review now, See more and the menu's counts")
    func aSetAsideTagsCardsLeaveReviewNowSeeMoreAndTheCounts() throws {
        // eudaimonía gets to the 30-day step, from which a card is learned,
        // ubuntu to the first step, and both come due. ataraxia is new.
        let ubuntu = try approveCard("ubuntu", tags: ["lenguaje"])
        let eudaimonia = try approveCard("eudaimonía", tags: ["filosofía"])
        try approveCard("ataraxia", tags: ["filosofía"])
        try engine.climb(eudaimonia, to: 5, movingForward: time)
        try engine.meet(ubuntu)
        time.advance(by: days(30))

        try engine.setAside("filosofía")

        #expect(try engine.reviewNow(settings) == [.review(ubuntu)])
        #expect(engine.openPanel(.reviewNow, with: [], settings: settings).moreCards == [.review(ubuntu)])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.learned == 0)
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
