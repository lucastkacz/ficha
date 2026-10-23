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

    @Test("no appearance comes for a set-aside tag's cards, and none is planned for them")
    func noAppearanceComesForASetAsideTagsCards() throws {
        try meetCard("eudaimonía", tags: ["filosofía"], dueAt: try at(10, 0))
        try engine.setAside("filosofía")

        time.move(to: try at(10, 0))

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
        #expect(try engine.upcomingAppearances(settings).isEmpty)
    }

    @Test("appearances, planned appearances and card notifications leave out a set-aside tag's cards")
    func appearancesAndCardNotificationsLeaveOutASetAsideTagsCards() throws {
        let ubuntu = try meetCard("ubuntu", tags: ["lenguaje"], dueAt: try at(10, 0))
        let eudaimonia = try meetCard("eudaimonía", tags: ["filosofía"], dueAt: try at(10, 0))
        let petricor = try meetCard("petricor", tags: [], dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        // Planned before the tag was set aside, as the iPhone's card
        // notifications are.
        let notified = NotifiedAppearance(try #require(try engine.upcomingAppearances(settings).first))
        #expect(notified.cardIDs == [ubuntu.id, eudaimonia.id, petricor.id])

        try engine.setAside("filosofía")

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.review(ubuntu), .review(petricor)]))
        #expect(try engine.upcomingAppearances(settings).first?.cards == [.review(ubuntu), .review(petricor)])
        let next = try engine.answerFromNotification(.review(.good), of: ubuntu.id, in: notified, settings: settings)
        #expect(next == .review(petricor))
    }

    @Test("a card with a set-aside tag and other tags is set aside")
    func aCardWithASetAsideTagAndOthersIsSetAside() throws {
        let ubuntu = try approveCard("ubuntu", tags: ["lenguaje", "filosofía", "ética"])

        try engine.setAside("filosofía")
        try engine.setAside("ética")

        #expect(try engine.cards().map(\.standing) == [.setAside(by: ["ética", "filosofía"])])
        #expect(try engine.reviewNow(settings).isEmpty)
        try engine.stopSettingAside("ética")
        #expect(try engine.cards().map(\.standing) == [.setAside(by: ["filosofía"])])
        #expect(ubuntu.standing == .inReviews)
    }

    // A refine session approves new cards with the tag, and the Cards window
    // edits a card to add it.
    @Test("a card that gets a set-aside tag later is set aside")
    func aCardThatGetsTheTagLaterIsSetAside() throws {
        let serendipia = try approveCard("serendipia", tags: [])
        try engine.setAside("historia")

        let mayo = try approveCard("Revolución de Mayo", tags: ["historia"])
        let edited = try engine.edit(
            serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo.", tags: ["historia"]))

        #expect(mayo.standing == .setAside(by: ["historia"]))
        #expect(edited.standing == .setAside(by: ["historia"]))
        #expect(try engine.reviewNow(settings).isEmpty)
    }

    @Test(
        "stopping setting a tag aside brings its cards back on their step, with the cards that came due meanwhile due")
    func stoppingSettingATagAsideBringsItsCardsBack() throws {
        // eudaimonía gets to the second step, which waits 4 hours, and
        // ataraxia is new.
        let eudaimonia = try approveCard("eudaimonía", tags: ["filosofía"])
        let ataraxia = try approveCard("ataraxia", tags: ["filosofía"])
        try engine.climb(eudaimonia, to: 1, movingForward: time)
        let standing = try engine.standing(of: eudaimonia.id, on: settings.ladder)
        try engine.setAside("filosofía")
        time.advance(by: days(2))
        #expect(try engine.reviewNow(settings).isEmpty)

        try engine.stopSettingAside("filosofía")

        #expect(try engine.standing(of: eudaimonia.id, on: settings.ladder) == standing)
        #expect(try engine.reviewNow(settings) == [.review(eudaimonia), .firstView(ataraxia)])
        #expect(try engine.progress(settings).due == 1)
        #expect(try engine.reviewLog().map(\.cardID) == [eudaimonia.id, eudaimonia.id])
    }

    // Buried, then the inbox, then set aside, then reviews (ADR 0011).
    @Test(
        "a flagged card stays in the inbox and a buried card stays buried whatever their tags, and fixing or unburying a card with a set-aside tag leaves it set aside"
    )
    func theInboxAndBurialsWinOverSetAside() throws {
        let ubuntu = try approveCard("ubuntu", tags: ["filosofía"])
        let eudaimonia = try approveCard("eudaimonía", tags: ["filosofía"])
        let flag = try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let buried = try engine.bury(eudaimonia.id)

        try engine.setAside("filosofía")

        #expect(try engine.inbox().flaggedCards.map(\.id) == [ubuntu.id])
        #expect(try engine.progress(settings).inInbox == 1)
        #expect(
            try engine.cards().map(\.standing) == [
                .inInbox(try #require(flag.flag)), .buried(at: try #require(buried.buriedAt), flag: nil),
            ])
        let fixed = try engine.fix(
            ubuntu.id, with: card(.word, front: "ubuntu", back: "Humanidad hacia los otros.", tags: ["filosofía"]))
        let unburied = try engine.unbury(eudaimonia.id)
        #expect(fixed.standing == .setAside(by: ["filosofía"]))
        #expect(unburied.standing == .setAside(by: ["filosofía"]))
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.reviewNow(settings).isEmpty)
    }

    // The review panel shows it as it shows a buried card's.
    @Test("answering a set-aside card is refused, naming its set-aside tags, and the review log doesn't change")
    func answeringASetAsideCardIsRefused() throws {
        let ubuntu = try approveCard("ubuntu", tags: ["lenguaje", "filosofía", "ética"])
        try engine.setAside("filosofía")
        try engine.setAside("ética")

        #expect(throws: EngineError.cardSetAside(ubuntu.id, tags: ["ética", "filosofía"])) {
            try engine.meet(ubuntu)
        }
        #expect(try engine.reviewLog().isEmpty)
    }

    @Test("a set-aside card can be flagged, buried, edited and expanded, as a card in Lucas's reviews can")
    func aSetAsideCardCanBeFlaggedBuriedEditedAndExpanded() throws {
        let ubuntu = try approveCard("ubuntu", tags: ["filosofía"])
        let eudaimonia = try approveCard("eudaimonía", tags: ["filosofía"])
        let ataraxia = try approveCard("ataraxia", tags: ["filosofía"])
        try engine.setAside("filosofía")

        let flagged = try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let buried = try engine.bury(eudaimonia.id)
        let edited = try engine.edit(
            ataraxia.id, with: card(.concept, front: "ataraxia", back: "Serenidad.", tags: ["filosofía"]))
        let expansion = try engine.expand(text: "ataraxia", note: "Es de Epicuro", source: nil)
        let expanded = try engine.approveExpansion(
            expansion.id,
            into: card(.concept, front: "ataraxia", back: "Serenidad, según Epicuro.", tags: ["filosofía"]))

        #expect(flagged.standing == .inInbox(try #require(flagged.flag)))
        #expect(buried.standing == .buried(at: time.now, flag: nil))
        #expect(edited.standing == .setAside(by: ["filosofía"]))
        #expect(expansion.expandsCardID == ataraxia.id)
        #expect(expanded.back == "Serenidad, según Epicuro.")
        #expect(expanded.standing == .setAside(by: ["filosofía"]))
    }

    // A set-aside tag no card carries stays in the sidebar, so the table
    // keeps its row until Lucas undoes it.
    @Test("the tag table's row goes once the tag is no longer set aside and has nothing else")
    func theTagsRowGoesOnceItHasNothingLeft() throws {
        try approveCard("ubuntu", tags: ["lenguaje"])
        try engine.setAside("historia")
        #expect(
            try engine.sidebarTags() == [CardTag(name: "historia", switchedOn: .setAside), CardTag(name: "lenguaje")])

        try engine.stopSettingAside("historia")
        try engine.stopSettingAside("historia")

        #expect(try engine.sidebarTags() == [CardTag(name: "lenguaje")])
        let mayo = try approveCard("Revolución de Mayo", tags: ["historia"])
        #expect(mayo.standing == .inReviews)
    }

    // `ficha cards` prints the cards this way, for a refine session to know.
    @Test("a card's encoding has setAsideBy for a card with set-aside tags, and leaves it out otherwise")
    func aCardsEncodingHasSetAsideByWhenItHasSetAsideTags() throws {
        try approveCard("ubuntu", tags: ["lenguaje", "filosofía", "ética"])
        try approveCard("serendipia", tags: ["lenguaje"])
        try engine.setAside("filosofía")
        try engine.setAside("ética")

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cards()))
        let cards = try #require(encoded as? [[String: Any]])

        #expect(cards.map { $0["setAsideBy"] as? [String] } == [["ética", "filosofía"], nil])
        #expect(cards.map { $0.keys.contains("setAsideBy") } == [true, false])
    }

    /// Approves a card with this front and these tags and meets it, an hour
    /// before `due`, so that it's due then, after the first step's wait. Each
    /// card is met after the ones before it, so they come due in order.
    @discardableResult
    private func meetCard(_ front: String, tags: [String], dueAt due: Date) throws -> Card {
        let card = try approveCard(front, tags: tags)
        time.move(to: due - hours(1))
        try engine.meet(card)
        return card
    }

    /// A time of day on October 14, 2026, by the tests' calendar.
    private func at(_ hour: Int, _ minute: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute)))
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
