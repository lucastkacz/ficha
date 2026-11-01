import FichaCore
import Foundation
import Testing

// For a tag's switch kept from before decks (ADR 0024), which nothing public
// sets any longer: `changeOwnTags(_:in:_:)` stands in for a database from
// then.
@testable import FichaData

/// Tests on setting a deck aside, which takes every card in it, and in every
/// deck inside it, out of Lucas's reviews for now, without burying them, and
/// on no longer setting it aside, which brings them back where they'd be
/// without it (ADR 0011, ADR 0024), with the default settings. They start at
/// 9 in the morning in Buenos Aires, when active hours start.
struct SettingAsideTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    @Test("a set-aside deck's cards leave review now, See more and the menu's counts")
    func aSetAsideDecksCardsLeaveReviewNowSeeMoreAndTheCounts() throws {
        // eudaimonía gets learned, graduated to wait 21 days or more, ubuntu
        // goes to the first learning step, and both come due. ataraxia is
        // new.
        let ubuntu = try approveCard("ubuntu", deck: "Lenguaje")
        let eudaimonia = try approveCard("eudaimonía", deck: "Filosofía")
        try approveCard("ataraxia", deck: "Filosofía")
        try engine.climbUntilLearned(eudaimonia, movingForward: time)
        try engine.meet(ubuntu)
        time.move(to: try #require(try engine.standing(of: eudaimonia.id, with: settings.scheduler).due))

        try engine.setAside(deck: "Filosofía")

        #expect(try engine.reviewNow(settings) == [.review(ubuntu)])
        #expect(try engine.openPanel(.reviewNow, with: [], settings: settings).moreCards == [.review(ubuntu)])
        let progress = try engine.progress(settings)
        #expect(progress.due == 1)
        #expect(progress.learned == 0)
    }

    @Test("no appearance comes for a set-aside deck's cards, and none is planned for them")
    func noAppearanceComesForASetAsideDecksCards() throws {
        try meetCard("eudaimonía", deck: "Filosofía", dueAt: try at(10, 0))
        try engine.setAside(deck: "Filosofía")

        time.move(to: try at(10, 0))

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .notNow(.nothingDue))
        #expect(try engine.upcomingAppearances(settings).isEmpty)
    }

    @Test("appearances, planned appearances and card notifications leave out a set-aside deck's cards")
    func appearancesAndCardNotificationsLeaveOutASetAsideDecksCards() throws {
        let ubuntu = try meetCard("ubuntu", deck: "Lenguaje", dueAt: try at(10, 0))
        let eudaimonia = try meetCard("eudaimonía", deck: "Filosofía", dueAt: try at(10, 0))
        let petricor = try meetCard("petricor", dueAt: try at(10, 0))
        time.move(to: try at(10, 0))
        // Planned before the deck was set aside, as the iPhone's card
        // notifications are.
        let notified = NotifiedAppearance(try #require(try engine.upcomingAppearances(settings).first))
        #expect(notified.cardIDs == [ubuntu.id, eudaimonia.id, petricor.id])

        try engine.setAside(deck: "Filosofía")

        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.review(ubuntu), .review(petricor)]))
        #expect(try engine.upcomingAppearances(settings).first?.cards == [.review(ubuntu), .review(petricor)])
        let next = try engine.answerFromNotification(.review(.good), of: ubuntu.id, in: notified, settings: settings)
        #expect(next == .review(petricor))
    }

    @Test(
        "a card in a set-aside deck inside a priority deck is left out of appearances, review now and See more, and the priority deck's other cards still come first"
    )
    func aCardInASetAsideDeckInsideAPriorityDeckIsLeftOut() throws {
        let ubuntu = try meetCard("ubuntu", deck: "Lenguaje", dueAt: try at(10, 0))
        let coliseo = try meetCard("Coliseo", deck: "Historia::Roma", dueAt: try at(10, 1))
        let mayo = try meetCard("Revolución de Mayo", deck: "Historia", dueAt: try at(10, 2))
        time.move(to: try at(10, 2))
        try engine.togglePriority(ofDeck: "Historia")
        #expect(try engine.reviewNow(settings) == [.review(coliseo), .review(mayo), .review(ubuntu)])

        try engine.setAside(deck: "Historia::Roma")

        let expected: [PanelCard] = [.review(mayo), .review(ubuntu)]
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show(expected))
        #expect(try engine.reviewNow(settings) == expected)
        #expect(try engine.openPanel(.reviewNow, with: [], settings: settings).moreCards == expected)
    }

    @Test(
        "a card in a deck inside a set-aside deck is set aside, by every set-aside deck it sits in, the outermost first"
    )
    func aCardInADeckInsideASetAsideDeckIsSetAside() throws {
        let ubuntu = try approveCard("ubuntu", deck: "Filosofía::Ética")

        try engine.setAside(deck: "Filosofía::Ética")
        try engine.setAside(deck: "Filosofía")

        #expect(try engine.cards().map(\.standing) == [.setAside(by: ["Filosofía", "Filosofía::Ética"])])
        #expect(try engine.reviewNow(settings).isEmpty)
        try engine.stopSettingAside(deck: "Filosofía::Ética")
        #expect(try engine.cards().map(\.standing) == [.setAside(by: ["Filosofía"])])
        #expect(ubuntu.standing == .inReviews)
    }

    // Change Deck moves cards, and a refine session approves new cards into
    // the deck. serendipia gets to the second step, which waits 4 hours, and
    // comes due while it's set aside.
    @Test(
        "a card moved into a set-aside deck, or into a deck inside one, leaves Lucas's reviews, and moved out comes back where it stood, due when it was"
    )
    func aCardMovedIntoASetAsideDeckLeavesReviews() throws {
        let serendipia = try approveCard("serendipia")
        let coliseo = try approveCard("Coliseo")
        try engine.climb(serendipia, goods: 1, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: settings.scheduler)
        try engine.setAside(deck: "Historia")

        let mayo = try approveCard("Revolución de Mayo", deck: "Historia")
        try engine.changeDeck(of: [serendipia.id], to: "Historia")
        try engine.changeDeck(of: [coliseo.id], to: "Historia::Roma")
        time.advance(by: hours(5))

        #expect(mayo.standing == .setAside(by: ["Historia"]))
        #expect(try engine.cards().map(\.standing) == Array(repeating: .setAside(by: ["Historia"]), count: 3))
        #expect(try engine.reviewNow(settings).isEmpty)
        try engine.changeDeck(of: [serendipia.id, coliseo.id], to: Deck.defaultName)
        #expect(try engine.cards().map(\.standing) == [.inReviews, .inReviews, .setAside(by: ["Historia"])])
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == standing)
        #expect(try engine.reviewNow(settings) == [.review(serendipia), .new(coliseo)])
    }

    // Historia::Roma became a priority deck before Historia was set aside,
    // and stays one, to untick.
    @Test("a priority deck inside a set-aside deck brings none of its cards to review now, See more or appearances")
    func aPriorityDeckInsideASetAsideDeckBringsNoCard() throws {
        let ubuntu = try meetCard("ubuntu", deck: "Lenguaje", dueAt: try at(10, 0))
        try meetCard("Coliseo", deck: "Historia::Roma", dueAt: try at(10, 1))
        try approveCard("Foro Romano", deck: "Historia::Roma")
        time.move(to: try at(10, 1))
        try engine.togglePriority(ofDeck: "Historia::Roma")

        try engine.setAside(deck: "Historia")

        #expect(try engine.prioritizeMenu().priorityDeckNames == ["Historia::Roma"])
        #expect(try engine.reviewNow(settings) == [.review(ubuntu)])
        #expect(try engine.openPanel(.reviewNow, with: [], settings: settings).moreCards == [.review(ubuntu)])
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.review(ubuntu)]))
    }

    @Test("Default can be set aside, which takes out its cards alone, and Default goes by its name, empty")
    func defaultCanBeSetAside() throws {
        let petricor = try approveCard("petricor")
        let gioconda = try approveCard("Gioconda", deck: "Arte")

        try engine.setAside(deck: Deck.defaultName)

        #expect(try engine.cards().map(\.standing) == [.setAside(by: [Deck.defaultName]), .inReviews])
        #expect(try engine.reviewNow(settings) == [.new(gioconda)])
        #expect(throws: EngineError.cardSetAside(petricor.id, decks: [Deck.defaultName])) {
            try engine.meet(petricor)
        }
        try engine.stopSettingAside(deck: Deck.defaultName)
        #expect(try engine.cards().map(\.standing) == [.inReviews, .inReviews])
    }

    @Test(
        "stopping setting a deck aside brings its cards back where they stood, with the cards that came due meanwhile due"
    )
    func stoppingSettingADeckAsideBringsItsCardsBack() throws {
        // eudaimonía gets to the second step, which waits 4 hours, and
        // ataraxia is new.
        let eudaimonia = try approveCard("eudaimonía", deck: "Filosofía")
        let ataraxia = try approveCard("ataraxia", deck: "Filosofía")
        try engine.climb(eudaimonia, goods: 1, movingForward: time)
        let standing = try engine.standing(of: eudaimonia.id, with: settings.scheduler)
        try engine.setAside(deck: "Filosofía")
        time.advance(by: days(2))
        #expect(try engine.reviewNow(settings).isEmpty)

        try engine.stopSettingAside(deck: "Filosofía")

        #expect(try engine.standing(of: eudaimonia.id, with: settings.scheduler) == standing)
        #expect(try engine.reviewNow(settings) == [.review(eudaimonia), .new(ataraxia)])
        #expect(try engine.progress(settings).due == 1)
        #expect(try engine.reviewLog().map(\.cardID) == [eudaimonia.id, eudaimonia.id])
    }

    @Test(
        "setting a deck aside takes both ways of its cards out of reviews, and stopping brings both back where they stood"
    )
    func settingADeckAsideTakesOutBothWays() throws {
        let eudaimonia = try approveCard("eudaimonía", deck: "Filosofía")
        let bothWays = try engine.setBothWays(true, of: [eudaimonia.id])
        try engine.meet(eudaimonia)
        try engine.meet(eudaimonia, way: .backFirst)
        time.advance(by: hours(1))

        try engine.setAside(deck: "Filosofía")
        let whileSetAside = try engine.reviewNow(settings)
        try engine.stopSettingAside(deck: "Filosofía")

        #expect(whileSetAside.isEmpty)
        #expect(try engine.reviewNow(settings) == [.review(bothWays[0]), .review(bothWays[0], .backFirst)])
    }

    // Buried, then the inbox, then set aside, then reviews (ADR 0011).
    @Test(
        "a flagged card stays in the inbox and a buried card stays buried whatever their deck, and fixing or unburying a card in a set-aside deck leaves it set aside"
    )
    func theInboxAndBurialsWinOverSetAside() throws {
        let ubuntu = try approveCard("ubuntu", deck: "Filosofía")
        let eudaimonia = try approveCard("eudaimonía", deck: "Filosofía")
        let flag = try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let buried = try engine.bury(eudaimonia.id)

        try engine.setAside(deck: "Filosofía")

        #expect(try engine.inbox().flaggedCards.map(\.id) == [ubuntu.id])
        #expect(try engine.progress(settings).inInbox == 1)
        #expect(
            try engine.cards().map(\.standing) == [
                .inInbox(try #require(flag.flag)), .buried(at: try #require(buried.buriedAt), flag: nil),
            ])
        let fixed = try engine.fix(ubuntu.id, with: card(.word, front: "ubuntu", back: "Humanidad hacia los otros."))
        let unburied = try engine.unbury(eudaimonia.id)
        #expect(fixed.standing == .setAside(by: ["Filosofía"]))
        #expect(unburied.standing == .setAside(by: ["Filosofía"]))
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.reviewNow(settings).isEmpty)
    }

    // The review panel shows it as it shows a buried card's.
    @Test("answering a set-aside card is refused, naming its set-aside decks, and the review log doesn't change")
    func answeringASetAsideCardIsRefused() throws {
        let ubuntu = try approveCard("ubuntu", deck: "Filosofía::Ética")
        try engine.setAside(deck: "Filosofía::Ética")
        try engine.setAside(deck: "Filosofía")

        #expect(throws: EngineError.cardSetAside(ubuntu.id, decks: ["Filosofía", "Filosofía::Ética"])) {
            try engine.meet(ubuntu)
        }
        #expect(try engine.reviewLog().isEmpty)
    }

    @Test("a set-aside card can be flagged, buried, edited and expanded, as a card in Lucas's reviews can")
    func aSetAsideCardCanBeFlaggedBuriedEditedAndExpanded() throws {
        let ubuntu = try approveCard("ubuntu", deck: "Filosofía")
        let eudaimonia = try approveCard("eudaimonía", deck: "Filosofía")
        let ataraxia = try approveCard("ataraxia", deck: "Filosofía")
        try engine.setAside(deck: "Filosofía")

        let flagged = try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let buried = try engine.bury(eudaimonia.id)
        let edited = try engine.edit(ataraxia.id, with: card(.concept, front: "ataraxia", back: "Serenidad."))
        let expansion = try engine.expand(text: "ataraxia", note: "Es de Epicuro", source: nil)
        let expanded = try engine.approveExpansion(
            expansion.id, into: card(.concept, front: "ataraxia", back: "Serenidad, según Epicuro."))

        #expect(flagged.standing == .inInbox(try #require(flagged.flag)))
        #expect(buried.standing == .buried(at: time.now, flag: nil))
        #expect(edited.standing == .setAside(by: ["Filosofía"]))
        #expect(expansion.expandsCardID == ataraxia.id)
        #expect(expanded.back == "Serenidad, según Epicuro.")
        #expect(expanded.standing == .setAside(by: ["Filosofía"]))
    }

    // A deck stays while it has a row (ADR 0024), so a set-aside deck no card
    // lives in stays listed, to untick.
    @Test(
        "setting aside a deck that isn't there makes it, and stopping keeps it, while stopping on a deck that isn't there makes none"
    )
    func settingAsideMakesTheDeckAndStoppingMakesNone() throws {
        try approveCard("ubuntu", deck: "Lenguaje")

        try engine.setAside(deck: " Historia :: Roma ")
        #expect(try engine.decks().map(\.name) == ["Historia", "Historia::Roma", "Lenguaje"])
        #expect(try engine.decks().map(\.isSetAside) == [false, true, false])

        try engine.stopSettingAside(deck: "Historia::Roma")
        try engine.stopSettingAside(deck: "Historia::Roma")
        try engine.stopSettingAside(deck: "Música")

        #expect(try engine.decks().map(\.name) == ["Historia", "Historia::Roma", "Lenguaje"])
        #expect(try engine.decks().map(\.isSetAside) == [false, false, false])
        #expect(throws: EngineError.blankDeckName) { try engine.setAside(deck: " :: ") }
        #expect(throws: EngineError.defaultDeckName("Default")) { try engine.setAside(deck: "Default::Viejo") }
    }

    // `ficha cards` prints the cards this way, for a refine session to know.
    @Test("a card's encoding has setAsideBy for a card in a set-aside deck, and leaves it out otherwise")
    func aCardsEncodingHasSetAsideByWhenItsDeckIsSetAside() throws {
        try approveCard("ubuntu", deck: "Filosofía::Ética")
        try approveCard("serendipia", deck: "Lenguaje")
        try engine.setAside(deck: "Filosofía")
        try engine.setAside(deck: "Filosofía::Ética")

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cards()))
        let cards = try #require(encoded as? [[String: Any]])

        #expect(cards.map { $0["setAsideBy"] as? [String] } == [["Filosofía", "Filosofía::Ética"], nil])
        #expect(cards.map { $0.keys.contains("setAsideBy") } == [true, false])
    }

    // A tag only labels its cards (ADR 0024). A switch a tag had before decks
    // stays in its row for the conversion of Lucas's tags into decks.
    @Test(
        "a tag sets no card aside, even one named as a set-aside deck, and a tag's switch from before decks counts nowhere"
    )
    func aTagSetsNoCardAside() throws {
        let ubuntu = try approveCard("ubuntu", tags: ["Filosofía"])
        let eudaimonia = try approveCard("eudaimonía", tags: ["ética"])
        let petricor = try approveCard("petricor", tags: ["lenguaje"])
        try engine.setAside(deck: "Filosofía")
        try engine.write { db in
            try changeOwnTags(["ética"], in: db) { $0.switchedOn = .setAside }
            try changeOwnTags(["lenguaje"], in: db) { $0.switchedOn = .priority }
        }

        #expect(try engine.cards().map(\.standing) == [.inReviews, .inReviews, .inReviews])
        #expect(try engine.reviewNow(settings) == [.new(ubuntu)])
        try engine.meet(ubuntu)
        try engine.meet(eudaimonia)
        try engine.meet(petricor)
        time.advance(by: hours(1))
        #expect(try engine.reviewNow(settings) == [ubuntu, eudaimonia, petricor].map { PanelCard.review($0) })
    }

    /// Approves a card with this front, in this deck, and meets it, an hour
    /// before `due`, so that it's due then, after the first step's wait. Each card is met after the ones before it, so they
    /// come due in order.
    @discardableResult
    private func meetCard(_ front: String, deck: String = Deck.defaultName, dueAt due: Date) throws -> Card {
        let card = try approveCard(front, deck: deck)
        time.move(to: due - hours(1))
        try engine.meet(card)
        return card
    }

    /// A time of day on October 14, 2026, by the tests' calendar.
    private func at(_ hour: Int, _ minute: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute)))
    }

    /// Approves a capture into one word card with this front and these tags,
    /// the way refining saves cards, moves it to `deck` with Change Deck,
    /// and returns the card as it is then.
    @discardableResult
    private func approveCard(_ front: String, deck: String = Deck.defaultName, tags: [String] = []) throws -> Card {
        try approveInDeck(front, deck: deck, tags: tags, in: engine)
    }
}
