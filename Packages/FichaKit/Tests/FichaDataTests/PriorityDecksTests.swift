import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on priority decks, whose cards, and those of every deck inside them,
/// come first when cards show up, while the others still come when there's
/// room (ADR 0011, ADR 0024), with the default settings: 5 cards per
/// appearance and 5 new cards a day. They start at 9 in the morning in Buenos
/// Aires, when active hours start.
struct PriorityDecksTests {
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
        let ubuntu = try meetCard("ubuntu", deck: "Lenguaje")
        let eudaimonia = try meetCard("eudaimonía", deck: "Filosofía")
        let petricor = try meetCard("petricor")
        let ataraxia = try meetCard("ataraxia", deck: "Filosofía")
        time.advance(by: hours(1))
        #expect(
            try engine.reviewNow(settings) == [ubuntu, eudaimonia, petricor, ataraxia].map { PanelCard.review($0) })

        try engine.togglePriority(ofDeck: "Filosofía")

        #expect(
            try engine.reviewNow(settings) == [eudaimonia, ataraxia, ubuntu, petricor].map { PanelCard.review($0) })
    }

    @Test(
        "with 5 cards per appearance, 5 other cards due and a new priority card, under the daily limit, an appearance brings the new priority card and 4 of the other due cards, and review now does the same"
    )
    func aNewPriorityCardTakesASlotAheadOfTheOtherDueCards() throws {
        // Met the day before, so none of the day's new cards is met yet.
        let due = try ["uno", "dos", "tres", "cuatro", "cinco"].map { try meetCard($0, deck: "Lenguaje") }
        try approveCard("ataraxia")
        let eudaimonia = try approveCard("eudaimonía", deck: "Filosofía")
        time.move(to: try morning(of: 15, in: calendar))
        #expect(try engine.reviewNow(settings) == due.map { PanelCard.review($0) })

        try engine.togglePriority(ofDeck: "Filosofía")

        let expected = due.prefix(4).map { PanelCard.review($0) } + [.firstView(eudaimonia)]
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show(expected))
        #expect(try engine.reviewNow(settings) == expected)
    }

    @Test("once Lucas has met 5 new cards today, no new card comes, priority or not")
    func noNewCardComesPastTheDailyLimit() throws {
        for front in ["uno", "dos", "tres", "cuatro", "cinco"] {
            try meetCard(front, deck: "Filosofía")
        }
        try approveCard("ataraxia")
        try approveCard("eudaimonía", deck: "Filosofía")

        try engine.togglePriority(ofDeck: "Filosofía")

        #expect(try engine.reviewNow(settings).isEmpty)
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
    }

    @Test("a new card outside the priority decks still comes only when there's a slot after every due card")
    func aNewCardOutsideThePriorityDecksWaitsForEveryDueCard() throws {
        let eudaimonia = try meetCard("eudaimonía", deck: "Filosofía")
        let others = try ["uno", "dos", "tres", "cuatro"].map { try meetCard($0, deck: "Lenguaje") }
        let ataraxia = try approveCard("ataraxia")
        try engine.togglePriority(ofDeck: "Filosofía")
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
        let other = try meetCard("ubuntu", deck: "Lenguaje")
        let priority = try ["uno", "dos", "tres", "cuatro", "cinco", "seis"].map {
            try meetCard($0, deck: "Filosofía")
        }
        try approveCard("eudaimonía", deck: "Filosofía")
        time.move(to: try morning(of: 15, in: calendar))
        // Met today, the other card first, so it's due sooner: neither is due
        // for an hour.
        let otherAhead = try meetCard("petricor")
        let priorityAhead = try meetCard("ataraxia", deck: "Filosofía")
        try engine.togglePriority(ofDeck: "Filosofía")
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
        let ubuntu = try meetCard("ubuntu", deck: "Lenguaje")
        let eudaimonia = try meetCard("eudaimonía", deck: "Filosofía")
        let petricor = try approveCard("petricor")
        let bothWays = try engine.setBothWays(true, of: [ubuntu.id, eudaimonia.id])
        try engine.togglePriority(ofDeck: "Filosofía")
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

    @Test(
        "a card in a priority deck, or in a deck inside one, counts as a priority card, Default too, and a priority deck's parent doesn't"
    )
    func aCardInAPriorityDeckOrInsideOneCounts() throws {
        let ubuntu = try meetCard("ubuntu", deck: "Lenguaje")
        let mayo = try meetCard("Revolución de Mayo", deck: "Historia::Argentina")
        let petricor = try meetCard("petricor")
        let coliseo = try meetCard("Coliseo", deck: "Historia")
        let eudaimonia = try meetCard("eudaimonía", deck: "Filosofía::Ética")
        time.advance(by: hours(1))

        try engine.togglePriority(ofDeck: "Historia::Argentina")
        try engine.togglePriority(ofDeck: "Filosofía")
        try engine.togglePriority(ofDeck: Deck.defaultName)

        #expect(
            try engine.reviewNow(settings)
                == [mayo, petricor, eudaimonia, ubuntu, coliseo].map { PanelCard.review($0) })
    }

    @Test("a card moved into a priority deck comes first, and moved out no longer does")
    func aCardMovedIntoAPriorityDeckComesFirst() throws {
        let ubuntu = try meetCard("ubuntu", deck: "Lenguaje")
        let eudaimonia = try meetCard("eudaimonía")
        time.advance(by: hours(1))
        try engine.togglePriority(ofDeck: "Filosofía")

        try engine.changeDeck(of: [eudaimonia.id], to: "Filosofía::Ética")
        let moved = try engine.cards()[1]
        let movedIn = try engine.reviewNow(settings)
        try engine.changeDeck(of: [eudaimonia.id], to: Deck.defaultName)

        #expect(movedIn == [moved, ubuntu].map { PanelCard.review($0) })
        #expect(try engine.reviewNow(settings) == [ubuntu, eudaimonia].map { PanelCard.review($0) })
    }

    @Test("each card's step and due time are the same with or without priority decks")
    func priorityDecksChangeNoStepOrDueTime() throws {
        let ubuntu = try approveCard("ubuntu", deck: "Lenguaje")
        let eudaimonia = try approveCard("eudaimonía", deck: "Filosofía")
        let ataraxia = try approveCard("ataraxia", deck: "Filosofía")
        try engine.climb(ubuntu, to: 2, movingForward: time)
        try engine.climb(eudaimonia, to: 1, movingForward: time)
        let cards = [ubuntu, eudaimonia, ataraxia]
        let standings = try cards.map { try engine.standing(of: $0.id, on: settings.ladder) }

        try engine.togglePriority(ofDeck: "Filosofía")

        #expect(try cards.map { try engine.standing(of: $0.id, on: settings.ladder) } == standings)
    }

    // A new priority card fits beside the cards due within the look-ahead,
    // where a new card without priority wouldn't, but that mustn't bring the
    // appearance before one would come without priority decks.
    @Test("an appearance comes when it would without priority decks, even when a new priority card would fit")
    func anAppearanceComesWhenItWouldWithoutPriorityDecks() throws {
        // Five cards climb to the third step, which waits 2 days, so they
        // come due on the 16th at 14:00, when none of that day's new cards is
        // met yet.
        let lenguaje = try ["uno", "dos", "tres", "cuatro"].map { try approveCard($0, deck: "Lenguaje") }
        let cinco = try approveCard("cinco", deck: "Filosofía")
        for card in lenguaje + [cinco] {
            try engine.meet(card)
        }
        for wait in [hours(1), hours(4)] {
            time.advance(by: wait)
            for card in lenguaje + [cinco] {
                try engine.review(card, .good)
            }
        }
        let eudaimonia = try approveCard("eudaimonía", deck: "Filosofía")
        let dueTime = time.now + days(2)
        try engine.togglePriority(ofDeck: "Filosofía")

        // They're due within the 20-minute look-ahead, but none is due yet.
        time.move(to: dueTime - minutes(15))
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
        time.move(to: dueTime)
        #expect(
            try engine.checkAppearance(settings, mac: FakeMac())
                == .show([.review(cinco)] + lenguaje.prefix(3).map { PanelCard.review($0) } + [.firstView(eudaimonia)]))
    }

    // Ciencia is set aside, with no card, and Literatura is set aside after
    // Literatura::Roma became a priority deck, which stays to be unticked.
    @Test(
        "the Prioritize submenu lists every deck as a tree, Default first while it holds cards, ticks the priority decks, and turns off the set-aside ones but a priority one"
    )
    func theSubmenuListsTheDecksAsATree() throws {
        let before = try engine.prioritizeMenu().decks
        try approveCard("ubuntu")
        try approveCard("Revolución de Mayo", deck: "Historia::Argentina")
        try approveCard("eudaimonía", deck: "Filosofía::Ética")
        try approveCard("Coliseo", deck: "Literatura::Roma")
        try approveCard("Martín Fierro", deck: "Literatura::Poesía")
        try engine.setAside(deck: "Ciencia")
        try engine.togglePriority(ofDeck: "Historia")
        try engine.togglePriority(ofDeck: "Filosofía::Ética")
        try engine.togglePriority(ofDeck: "Literatura::Roma")
        try engine.setAside(deck: "Literatura")

        let menu = try engine.prioritizeMenu()

        #expect(before.isEmpty)
        #expect(
            menu.decks.flatMap(\.lines) == [
                "", "Ciencia (off)", "Filosofía", "  Ética ✓", "Historia ✓", "  Argentina", "Literatura (off)",
                "  Poesía (off)", "  Roma ✓",
            ])
        #expect(menu.decks.map(\.id) == ["", "Ciencia", "Filosofía", "Historia", "Literatura"])
        #expect(menu.decks[2].children.map(\.id) == ["Filosofía::Ética"])
    }

    @Test(
        "the Prioritize submenu ticks None while no deck is a priority deck, and its title names the priority decks as a tree lists them once some are"
    )
    func theSubmenuTicksNoneAndNamesThePriorityDecks() throws {
        try approveCard("ubuntu", deck: "Lenguaje")
        try approveCard("Revolución de Mayo", deck: "Historia::Argentina")
        #expect(try engine.prioritizeMenu().isNoneTicked)
        #expect(try engine.prioritizeMenu().priorityDeckNames.isEmpty)

        try engine.togglePriority(ofDeck: "Lenguaje")
        try engine.togglePriority(ofDeck: "Historia::Argentina")
        try engine.togglePriority(ofDeck: "Historia")

        let menu = try engine.prioritizeMenu()
        #expect(!menu.isNoneTicked)
        #expect(menu.priorityDeckNames == ["Historia", "Historia::Argentina", "Lenguaje"])
    }

    @Test("clearing the priority decks brings the cards in today's order, and leaves every deck in the submenu")
    func clearingThePriorityDecks() throws {
        let ubuntu = try meetCard("ubuntu", deck: "Lenguaje")
        let eudaimonia = try meetCard("eudaimonía", deck: "Filosofía")
        time.advance(by: hours(1))
        try engine.togglePriority(ofDeck: "Filosofía")
        try engine.togglePriority(ofDeck: "Historia")
        #expect(try engine.reviewNow(settings) == [eudaimonia, ubuntu].map { PanelCard.review($0) })

        try engine.clearPriorityDecks()

        #expect(try engine.reviewNow(settings) == [ubuntu, eudaimonia].map { PanelCard.review($0) })
        let menu = try engine.prioritizeMenu()
        #expect(menu.isNoneTicked)
        #expect(menu.decks.map(\.id) == ["Filosofía", "Historia", "Lenguaje"])
    }

    // A deck is a priority deck, set aside, or neither (ADR 0011).
    @Test(
        "setting aside a priority deck drops its priority, the submenu turns it off, and toggling its priority is refused"
    )
    func settingAsideAPriorityDeckDropsItsPriority() throws {
        let ubuntu = try approveCard("ubuntu", deck: "Filosofía")
        try approveCard("Revolución de Mayo", deck: "Historia")
        try engine.togglePriority(ofDeck: "Filosofía")

        try engine.setAside(deck: "Filosofía")

        #expect(try engine.prioritizeMenu().decks.flatMap(\.lines) == ["Filosofía (off)", "Historia"])
        #expect(throws: EngineError.deckSetAside("Filosofía")) { try engine.togglePriority(ofDeck: "Filosofía") }
        #expect(try engine.decks().first?.switchedOn == .setAside)
        try engine.stopSettingAside(deck: "Filosofía")
        #expect(try engine.prioritizeMenu().decks.flatMap(\.lines) == ["Filosofía", "Historia"])
        #expect(try engine.cards().first == ubuntu)
    }

    // Filosofía is set aside, and Historia isn't.
    @Test(
        "setting a deck's priority makes it a priority deck or no longer one, whatever it was, and is refused on a set-aside deck"
    )
    func settingADecksPriority() throws {
        try approveCard("ubuntu", deck: "Filosofía")
        try approveCard("Revolución de Mayo", deck: "Historia")
        try engine.setAside(deck: "Filosofía")

        try engine.setPriority(true, ofDeck: "Historia")
        try engine.setPriority(true, ofDeck: "Historia")
        #expect(try engine.prioritizeMenu().priorityDeckNames == ["Historia"])
        try engine.setPriority(false, ofDeck: "Historia")
        try engine.setPriority(false, ofDeck: "Historia")
        #expect(try engine.prioritizeMenu().priorityDeckNames.isEmpty)

        #expect(throws: EngineError.deckSetAside("Filosofía")) { try engine.setPriority(true, ofDeck: "Filosofía") }
        try engine.setPriority(false, ofDeck: "Filosofía")
        #expect(try engine.decks().first?.switchedOn == .setAside)
    }

    // Literatura::Roma was a priority deck before Literatura was set aside,
    // and Literatura::Poesía::Gauchesca never was.
    @Test(
        "a deck inside a set-aside deck can't become a priority deck, as the submenu turns it off, but one that is stops being one"
    )
    func prioritizingADeckInsideASetAsideDeck() throws {
        try approveCard("Coliseo", deck: "Literatura::Roma")
        try approveCard("Martín Fierro", deck: "Literatura::Poesía::Gauchesca")
        try engine.setPriority(true, ofDeck: "Literatura::Roma")
        try engine.setAside(deck: "Literatura")

        #expect(throws: EngineError.deckSetAside("Literatura")) {
            try engine.togglePriority(ofDeck: "Literatura::Poesía::Gauchesca")
        }
        #expect(try engine.prioritizeMenu().priorityDeckNames == ["Literatura::Roma"])
        try engine.togglePriority(ofDeck: "Literatura::Roma")
        #expect(try engine.prioritizeMenu().priorityDeckNames.isEmpty)
        #expect(throws: EngineError.deckSetAside("Literatura")) {
            try engine.togglePriority(ofDeck: "Literatura::Roma")
        }
    }

    @Test("unticking a deck's priority never makes a deck, and making one a priority deck does, as Change Deck does")
    func prioritizingMakesTheDeckAndUntickingMakesNone() throws {
        try approveCard("ubuntu", deck: "Lenguaje")

        try engine.setPriority(false, ofDeck: "Música")
        try engine.clearPriorityDecks()
        #expect(try engine.decks().map(\.name) == ["Lenguaje"])

        try engine.togglePriority(ofDeck: " Historia :: Roma ")
        #expect(try engine.prioritizeMenu().priorityDeckNames == ["Historia::Roma"])
        #expect(throws: EngineError.blankDeckName) { try engine.togglePriority(ofDeck: "  ") }
    }

    // The Mac's preferences are the app's, whichever database it opens, so a
    // priority deck kept there would show in another database too.
    @Test(
        "priority decks survive reopening the database, and another database has none, so nothing goes in the Mac's preferences"
    )
    func priorityDecksSurviveReopening() throws {
        let folder = URL.temporaryDirectory.appending(
            path: "FichaDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = try Engine(location: .folder(folder), time: time, calendar: calendar)
        try approveInDeck("ubuntu", deck: "Lenguaje", in: engine)
        let eudaimonia = try approveInDeck("eudaimonía", deck: "Filosofía", in: engine)
        try engine.togglePriority(ofDeck: "Filosofía")

        let reopened = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let another = try Engine(location: .inMemory, time: time, calendar: calendar)
        let anotherUbuntu = try approveInDeck("ubuntu", deck: "Lenguaje", in: another)
        try approveInDeck("eudaimonía", deck: "Filosofía", in: another)

        #expect(try reopened.prioritizeMenu().priorityDeckNames == ["Filosofía"])
        #expect(try reopened.reviewNow(settings) == [.firstView(eudaimonia)])
        #expect(try another.prioritizeMenu().priorityDeckNames.isEmpty)
        #expect(try another.reviewNow(settings) == [.firstView(anotherUbuntu)])
    }

    /// Approves a card with this front in this deck and meets it now, so
    /// that it's due an hour later, after the first step's wait, and then
    /// moves time a minute forward, so the next card met comes due after it.
    @discardableResult
    private func meetCard(_ front: String, deck: String = Deck.defaultName) throws -> Card {
        let card = try approveCard(front, deck: deck)
        try engine.meet(card)
        time.advance(by: minutes(1))
        return card
    }

    /// Approves a capture into one word card with this front, the way
    /// refining saves cards, moves it to `deck` with Change Deck, and returns
    /// the card as it is then: a new card, after the ones approved before it.
    @discardableResult
    private func approveCard(_ front: String, deck: String = Deck.defaultName) throws -> Card {
        try approveInDeck(front, deck: deck, in: engine)
    }
}

extension PrioritizeMenu.DeckItem {
    /// The lines the item and the items inside it show, each indented by its
    /// level, by its title, ticked with "✓" and "(off)" when it's off.
    fileprivate var lines: [String] {
        let line = title + (isTicked ? " ✓" : "") + (isEnabled ? "" : " (off)")
        return [line] + children.flatMap(\.lines).map { "  " + $0 }
    }
}
