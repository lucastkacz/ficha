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
        #expect(
            try engine.reviewNow(settings) == [ubuntu, eudaimonia, petricor, ataraxia].map { PanelCard.review($0) })

        try engine.togglePriority(of: "filosofía")

        #expect(
            try engine.reviewNow(settings) == [eudaimonia, ataraxia, ubuntu, petricor].map { PanelCard.review($0) })
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
        #expect(try engine.reviewNow(settings) == due.map { PanelCard.review($0) })

        try engine.togglePriority(of: "filosofía")

        let expected = due.prefix(4).map { PanelCard.review($0) } + [.firstView(eudaimonia)]
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show(expected))
        #expect(try engine.reviewNow(settings) == expected)
    }

    @Test("once Lucas has met 5 new cards today, no new card comes, priority or not")
    func noNewCardComesPastTheDailyLimit() throws {
        for front in ["uno", "dos", "tres", "cuatro", "cinco"] {
            try meetCard(front, tags: ["filosofía"])
        }
        try approveCard("ataraxia", tags: [])
        try approveCard("eudaimonía", tags: ["filosofía"])

        try engine.togglePriority(of: "filosofía")

        #expect(try engine.reviewNow(settings).isEmpty)
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
    }

    @Test("a new card without a priority tag still comes only when there's a slot after every due card")
    func aNewCardWithoutAPriorityTagWaitsForEveryDueCard() throws {
        let eudaimonia = try meetCard("eudaimonía", tags: ["filosofía"])
        let others = try ["uno", "dos", "tres", "cuatro"].map { try meetCard($0, tags: ["lenguaje"]) }
        let ataraxia = try approveCard("ataraxia", tags: [])
        try engine.togglePriority(of: "filosofía")
        time.move(to: try morning(of: 15, in: calendar))

        #expect(try engine.reviewNow(settings) == ([eudaimonia] + others).map { PanelCard.review($0) })
        try engine.review(others[3], .good)
        #expect(
            try engine.reviewNow(settings) == ([eudaimonia] + others.prefix(3)).map { PanelCard.review($0) }
                + [.firstView(ataraxia)])
    }

    @Test(
        "\"See more\" brings the due priority cards that didn't fit first, its reviews ahead are priority cards first, and it never brings a new card"
    )
    func seeMoreBringsPriorityCardsFirst() throws {
        // Met the day before, the other card first, so it's the longest
        // overdue.
        let other = try meetCard("ubuntu", tags: ["lenguaje"])
        let priority = try ["uno", "dos", "tres", "cuatro", "cinco", "seis"].map {
            try meetCard($0, tags: ["filosofía"])
        }
        try approveCard("eudaimonía", tags: ["filosofía"])
        time.move(to: try morning(of: 15, in: calendar))
        // Met today, the other card first, so it's due sooner: neither is due
        // for an hour.
        let otherAhead = try meetCard("petricor", tags: [])
        let priorityAhead = try meetCard("ataraxia", tags: ["filosofía"])
        try engine.togglePriority(of: "filosofía")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        #expect(panel.cards == priority.prefix(5).map { PanelCard.review($0) })

        for _ in panel.cards {
            try panel.answer(.review(.good), responseTime: .seconds(3))
        }

        #expect(
            panel.moreCards == [
                .review(priority[5]), .review(other), .reviewAhead(priorityAhead), .reviewAhead(otherAhead),
            ])
    }

    @Test("a priority card's back-first way comes with the priority cards, new or due, ahead of the others")
    func aPriorityCardsBackFirstWayComesWithThePriorityCards() throws {
        let ubuntu = try meetCard("ubuntu", tags: ["lenguaje"])
        let eudaimonia = try meetCard("eudaimonía", tags: ["filosofía"])
        let petricor = try approveCard("petricor", tags: [])
        let bothWays = try engine.setBothWays(true, of: [ubuntu.id, eudaimonia.id])
        try engine.togglePriority(of: "filosofía")
        time.move(to: try morning(of: 15, in: calendar))

        let newOne = try engine.reviewNow(settings)
        try engine.meet(bothWays[1], way: .backFirst)
        try engine.meet(bothWays[0], way: .backFirst)
        time.advance(by: hours(1))
        let dueOnes = try engine.reviewNow(settings)

        #expect(newOne == [.review(bothWays[1]), .review(bothWays[0]), .firstView(bothWays[1], .backFirst)])
        #expect(
            dueOnes == [
                .review(bothWays[1]), .review(bothWays[1], .backFirst), .review(bothWays[0]),
                .review(bothWays[0], .backFirst), .firstView(petricor),
            ])
    }

    @Test("a card with any of the priority tags counts as a priority card")
    func aCardWithAnyPriorityTagCounts() throws {
        let ubuntu = try meetCard("ubuntu", tags: ["lenguaje"])
        let mayo = try meetCard("Revolución de Mayo", tags: ["argentina", "historia"])
        let petricor = try meetCard("petricor", tags: [])
        let eudaimonia = try meetCard("eudaimonía", tags: ["ética", "filosofía"])
        time.advance(by: hours(1))

        try engine.togglePriority(of: "filosofía")
        try engine.togglePriority(of: "historia")

        #expect(try engine.reviewNow(settings) == [mayo, eudaimonia, ubuntu, petricor].map { PanelCard.review($0) })
    }

    @Test("each card's step and due time are the same with or without priority tags")
    func priorityTagsChangeNoStepOrDueTime() throws {
        let ubuntu = try approveCard("ubuntu", tags: ["lenguaje"])
        let eudaimonia = try approveCard("eudaimonía", tags: ["filosofía"])
        let ataraxia = try approveCard("ataraxia", tags: ["filosofía"])
        try engine.climb(ubuntu, to: 2, movingForward: time)
        try engine.climb(eudaimonia, to: 1, movingForward: time)
        let cards = [ubuntu, eudaimonia, ataraxia]
        let standings = try cards.map { try engine.standing(of: $0.id, on: settings.ladder) }

        try engine.togglePriority(of: "filosofía")

        #expect(try cards.map { try engine.standing(of: $0.id, on: settings.ladder) } == standings)
    }

    // A new priority card fits beside the cards due within the look-ahead,
    // where a new card without priority wouldn't, but that mustn't bring the
    // appearance before one would come without priority tags.
    @Test("an appearance comes when it would without priority tags, even when a new priority card would fit")
    func anAppearanceComesWhenItWouldWithoutPriorityTags() throws {
        // Five cards climb to the third step, which waits 2 days, so they
        // come due on the 16th at 14:00, when none of that day's new cards is
        // met yet.
        let lenguaje = try ["uno", "dos", "tres", "cuatro"].map { try approveCard($0, tags: ["lenguaje"]) }
        let cinco = try approveCard("cinco", tags: ["filosofía"])
        for card in lenguaje + [cinco] {
            try engine.meet(card)
        }
        for wait in [hours(1), hours(4)] {
            time.advance(by: wait)
            for card in lenguaje + [cinco] {
                try engine.review(card, .good)
            }
        }
        let eudaimonia = try approveCard("eudaimonía", tags: ["filosofía"])
        let dueTime = time.now + days(2)
        try engine.togglePriority(of: "filosofía")

        // They're due within the 20-minute look-ahead, but none is due yet.
        time.move(to: dueTime - minutes(15))
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
        time.move(to: dueTime)
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac())
                == .show([.review(cinco)] + lenguaje.prefix(3).map { PanelCard.review($0) } + [.firstView(eudaimonia)]))
    }

    // ciencia is set aside, and literatura::Roma sits inside a set-aside
    // tag: toggling either's priority wouldn't bring a card. historia is a
    // priority tag no card carries any longer, and stays to be unticked.
    @Test(
        "the Prioritize submenu lists None, the pinned tags in their order, then the priority tags that aren't pinned alphabetically, then All Tags…, and ticks the priority tags, but no set-aside one"
    )
    func theSubmenuListsAndTicksTheTags() throws {
        try approveCard("ubuntu", tags: ["lenguaje", "filosofía"])
        let mayo = try approveCard("Revolución de Mayo", tags: ["historia", "argentina"])
        try approveCard("eudaimonía", tags: ["ética"])
        try approveCard("Coliseo", tags: ["literatura::Roma"])
        let before = try engine.prioritizeMenu().tags
        for tag in ["lenguaje", "historia", "ciencia", "literatura::Roma", "argentina"] {
            try engine.pin(tag)
        }
        try engine.setAside("ciencia")
        try engine.setAside("literatura")

        try engine.togglePriority(of: "historia")
        try engine.togglePriority(of: "filosofía")
        try engine.togglePriority(of: "ética")
        try engine.edit(
            mayo.id, with: card(.word, front: "Revolución de Mayo", back: "Mayo de 1810.", tags: ["argentina"]))

        let menu = try engine.prioritizeMenu()
        #expect(before.isEmpty)
        #expect(
            menu.items.map(\.label) == [
                "None", "lenguaje", "historia", "argentina", "ética", "filosofía", "All Tags…",
            ])
        #expect(menu.tags.map(\.isPriority) == [false, true, false, true, true])
        #expect(menu.tags.map(\.isPinned) == [true, true, true, false, false])
    }

    @Test(
        "the Prioritize submenu ticks None while no tag is a priority tag, and its title names the priority tags alphabetically once some are"
    )
    func theSubmenuTicksNoneAndNamesThePriorityTags() throws {
        try approveCard("ubuntu", tags: ["lenguaje", "filosofía"])
        try approveCard("Revolución de Mayo", tags: ["historia", "argentina"])
        #expect(try engine.prioritizeMenu().isNoneTicked)
        #expect(try engine.prioritizeMenu().priorityTagNames.isEmpty)

        try engine.togglePriority(of: "historia")
        try engine.togglePriority(of: "filosofía")

        let menu = try engine.prioritizeMenu()
        #expect(!menu.isNoneTicked)
        #expect(menu.priorityTagNames == ["filosofía", "historia"])
    }

    @Test(
        "clearing the priority tags brings the cards in today's order, and leaves the pinned tags alone in the submenu"
    )
    func clearingThePriorityTags() throws {
        let ubuntu = try meetCard("ubuntu", tags: ["lenguaje"])
        let eudaimonia = try meetCard("eudaimonía", tags: ["filosofía"])
        time.advance(by: hours(1))
        try engine.pin("lenguaje")
        try engine.togglePriority(of: "filosofía")
        try engine.togglePriority(of: "historia")
        #expect(try engine.reviewNow(settings) == [eudaimonia, ubuntu].map { PanelCard.review($0) })

        try engine.clearPriorityTags()

        #expect(try engine.reviewNow(settings) == [ubuntu, eudaimonia].map { PanelCard.review($0) })
        #expect(try engine.prioritizeMenu().tags.map(\.name) == ["lenguaje"])
    }

    // A tag is a priority tag, set aside, or neither (ADR 0011).
    @Test(
        "setting aside a priority tag drops its priority, the submenu leaves set-aside tags out, and toggling one's priority is refused"
    )
    func settingAsideAPriorityTagDropsItsPriority() throws {
        let ubuntu = try approveCard("ubuntu", tags: ["filosofía"])
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try engine.pin("filosofía")
        try engine.pin("historia")
        try engine.togglePriority(of: "filosofía")

        try engine.setAside("filosofía")

        #expect(try engine.prioritizeMenu().tags.map(\.name) == ["historia"])
        #expect(throws: EngineError.tagSetAside("filosofía")) { try engine.togglePriority(of: "filosofía") }
        #expect(try engine.allTags().first?.switchedOn == .setAside)
        #expect(try engine.prioritizeMenu().tags.map(\.name) == ["historia"])
        try engine.stopSettingAside("filosofía")
        #expect(try engine.prioritizeMenu().tags.map(\.name) == ["filosofía", "historia"])
        #expect(try engine.cards().first == ubuntu)
    }

    // filosofía is set aside, and historia isn't.
    @Test(
        "setting a tag's priority makes it a priority tag or no longer one, whatever it was, and is refused on a set-aside tag"
    )
    func settingATagsPriority() throws {
        try approveCard("ubuntu", tags: ["filosofía"])
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try engine.setAside("filosofía")

        try engine.setPriority(true, of: "historia")
        try engine.setPriority(true, of: "historia")
        #expect(try engine.prioritizeMenu().priorityTagNames == ["historia"])
        try engine.setPriority(false, of: "historia")
        try engine.setPriority(false, of: "historia")
        #expect(try engine.prioritizeMenu().priorityTagNames.isEmpty)

        #expect(throws: EngineError.tagSetAside("filosofía")) { try engine.setPriority(true, of: "filosofía") }
        try engine.setPriority(false, of: "filosofía")
        #expect(try engine.allTags().first?.switchedOn == .setAside)
    }

    // The Mac's preferences are the app's, whichever database it opens, so a
    // priority tag kept there would show in another database too.
    @Test(
        "priority tags survive reopening the database, and another database has none, so nothing goes in the Mac's preferences"
    )
    func priorityTagsSurviveReopening() throws {
        let folder = URL.temporaryDirectory.appending(
            path: "FichaDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = try Engine(location: .folder(folder), time: time, calendar: calendar)
        try approve(card(.word, front: "ubuntu", back: "Humanidad.", tags: ["lenguaje"]), in: engine)
        let eudaimonia = try approve(
            card(.word, front: "eudaimonía", back: "Plenitud.", tags: ["filosofía"]), in: engine)
        try engine.togglePriority(of: "filosofía")

        let reopened = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let another = try Engine(location: .inMemory, time: time, calendar: calendar)
        let anotherUbuntu = try approve(
            card(.word, front: "ubuntu", back: "Humanidad.", tags: ["lenguaje"]), in: another)
        try approve(card(.word, front: "eudaimonía", back: "Plenitud.", tags: ["filosofía"]), in: another)

        #expect(try reopened.prioritizeMenu().priorityTagNames == ["filosofía"])
        #expect(try reopened.reviewNow(settings) == [.firstView(eudaimonia)])
        #expect(try another.prioritizeMenu().priorityTagNames.isEmpty)
        #expect(try another.reviewNow(settings) == [.firstView(anotherUbuntu)])
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

extension PrioritizeMenu.Item {
    /// What the item says in the submenu, a tag by its whole name, written
    /// with `::`.
    fileprivate var label: String {
        switch self {
        case .noPriorityTag: "None"
        case .tag(let tag): tag.name
        case .allTags: "All Tags…"
        }
    }
}
