import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the review panel while it's open: how it closes, when an
/// appearance's panel takes the keyboard, how long Lucas takes on a card,
/// and the deck and the tags each card comes with, with the default settings. Left untouched for 10 minutes, the panel closes
/// on its own, and an appearance's panel takes the keyboard once Lucas has
/// been idle for 5 seconds.
struct ReviewPanelTests {
    let calendar: Calendar
    let time: ManualTimeSource
    /// The steady clock the panel times Lucas on.
    let clock = ManualClock()
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("a panel left untouched for 10 minutes closes on its own, which counts as a snooze")
    func anUntouchedPanelClosesOnItsOwn() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.appearance, with: [.new(serendipia)], settings: settings)

        time.advance(by: minutes(10) - 1)
        panel.closeIfUntouched()
        #expect(panel.outcome == nil)
        time.advance(by: 1)
        panel.closeIfUntouched()

        #expect(panel.outcome == .autoClosed)
        #expect(try engine.appearanceLog().map(\.outcome) == [.autoClosed])
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == .new)
    }

    @Test("doing something in the panel keeps it open for another 10 minutes")
    func touchingThePanelKeepsItOpen() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.appearance, with: [.new(serendipia)], settings: settings)

        time.advance(by: minutes(5))
        panel.touch()
        time.advance(by: minutes(10) - 1)
        panel.closeIfUntouched()
        #expect(panel.outcome == nil)
        time.advance(by: 1)
        panel.closeIfUntouched()

        #expect(panel.outcome == .autoClosed)
    }

    // So Lucas can ask for more cards, or undo the last one.
    @Test("once Lucas answered every card, the panel stays open, and closing it then finishes it")
    func thePanelStaysOpenOnceEveryCardIsAnswered() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let start = time.now
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        time.advance(by: 8)

        try panel.answer(.review(.again), responseTime: .seconds(8))
        #expect(panel.current == nil)
        #expect(panel.outcome == nil)
        panel.close(.byLucas)

        #expect(panel.outcome == .finished)
        #expect(
            try engine.appearanceLog() == [
                AppearanceLogEntry(trigger: .reviewNow, shownAt: start, closedAt: start + 8, outcome: .finished)
            ]
        )
        #expect(
            try engine.standing(of: serendipia.id, with: settings.scheduler).stageAndDue
                == learning(step: 0, due: start + 8 + hours(1)))
    }

    @Test("closed with cards left, the panel is snoozed, and the cards Lucas didn't answer stay as they were")
    func closingWithCardsLeftSnoozes() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        try engine.meet(petricor)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.appearance, with: [.review(ubuntu), .review(petricor)], settings: settings)

        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.close(.byLucas)

        #expect(panel.outcome == .snoozed)
        #expect(try engine.appearanceLog().map(\.outcome) == [.snoozed])
        #expect(try engine.standing(of: petricor.id, with: settings.scheduler).isDue(at: time.now))
    }

    @Test("an appearance's panel takes the keyboard once Lucas has been idle for 5 seconds, and only once")
    func anAppearanceTakesTheKeyboardOnceIdle() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.appearance, with: [.new(serendipia)], settings: settings)
        #expect(!panel.mayHaveKeyboard)

        let takesItBeforeFiveSeconds = panel.takesKeyboard(on: FakeMac(idleTime: .milliseconds(4_999)))
        let takesItAtFiveSeconds = panel.takesKeyboard(on: FakeMac(idleTime: .seconds(5)))
        let takesItAgain = panel.takesKeyboard(on: FakeMac(idleTime: .seconds(60)))

        #expect(!takesItBeforeFiveSeconds)
        #expect(takesItAtFiveSeconds)
        #expect(!takesItAgain)
        #expect(panel.mayHaveKeyboard)
    }

    // Without the idle time, the panel can't tell whether Lucas is typing.
    @Test("an appearance's panel doesn't take the keyboard when the Mac doesn't say how long Lucas has been idle")
    func anAppearanceWaitsForTheIdleTime() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.appearance, with: [.new(serendipia)], settings: settings)

        let takesIt = panel.takesKeyboard(on: FakeMac(idleTime: nil))

        #expect(!takesIt)
        #expect(!panel.mayHaveKeyboard)
    }

    @Test("once Lucas clicks an appearance's panel, it has the keyboard and doesn't take it again on its own")
    func clickingThePanelGivesItTheKeyboard() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.appearance, with: [.new(serendipia)], settings: settings)

        panel.clicked()
        let takesItOnItsOwn = panel.takesKeyboard(on: FakeMac(idleTime: .seconds(60)))

        #expect(panel.mayHaveKeyboard)
        #expect(!takesItOnItsOwn)
    }

    @Test("review now's panel has the keyboard from the start: Lucas opened it")
    func reviewNowHasTheKeyboard() throws {
        try approveCard("serendipia", in: engine)

        let panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        #expect(panel.mayHaveKeyboard)
    }

    @Test(
        "writing a flag's note leaves its time out of the card's response time, and cancelling it goes on from where it waited"
    )
    func writingANoteWaits() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings, clock: clock)

        clock.advance(by: .seconds(3))
        panel.startFlagging()
        panel.write(note: "Falta un ejemplo")
        clock.advance(by: .seconds(20))
        panel.cancelFlagging()
        clock.advance(by: .seconds(2))
        panel.flip()
        panel.rate(.good)

        #expect(try engine.reviewLog().last?.responseTime == .seconds(5))
    }

    // The Cards window can delete the card the panel shows.
    @Test("burying a card that was deleted meanwhile leaves the panel on it, and records that the bury failed")
    func aFailedBuryLeavesTheCard() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings, clock: clock)
        try engine.delete([serendipia.id])

        panel.buryCard()

        #expect(panel.failure?.action == .bury)
        #expect(panel.failure?.error == .cardNotFound(serendipia.id))
        #expect(panel.content == .upperSide(serendipia, isNew: true))
        panel.dismissFailure()
        #expect(panel.failure == nil)
    }

    // The Cards window can set aside the deck of the card the panel shows, as
    // it can bury the card.
    @Test("answering a card whose deck was set aside after the panel opened fails as answering a buried one does")
    func answeringACardSetAsideMeanwhileFailsAsABuriedOneDoes() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveInDeck("ubuntu", deck: "Filosofía", in: engine)
        var buriedPanel = try engine.openPanel(.reviewNow, with: [.new(serendipia)], settings: settings)
        var setAsidePanel = try engine.openPanel(.reviewNow, with: [.new(ubuntu)], settings: settings)
        try engine.bury(serendipia.id)
        try engine.setAside(deck: "Filosofía")

        buriedPanel.flip()
        buriedPanel.rate(.again)
        setAsidePanel.flip()
        setAsidePanel.rate(.again)

        #expect(buriedPanel.failure?.action == .answer)
        #expect(buriedPanel.failure?.error == .cardBuried(serendipia.id))
        #expect(setAsidePanel.failure?.action == .answer)
        #expect(setAsidePanel.failure?.error == .cardSetAside(ubuntu.id, decks: ["Filosofía"]))
        #expect(buriedPanel.content == .bothSides(serendipia, isNew: true))
        #expect(setAsidePanel.content == .bothSides(ubuntu, isNew: true))
        #expect(try engine.reviewLog().isEmpty)
    }

    // Subjects come mixed (ADR 0011): "Poder" isn't answered the same way
    // under "derecho" as under "física".
    @Test("a new card comes with its tags, in its order, each with its color and emoji")
    func aNewCardComesWithItsTags() throws {
        let mayo = try approve(
            card(
                .concept, front: "Revolución de Mayo", back: "25 de mayo de 1810.",
                tags: ["historia", "argentina", "lenguaje"]),
            in: engine)
        try engine.setColor(.blue, of: "argentina")
        try engine.setEmoji(Emoji("🇦🇷"), of: "argentina")
        try engine.setColor(.green, of: "historia")

        let panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        #expect(panel.content == .upperSide(mayo, isNew: true))
        #expect(
            panel.tags == [
                CardTag(name: "historia", color: .green),
                CardTag(name: "argentina", color: .blue, emoji: "🇦🇷"),
                CardTag(name: "lenguaje"),
            ])
    }

    @Test("a review and a review ahead come with their tags, each with its color and emoji")
    func aReviewAndAReviewAheadComeWithTheirTags() throws {
        let constituyente = try approve(
            card(.concept, front: "Poder constituyente", back: "El que crea la constitución.", tags: ["derecho"]),
            in: engine)
        let poder = try approve(
            card(.concept, front: "Poder", back: "Trabajo por unidad de tiempo.", tags: ["física", "ciencia"]),
            in: engine)
        try engine.climb(constituyente, goods: 2, movingForward: time)
        try engine.meet(poder)
        time.advance(by: hours(1))
        try engine.setEmoji(Emoji("⚖️"), of: "derecho")
        try engine.setColor(.orange, of: "física")
        // Now "Poder" is due, and "Poder constituyente", graduated, is the
        // closest to being due, for a review ahead.
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        #expect(panel.content == .upperSide(poder))
        #expect(panel.tags == [CardTag(name: "física", color: .orange), CardTag(name: "ciencia")])

        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.seeMore()

        #expect(panel.content == .upperSide(constituyente, isAhead: true))
        #expect(panel.tags == [CardTag(name: "derecho", emoji: "⚖️")])
    }

    @Test("a card with no tags comes with none")
    func aCardWithNoTagsComesWithNone() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setColor(.green, of: "ciencia")

        let panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        #expect(panel.content == .upperSide(serendipia, isNew: true))
        #expect(panel.tags.isEmpty)
    }

    // Subjects come mixed (ADR 0011, ADR 0024): the deck says which one a
    // card is about, before its tags label it.
    @Test(
        "a card comes with its deck, by its whole name, with its color and emoji, its own or its parent's, before its tags; Default's too"
    )
    func aCardComesWithItsDeckBeforeItsTags() throws {
        let mayo = try approveInDeck("Revolución de Mayo", deck: "Historia::Argentina", tags: ["política"], in: engine)
        let petricor = try approveInDeck("petricor", in: engine)
        try engine.setColor(.blue, ofDeck: "Historia")
        try engine.setEmoji(Emoji("📜"), ofDeck: "Historia")
        try engine.setEmoji(Emoji("🇦🇷"), ofDeck: "Historia::Argentina")

        var panel = try engine.openPanel(
            .appearance, with: [.new(mayo), .new(petricor)], settings: settings)

        #expect(panel.content == .upperSide(mayo, isNew: true))
        #expect(
            panel.deck
                == Deck(name: "Historia::Argentina", emoji: "🇦🇷", inheritedColor: .blue, inheritedEmoji: "📜"))
        #expect(panel.tags == [CardTag(name: "política")])
        panel.flip()
        panel.rate(.good)
        #expect(panel.content == .upperSide(petricor, isNew: true))
        #expect(panel.deck == Deck(name: Deck.defaultName))
        panel.flip()
        panel.rate(.good)
        #expect(panel.deck == nil)
    }

    // So the card Lucas is on doesn't change under him, as with its tags.
    @Test("a deck's color or emoji changed while the panel is open shows from the next panel on")
    func aDeckChangedWhileThePanelIsOpenShowsFromTheNextPanelOn() throws {
        try approveInDeck("fotosíntesis", deck: "Ciencias", in: engine)
        let open = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        try engine.setColor(.green, ofDeck: "Ciencias")
        try engine.setEmoji(Emoji("🔬"), ofDeck: "Ciencias")
        let next = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        #expect(open.deck == Deck(name: "Ciencias"))
        #expect(next.deck == Deck(name: "Ciencias", color: .green, emoji: "🔬"))
    }

    // So the card Lucas is on doesn't change under him.
    @Test("a tag's color or emoji changed while the panel is open shows from the next panel on")
    func aTagChangedWhileThePanelIsOpenShowsFromTheNextPanelOn() throws {
        try approve(card(.concept, front: "fotosíntesis", back: "Luz en azúcar.", tags: ["ciencia"]), in: engine)
        let open = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        try engine.setColor(.green, of: "ciencia")
        try engine.setEmoji(Emoji("🔬"), of: "ciencia")
        let next = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        #expect(open.tags == [CardTag(name: "ciencia")])
        #expect(next.tags == [CardTag(name: "ciencia", color: .green, emoji: "🔬")])
    }

    // Ficha Dev's debug menu moves the engine's time forward, as this test's
    // time does.
    @Test("Ficha Dev moving the time doesn't change how long Lucas took on a card")
    func movingTheTimeLeavesTheResponseTime() throws {
        try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings, clock: clock)

        clock.advance(by: .seconds(8))
        time.advance(by: hours(3))
        panel.flip()
        panel.rate(.good)

        #expect(try engine.reviewLog().map(\.responseTime) == [.seconds(8)])
    }

    @Test(
        "after the eighth “Don't know”, the panel stays on the card, flagging it with the note “Forgotten 8 times”, which Lucas can add to, and Return flags it and moves on"
    )
    func theEighthAgainOffersToFlagTheCard() throws {
        let cards = try dueCards(forgottenSevenTimes: "ubuntu", then: "petricor")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        panel.flip()

        panel.rate(.again)
        #expect(panel.content == .flagging(cards[0], showsLowerSide: true))
        #expect(panel.offersToFlag)
        #expect(panel.note == "Forgotten 8 times")
        panel.write(note: "Forgotten 8 times. Falta un ejemplo.")
        panel.finishFlagging()

        #expect(panel.content == .upperSide(cards[1]))
        #expect(!panel.offersToFlag)
        #expect(try engine.inbox().flaggedCards.map(\.flag?.note) == ["Forgotten 8 times. Falta un ejemplo."])
        #expect(try engine.reviewLog().last?.kind == .review(.again))
        // Its first review, two goods, and seven lapses, each relearned with
        // a good, before the eighth.
        #expect(try engine.reviewLog().filter { $0.cardID == cards[0].id }.count == 1 + 2 + 7 * 2 + 1)
    }

    @Test(
        "with seven lapses each way, the eighth back first offers to flag the card with the note “Forgotten 8 times back first”, and the eighth front first with “Forgotten 8 times”"
    )
    func theEighthAgainOfEachWayOffersToFlagTheCard() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let bothWays = try engine.setBothWays(true, of: [ubuntu.id])
        try engine.lapse(ubuntu, times: 7, movingForward: time)
        try engine.lapse(ubuntu, times: 7, way: .backFirst, movingForward: time)
        let dues = try [Way.frontFirst, .backFirst].map { way in
            try #require(try engine.standing(of: ubuntu.id, way: way, with: settings.scheduler).due)
        }
        time.move(to: try #require(dues.max()))
        var panel = try engine.openPanel(
            .reviewNow, with: [.review(bothWays[0], .backFirst), .review(bothWays[0])], settings: settings)

        panel.flip()
        panel.rate(.again)
        let backFirstOffer = panel.content
        let backFirstNote = panel.note
        panel.cancelFlagging()
        panel.flip()
        panel.rate(.again)

        #expect(backFirstOffer == .flagging(bothWays[0], .backFirst, showsLowerSide: true))
        #expect(backFirstNote == "Forgotten 8 times back first")
        #expect(panel.content == .flagging(bothWays[0], showsLowerSide: true))
        #expect(panel.note == "Forgotten 8 times")
    }

    @Test("Esc on the offer to flag a card leaves it in the reviews, its “Don't know” recorded, and moves on")
    func cancellingTheOfferMovesOnWithoutFlagging() throws {
        let cards = try dueCards(forgottenSevenTimes: "ubuntu", then: "petricor")
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        panel.flip()
        panel.rate(.again)

        panel.cancelFlagging()

        #expect(panel.content == .upperSide(cards[1]))
        #expect(!panel.offersToFlag)
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(
            try engine.standing(of: cards[0].id, with: settings.scheduler).stageAndDue
                == relearning(step: 0, due: time.now + hours(1)))
        #expect(try engine.reviewNow(settings) == [.review(cards[1])])
    }

    @Test(
        "one ⌘Z after the offer undoes the flag and the “Don't know”, and shows the card's back again, its time going on from the answer; rating it again offers again"
    )
    func undoAfterTheOfferUndoesTheFlagAndTheRating() throws {
        let cards = try dueCards(forgottenSevenTimes: "ubuntu", then: "petricor")
        let standing = try engine.standing(of: cards[0].id, with: settings.scheduler)
        let log = try engine.reviewLog()
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings, clock: clock)
        clock.advance(by: .seconds(4))
        panel.flip()
        panel.rate(.again)
        clock.advance(by: .seconds(20))
        panel.finishFlagging()

        panel.undoLastCard()
        #expect(panel.content == .bothSides(cards[0]))
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.standing(of: cards[0].id, with: settings.scheduler) == standing)
        #expect(try engine.reviewLog() == log)
        #expect(!panel.canUndo)
        clock.advance(by: .seconds(1))
        panel.rate(.again)

        #expect(panel.content == .flagging(cards[0], showsLowerSide: true))
        #expect(panel.note == "Forgotten 8 times")
        #expect(try engine.reviewLog().last?.responseTime == .seconds(5))
        #expect(panel.failure == nil)
    }

    // Lucas answered the card, so the panel went through it.
    @Test("closing the panel while it offers to flag its last card finishes it, and leaves the card in the reviews")
    func closingDuringTheOfferFinishesThePanel() throws {
        let cards = try dueCards(forgottenSevenTimes: "ubuntu")
        var panel = try engine.openPanel(.appearance, with: [.review(cards[0])], settings: settings)
        panel.flip()
        panel.rate(.again)

        panel.close(.byLucas)

        #expect(panel.outcome == .finished)
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.reviewLog().last?.kind == .review(.again))
    }

    @Test("a “Don't know” under the number, or with the offer turned off, moves on without offering to flag the card")
    func noOfferBelowTheNumberOrWhenTurnedOff() throws {
        var turnedOff = settings
        turnedOff.forgottenOftenAfter = nil
        let cards = try dueCards(forgottenSevenTimes: "ubuntu", then: "petricor")
        var belowTheNumber = try engine.openPanel(.reviewNow, with: [.review(cards[1])], settings: settings)
        var offerOff = try engine.openPanel(.reviewNow, with: [.review(cards[0])], settings: turnedOff)

        belowTheNumber.flip()
        belowTheNumber.rate(.again)
        offerOff.flip()
        offerOff.rate(.again)

        #expect(belowTheNumber.content == .done)
        #expect(offerOff.content == .done)
        #expect(try engine.inbox().flaggedCards.isEmpty)
    }

    // Lucas, 2026-10-15: nothing was reviewed, so there's nothing to wait
    // after.
    @Test("an empty review now isn't logged, so it doesn't hold the next appearance back")
    func anEmptyReviewNowIsNotLogged() throws {
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)
        time.advance(by: minutes(1))

        panel.close(.byLucas)

        #expect(panel.outcome == .finished)
        #expect(try engine.appearanceLog().isEmpty)
        let serendipia = try approveCard("serendipia", in: engine)
        #expect(try engine.checkAppearance(settings, mac: FakeMac()) == .show([.new(serendipia)]))
    }

    @Test(
        "a side's ▶ plays its sound, with its length, showing ■, pressing it again stops it, and once more plays it from the start"
    )
    func aSidesPlayButtonPlaysItsSound() async throws {
        let la = try await addTone(440, to: engine)
        let coloratura = try dueCard("coloratura", frontSound: la)
        var panel = try engine.openPanel(.reviewNow, with: [.review(coloratura)], settings: settings)

        panel.playOrStopSound(on: .front)
        let playing = panel.playingSound
        let showsStop = panel.isPlaying(on: .front)
        panel.playOrStopSound(on: .front)
        let stopped = panel.playingSound
        let showsPlay = !panel.isPlaying(on: .front)
        panel.playOrStopSound(on: .front)

        #expect(playing?.side == .front)
        #expect(playing?.name == la)
        #expect(showsStop)
        #expect(stopped == nil)
        #expect(showsPlay)
        #expect(panel.playingSound == playing)
        let length = try #require(try panel.sounds[la]?.get().length)
        #expect(length > .milliseconds(950) && length < .milliseconds(1_050))
    }

    @Test("R plays the front's sound once the back shows when the back's sound couldn't be read")
    func rPlaysTheFrontsSoundWhenTheBacksCouldntBeRead() async throws {
        let la = try await addTone(440, to: engine)
        let missing = try #require(SoundName(rawValue: String(repeating: "0", count: 64) + ".m4a"))
        let coloratura = try dueCard("coloratura", frontSound: la, backSound: missing)
        var panel = try engine.openPanel(.reviewNow, with: [.review(coloratura)], settings: settings)
        panel.flip()

        panel.playOrStopSound()

        #expect(panel.sounds[missing].map { (try? $0.get()) == nil } == true)
        #expect(panel.playingSound?.side == .front)
    }

    /// What Lucas writes about the card he's on in the review panel.
    enum Writing: CaseIterable, Sendable {
        case note, question
    }

    // Esc would throw away what he writes, and R goes into it, so the sound
    // has no key to stop it while he writes.
    @Test(
        "writing a note or a question about the card stops its sound, which plays again once the card shows again",
        arguments: Writing.allCases)
    func writingAboutTheCardStopsItsSound(_ writing: Writing) async throws {
        let la = try await addTone(440, to: engine)
        let coloratura = try dueCard("coloratura", frontSound: la)
        var panel = try engine.openPanel(.reviewNow, with: [.review(coloratura)], settings: settings)
        panel.playOrStopSound()

        switch writing {
        case .note: panel.startFlagging()
        case .question: panel.startAsking()
        }
        let whileWriting = panel.playingSound
        panel.playOrStopSound(on: .front)
        let afterItsPlay = panel.playingSound
        let canPlay = panel.canPlaySounds
        switch writing {
        case .note: panel.cancelFlagging()
        case .question: panel.cancelAsking()
        }
        panel.playOrStopSound()

        #expect(whileWriting == nil)
        #expect(afterItsPlay == nil)
        #expect(!canPlay)
        #expect(panel.canPlaySounds)
        #expect(panel.playingSound?.name == la)
    }

    // The card stays, so its sound goes on.
    @Test("⌘Z that takes back a question about the card leaves its sound playing")
    func undoingAQuestionLeavesTheSoundPlaying() async throws {
        let la = try await addTone(440, to: engine)
        let coloratura = try dueCard("coloratura", frontSound: la)
        var panel = try engine.openPanel(.reviewNow, with: [.review(coloratura)], settings: settings)
        panel.startAsking()
        panel.write(question: "¿Quién la canta mejor?")
        panel.finishAsking()
        panel.playOrStopSound()

        panel.undoLastCard()

        #expect(try engine.inbox().followUps.isEmpty)
        #expect(panel.playingSound?.name == la)
    }

    @Test(
        "a new card shows its front alone, marked new, then its back under it once flipped, to rate with any of the four ratings",
        arguments: Rating.allCases)
    func aNewCardShowsItsFrontFirst(rating: Rating) throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        let beforeTheFlip = panel.content
        panel.rate(rating)
        let logBeforeTheFlip = try engine.reviewLog()
        panel.flip()
        let afterTheFlip = panel.content
        panel.rate(rating)

        #expect(beforeTheFlip == .upperSide(serendipia, isNew: true))
        #expect(logBeforeTheFlip.isEmpty)
        #expect(afterTheFlip == .bothSides(serendipia, isNew: true))
        #expect(panel.current == nil)
        #expect(try engine.reviewLog().map(\.kind) == [.review(rating)])
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) != .new)
    }

    @Test(
        "a new back-first way shows the back alone, marked new, then the front under it once flipped, and its rating moves only that way"
    )
    func aNewBackFirstWayFlipsBeforeItsRating() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        let frontFirst = try engine.standing(of: serendipia.id, with: settings.scheduler)
        var panel = try engine.openPanel(.reviewNow, with: engine.reviewNow(settings), settings: settings)

        let beforeTheFlip = panel.content
        panel.flip()
        let afterTheFlip = panel.content
        panel.rate(.again)

        #expect(beforeTheFlip == .upperSide(bothWays[0], .backFirst, isNew: true))
        #expect(afterTheFlip == .bothSides(bothWays[0], .backFirst, isNew: true))
        #expect(panel.current == nil)
        #expect(
            try engine.standing(of: serendipia.id, way: .backFirst, with: settings.scheduler).stageAndDue
                == learning(step: 0, due: time.now + hours(1)))
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == frontFirst)
    }

    @Test(
        "a back-first review shows the back alone, then the front under it to rate, and the rating moves only that way")
    func aBackFirstReviewShowsTheBackOnTop() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        try engine.meet(serendipia, way: .backFirst)
        time.advance(by: hours(1))
        var panel = try engine.openPanel(.reviewNow, with: [.review(bothWays[0], .backFirst)], settings: settings)

        let beforeTheFlip = panel.content
        panel.flip()
        let afterTheFlip = panel.content
        panel.rate(.good)

        #expect(beforeTheFlip == .upperSide(bothWays[0], .backFirst))
        #expect(afterTheFlip == .bothSides(bothWays[0], .backFirst))
        #expect(
            try engine.standing(of: serendipia.id, way: .backFirst, with: settings.scheduler).stageAndDue
                == learning(step: 1, due: time.now + hours(4)))
        #expect(
            try engine.standing(of: serendipia.id, with: settings.scheduler).stageAndDue
                == learning(step: 0, due: time.now))
    }

    @Test(
        "back first, R plays the back's sound before the flip, and once flipped the front's, or the back's without one")
    func rPlaysTheSoundOfTheSideThatShowsBackFirst() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let coloratura = try wordCard("coloratura", frontSound: la, backSound: mi)
        let aria = try wordCard("aria", backSound: mi)
        let bothWays = try engine.setBothWays(true, of: [coloratura.id, aria.id])
        var withBoth = try engine.openPanel(.reviewNow, with: [.review(bothWays[0], .backFirst)], settings: settings)
        var withBack = try engine.openPanel(.reviewNow, with: [.review(bothWays[1], .backFirst)], settings: settings)

        let rBeforeTheFlip = withBoth.sideForR
        withBoth.flip()
        withBack.flip()

        #expect(rBeforeTheFlip == .back)
        #expect(withBoth.sideForR == .front)
        #expect(withBack.sideForR == .back)
    }

    @Test("R plays the front's sound while only the front shows, and the back's once the back shows")
    func rPlaysTheSoundOfTheSideThatShows() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let coloratura = try dueCard("coloratura", frontSound: la, backSound: mi)
        var panel = try engine.openPanel(.reviewNow, with: [.review(coloratura)], settings: settings)

        let rOnTheFront = panel.sideForR
        panel.playOrStopSound()
        let playedOnTheFront = panel.playingSound
        panel.playOrStopSound()
        panel.flip()
        let rOnTheBack = panel.sideForR
        panel.playOrStopSound()

        #expect(rOnTheFront == .front)
        #expect(playedOnTheFront?.side == .front)
        #expect(playedOnTheFront?.name == la)
        #expect(rOnTheBack == .back)
        #expect(panel.playingSound?.side == .back)
        #expect(panel.playingSound?.name == mi)
    }

    @Test(
        "a new card, which shows its front alone, R plays the front's sound, and once flipped the back's, or the front's when the back has none"
    )
    func rPlaysTheFrontsSoundOnANewCard() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let coloratura = try wordCard("coloratura", frontSound: la, backSound: mi)
        let aria = try wordCard("aria", frontSound: la)
        var withBoth = try engine.openPanel(.reviewNow, with: [.new(coloratura)], settings: settings)
        var withFront = try engine.openPanel(.reviewNow, with: [.new(aria)], settings: settings)

        let rBeforeTheFlip = withBoth.sideForR
        withBoth.flip()
        withFront.flip()
        withBoth.playOrStopSound()
        withFront.playOrStopSound()

        #expect(rBeforeTheFlip == .front)
        #expect(withBoth.playingSound?.side == .back)
        #expect(withFront.playingSound?.side == .front)
    }

    @Test("once the back shows, R plays the front's sound when the back has none, and nothing on a card without sounds")
    func rPlaysTheFrontsSoundWhenTheBackHasNone() async throws {
        let la = try await addTone(440, to: engine)
        let aria = try dueCard("aria", frontSound: la)
        let tenor = try dueCard("tenor")
        var panel = try engine.openPanel(.reviewNow, with: [.review(aria), .review(tenor)], settings: settings)

        panel.flip()
        panel.playOrStopSound()
        let played = panel.playingSound
        panel.rate(.good)
        panel.playOrStopSound()

        #expect(played?.side == .front)
        #expect(panel.sideForR == nil)
        #expect(panel.playingSound == nil)
    }

    // So Lucas keeps hearing the front's sound while he reads the back.
    @Test(
        "one sound plays at a time, flipping doesn't stop it, R stops the one that plays, and pressing it again plays it from the start"
    )
    func oneSoundPlaysAtATime() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let coloratura = try dueCard("coloratura", frontSound: la, backSound: mi)
        var panel = try engine.openPanel(.reviewNow, with: [.review(coloratura)], settings: settings)

        panel.playOrStopSound(on: .front)
        panel.flip()
        let afterTheFlip = panel.playingSound
        let rAfterTheFlip = panel.sideForR
        panel.playOrStopSound(on: .back)
        let frontAfterTheBack = panel.isPlaying(on: .front)
        let backAfterTheBack = panel.isPlaying(on: .back)
        panel.playOrStopSound()
        let afterR = panel.playingSound
        panel.playOrStopSound()

        #expect(afterTheFlip?.side == .front)
        #expect(rAfterTheFlip == .front)
        #expect(!frontAfterTheBack)
        #expect(backAfterTheBack)
        #expect(afterR == nil)
        #expect(panel.playingSound?.side == .back)
    }

    /// How the card Lucas is on leaves the review panel, or how the panel
    /// closes.
    enum Leaving: CaseIterable, Sendable {
        case answer, flag, bury, undo, closeWithEsc, closeOnItsOwn
    }

    @Test(
        "a sound stops as its card leaves, with an answer, a flag, a burial or an undo, or as the panel closes, with Esc or on its own",
        arguments: Leaving.allCases)
    func aSoundStopsAsItsCardLeaves(_ leaving: Leaving) async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let aria = try dueCard("aria", frontSound: la)
        let coloratura = try dueCard("coloratura", frontSound: mi)
        var panel = try engine.openPanel(.reviewNow, with: [.review(aria), .review(coloratura)], settings: settings)
        panel.flip()
        panel.rate(.good)

        panel.playOrStopSound(on: .front)
        let played = panel.playingSound
        switch leaving {
        case .answer:
            panel.flip()
            panel.rate(.good)
        case .flag:
            panel.startFlagging()
            panel.write(note: "Falta el compositor.")
            panel.finishFlagging()
        case .bury:
            panel.buryCard()
        case .undo:
            panel.undoLastCard()
        case .closeWithEsc:
            panel.close(.byLucas)
        case .closeOnItsOwn:
            time.advance(by: minutes(10))
            panel.closeIfUntouched()
        }
        let afterLeaving = panel.playingSound
        panel.playOrStopSound()

        #expect(played?.name == mi)
        #expect(afterLeaving == nil)
        #expect(panel.failure == nil)
        // R then plays the card ⌘Z brought back, and nothing once every card
        // was gone through or the panel closed.
        #expect(panel.playingSound?.name == (leaving == .undo ? la : nil))
    }

    @Test("a “Don't know” stops the sound also when the panel stays on the card, to offer to flag it")
    func dontKnowStopsTheSoundAsThePanelOffersToFlag() async throws {
        let la = try await addTone(440, to: engine)
        let aria = try wordCard("aria", frontSound: la)
        try engine.lapse(aria, times: 7, movingForward: time)
        time.move(to: try #require(try engine.standing(of: aria.id, with: settings.scheduler).due))
        var panel = try engine.openPanel(.reviewNow, with: [.review(aria)], settings: settings)

        panel.playOrStopSound(on: .front)
        let played = panel.playingSound
        panel.flip()
        panel.rate(.again)

        #expect(played?.name == la)
        #expect(panel.offersToFlag)
        #expect(panel.playingSound == nil)
    }

    @Test("a sound that ends on its own turns its ■ back into ▶, unless another sound started meanwhile")
    func aSoundThatEndsTurnsItsStopBackIntoPlay() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let coloratura = try dueCard("coloratura", frontSound: la, backSound: mi)
        var panel = try engine.openPanel(.reviewNow, with: [.review(coloratura)], settings: settings)
        panel.flip()

        panel.playOrStopSound(on: .front)
        let front = try #require(panel.playingSound)
        panel.playOrStopSound(on: .back)
        let back = try #require(panel.playingSound)
        panel.soundEnded(front)
        let afterTheFrontEnded = panel.playingSound
        panel.soundEnded(back)

        #expect(afterTheFrontEnded == back)
        #expect(panel.playingSound == nil)
        #expect(!panel.isPlaying(on: .back))
    }

    /// Creates a word card with `front` and the sounds `frontSound` and
    /// `backSound` on its sides: a new card.
    private func wordCard(_ front: String, frontSound: SoundName? = nil, backSound: SoundName? = nil) throws -> Card {
        try engine.create(
            card(.word, front: front, back: "Una palabra de la ópera.", frontSound: frontSound, backSound: backSound))
    }

    /// Creates a word card with `front` and the sounds `frontSound` and
    /// `backSound` on its sides, and meets it, so that it's due an hour
    /// later, when this moves the time.
    private func dueCard(_ front: String, frontSound: SoundName? = nil, backSound: SoundName? = nil) throws -> Card {
        let created = try wordCard(front, frontSound: frontSound, backSound: backSound)
        try engine.meet(created)
        time.advance(by: hours(1))
        return created
    }

    /// Approves a word card with the front `forgotten`, graduates it and
    /// makes it lapse seven times, one under the default number of a card
    /// forgotten often, and approves a card for each of `others`, graduated
    /// with three goods, so a longer interval, and moves the time until they
    /// are all due. Review now brings them in that order: the shortest
    /// interval first.
    private func dueCards(forgottenSevenTimes forgotten: String, then others: String...) throws -> [Card] {
        let forgottenCard = try approveCard(forgotten, in: engine)
        let otherCards = try others.map { try approveCard($0, in: engine) }
        try engine.lapse(forgottenCard, times: 7, movingForward: time)
        for card in otherCards {
            try engine.climb(card, goods: 3, movingForward: time)
        }
        let cards = [forgottenCard] + otherCards
        let dues = try cards.map { card in
            try #require(try engine.standing(of: card.id, with: settings.scheduler).due)
        }
        time.move(to: try #require(dues.max()))
        return cards
    }
}
