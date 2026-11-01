import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on what the widget shows (#171): the card a review now would start
/// with, or when the next one comes, as the engine decides it, and the review
/// now a click on it opens.
struct WidgetTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("the widget shows the front of the card a review now would start with")
    func showsTheFrontOfTheDueCard() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        time.advance(by: hours(1))

        #expect(
            try engine.widgetTimeline(.defaults, engineAheadBy: .zero).entries == [
                WidgetTimeline.Entry(
                    date: time.now,
                    content: .card(
                        WidgetCard(
                            way: CardWay(cardID: serendipia.id, way: .frontFirst), isNew: false, side: .front,
                            text: "serendipia", image: nil, showsSpeaker: false)))
            ])
    }

    @Test("a card review now would start with back first shows its back, with that side's image")
    func aBackFirstCardShowsItsBackWithItsImage() throws {
        let flag = try engine.addImage(picture(width: 300, height: 200, red: 0.3))
        let argentina = try approve(card(.word, front: "Argentina", back: "Su bandera", backImage: flag), in: engine)
        let bothWays = try #require(try engine.setBothWays(true, of: [argentina.id]).first)
        try engine.meet(bothWays)
        try engine.meet(bothWays, way: .backFirst)
        time.advance(by: hours(1))
        // The front-first way climbs, so the back-first way, on the first
        // step, comes first.
        try engine.review(bothWays, .good)

        #expect(
            try engine.widgetTimeline(.defaults, engineAheadBy: .zero).entries.first?.content
                == .card(
                    WidgetCard(
                        way: CardWay(cardID: argentina.id, way: .backFirst), isNew: false, side: .back,
                        text: "Su bandera", image: flag, showsSpeaker: false)))
    }

    @Test("the widget picks by this Mac's cards per appearance, which the app hands over, as review now does")
    func picksByThisMacsCardsPerAppearance() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        time.advance(by: hours(1))
        let ubuntu = try approveInDeck("ubuntu", deck: "Urgente", in: engine)
        try engine.togglePriority(ofDeck: "Urgente")
        // With a single card, a priority card's new way comes before
        // another card's due way, and takes the only place.
        var settings = ReviewSettings.defaults
        settings.cardsPerAppearance = 1
        let ubuntuFrontFirst = CardWay(cardID: ubuntu.id, way: .frontFirst)

        let shown = try engine.widgetTimeline(WidgetSettings(settings), engineAheadBy: .zero).entries.first?.content

        #expect(try engine.reviewNow(settings) == [.new(ubuntu)])
        #expect(
            shown
                == .card(
                    WidgetCard(
                        way: ubuntuFrontFirst, isNew: true, side: .front, text: "ubuntu", image: nil,
                        showsSpeaker: false)))
    }

    @Test("a side with only an image shows the image, and no speaker even when the side has a sound too")
    func aSideWithOnlyAnImageShowsTheImage() async throws {
        let flag = try engine.addImage(picture(width: 300, height: 200, red: 0.3))
        let anthem = try await engine.addSound(tone(seconds: 1, hertz: 440), named: "himno.wav")
        let capture = try engine.newCapture("La bandera argentina")
        let argentina = try #require(
            try engine.approve(
                capture.id, into: [card(.word, front: "", back: "Argentina", frontImage: flag, frontSound: anthem)]
            ).first)

        #expect(
            try engine.widgetTimeline(.defaults, engineAheadBy: .zero).entries.first?.content
                == .card(
                    WidgetCard(
                        way: CardWay(cardID: argentina.id, way: .frontFirst), isNew: true, side: .front, text: "",
                        image: flag, showsSpeaker: false)))
    }

    @Test("a side with only a sound shows a speaker, and a new card is marked as new")
    func aSideWithOnlyASoundShowsASpeaker() async throws {
        let la = try await engine.addSound(tone(seconds: 1, hertz: 440), named: "la.wav")
        let capture = try engine.newCapture("La, a 440 Hz")
        let note = try #require(
            try engine.approve(capture.id, into: [card(.word, front: "", back: "La, a 440 Hz", frontSound: la)]).first)

        #expect(
            try engine.widgetTimeline(.defaults, engineAheadBy: .zero).entries.first?.content
                == .card(
                    WidgetCard(
                        way: CardWay(cardID: note.id, way: .frontFirst), isNew: true, side: .front, text: "",
                        image: nil, showsSpeaker: true)))
    }

    @Test("with no card waiting, the widget says when the next one comes, and shows it then")
    func showsWhenTheNextCardComes() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        let due = time.now + hours(1)

        let timeline = try engine.widgetTimeline(.defaults, engineAheadBy: .zero)

        #expect(
            timeline.entries == [
                WidgetTimeline.Entry(date: time.now, content: .nextCard(at: due)),
                WidgetTimeline.Entry(date: due, content: .card(widgetCardOfMetCard(serendipia))),
            ])
        #expect(timeline.refreshAt == nil)
    }

    @Test("a new card waits for the next day once Lucas met the day's new cards, and the widget says so")
    func aNewCardWaitsForTheNextDay() throws {
        var settings = ReviewSettings.defaults.progress
        settings.newCardsPerDay = 1
        try engine.saveProgressSettings(settings, changedFrom: ReviewSettings.defaults.progress)
        let met = try approveCard("serendipia", in: engine)
        let new = try approveCard("ubuntu", in: engine)
        // Met this morning, and due again in 2 days.
        try engine.climb(met, goods: 2, movingForward: time)
        let midnight = try #require(calendar.dateInterval(of: .day, for: time.now)?.end)

        #expect(
            try engine.widgetTimeline(.defaults, engineAheadBy: .zero).entries.prefix(2) == [
                WidgetTimeline.Entry(date: time.now, content: .nextCard(at: midnight)),
                WidgetTimeline.Entry(
                    date: midnight,
                    content: .card(
                        WidgetCard(
                            way: CardWay(cardID: new.id, way: .frontFirst), isNew: true, side: .front,
                            text: "ubuntu", image: nil, showsSpeaker: false))),
            ])
    }

    @Test("what comes due less than 5 minutes after an entry shows 5 minutes after it in WidgetKit, as it asks")
    func entriesAreFiveMinutesApart() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.climb(ubuntu, goods: 1, movingForward: time)
        // Due a minute after ubuntu, on a lower step, so it comes first then.
        let ubuntuDue = try dueTime(of: ubuntu)
        time.move(to: ubuntuDue - hours(1) + minutes(1))
        try engine.meet(serendipia)

        let timeline = try engine.widgetTimeline(.defaults, engineAheadBy: .zero)

        #expect(timeline.entries.map(\.date) == [time.now, ubuntuDue, ubuntuDue + minutes(1)])
        #expect(timeline.spacedEntries.map(\.date) == [time.now, ubuntuDue, ubuntuDue + minutes(5)])
    }

    @Test("with no cards at all, the widget says so")
    func noCardsAtAll() throws {
        let timeline = try engine.widgetTimeline(.defaults, engineAheadBy: .zero)

        #expect(timeline.entries == [WidgetTimeline.Entry(date: time.now, content: .noCards)])
        #expect(timeline.refreshAt == nil)
    }

    @Test("with cards none of which comes as time passes, the widget says none is coming")
    func noneComing() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.bury([serendipia.id])

        let timeline = try engine.widgetTimeline(.defaults, engineAheadBy: .zero)

        #expect(timeline.entries == [WidgetTimeline.Entry(date: time.now, content: .noneComing)])
        #expect(timeline.refreshAt == nil)
    }

    @Test("a click on the widget starts review now with its card, and the others review now brings follow")
    func aClickStartsReviewNowWithItsCard() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(serendipia)
        time.advance(by: hours(1))

        #expect(
            try engine.reviewNow(.defaults, startingWith: CardWay(cardID: ubuntu.id, way: .frontFirst))
                == [.new(ubuntu), .review(serendipia)])
    }

    @Test("a click on a card review now no longer brings, as one reviewed meanwhile, starts review now as usual")
    func aClickOnACardNoLongerWaitingStartsReviewNowAsUsual() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        try engine.review(serendipia, .good)

        #expect(
            try engine.reviewNow(.defaults, startingWith: CardWay(cardID: serendipia.id, way: .frontFirst))
                == [.review(ubuntu)])
    }

    @Test("a click on the widget's card starts review now in the open panel's place at its end, and not before")
    func aClickReplacesTheOpenPanelAtItsEnd() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        // Review now brings one new card, and then "See more?", which brings
        // no new card.
        var panel = try engine.openPanel(.reviewNow, with: try engine.reviewNow(.defaults), settings: .defaults)
        let widgetsCard = CardWay(cardID: ubuntu.id, way: .frontFirst)

        let onItsCard = panel.givesWay(toAReviewNowStartingWith: widgetsCard)
        panel.flip()
        panel.rate(.good)
        let atItsEnd = panel.givesWay(toAReviewNowStartingWith: widgetsCard)
        let atItsEndWithNoCard = panel.givesWay(toAReviewNowStartingWith: nil)

        #expect(panel.cards == [.new(serendipia)])
        #expect(!onItsCard)
        #expect(atItsEnd)
        #expect(!atItsEndWithNoCard)
    }

    @Test("the link a click on the widget opens names its card, and the app takes no other link for it")
    func theWidgetsLinkNamesItsCard() throws {
        let toACard = WidgetLink(startingWith: CardWay(cardID: 12, way: .backFirst))
        let toReviewNow = WidgetLink(startingWith: nil)
        let url = try #require(toACard.url(scheme: "ficha-dev"))

        #expect(WidgetLink(url, scheme: "ficha-dev") == toACard)
        #expect(WidgetLink(try #require(toReviewNow.url(scheme: "ficha-dev")), scheme: "ficha-dev") == toReviewNow)
        // The real Ficha's, and links the widget never makes.
        #expect(WidgetLink(url, scheme: "ficha") == nil)
        #expect(WidgetLink(try #require(URL(string: "ficha-dev://review-now?card=x")), scheme: "ficha-dev") == nil)
        #expect(WidgetLink(try #require(URL(string: "ficha-dev://capture")), scheme: "ficha-dev") == nil)
    }

    @Test("the app reloads the widget the first time, and then only when what it shows from then on changes")
    func theAppReloadsTheWidgetOnlyWhenWhatItShowsChanges() throws {
        var reloading = WidgetReloading()
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)

        let atLaunch = reloading.reloadsAsTheAppDoes(for: try engine.widgetTimeline(.defaults, engineAheadBy: .zero))
        time.advance(by: minutes(1))
        try engine.newCapture("ubuntu")
        let afterACapture = reloading.reloadsAsTheAppDoes(
            for: try engine.widgetTimeline(.defaults, engineAheadBy: .zero))
        // The widget's timeline shows serendipia once it's due.
        time.advance(by: hours(1))
        let onceDue = reloading.reloadsAsTheAppDoes(for: try engine.widgetTimeline(.defaults, engineAheadBy: .zero))
        try engine.review(serendipia, .good)
        let afterAReview = reloading.reloadsAsTheAppDoes(
            for: try engine.widgetTimeline(.defaults, engineAheadBy: .zero))

        #expect(atLaunch)
        #expect(!afterACapture)
        #expect(!onceDue)
        #expect(afterAReview)
    }

    @Test(
        "with more due times than the timeline looks at, a write that changes nothing the widget shows reloads nothing")
    func aTimelineCutShortReloadsOnlyWhenWhatItShowsChanges() throws {
        var reloading = WidgetReloading()
        // 250 cards met a second apart, each due an hour later.
        let cards = try engine.approve(
            engine.newCapture("muchas").id,
            into: (1...250).map { try card(.word, front: "palabra \($0)", back: "Lo que quiere decir.") })
        for card in cards {
            try engine.meet(card)
            time.advance(by: 1)
        }
        let atLaunch = reloading.reloadsAsTheAppDoes(for: try engine.widgetTimeline(.defaults, engineAheadBy: .zero))
        // The first ten came due, so the timeline looks ten due times further.
        time.move(to: try dueTime(of: cards[9]))
        try engine.newCapture("ubuntu")
        let afterACapture = reloading.reloadsAsTheAppDoes(
            for: try engine.widgetTimeline(.defaults, engineAheadBy: .zero))
        try engine.review(cards[0], .good)
        let afterAReview = reloading.reloadsAsTheAppDoes(
            for: try engine.widgetTimeline(.defaults, engineAheadBy: .zero))

        #expect(atLaunch)
        #expect(!afterACapture)
        #expect(afterAReview)
    }

    @Test(
        "the app gathers a burst of changes to the database into one look at the widget, once they stop for 30 seconds")
    func aBurstOfChangesMakesOneLook() {
        var reloading = WidgetReloading()
        let start = time.now

        let first = reloading.databaseChanged(at: start)
        let second = reloading.databaseChanged(at: start + 10)
        // The look the first change set: another came since.
        let looksForTheFirst = reloading.looks(at: start + 30)
        let looksForTheSecond = reloading.looks(at: start + 40)
        // Nothing changed since that look.
        let looksAgain = reloading.looks(at: start + 70)

        #expect(first == start + 30)
        #expect(second == start + 40)
        #expect(!looksForTheFirst)
        #expect(looksForTheSecond)
        #expect(!looksAgain)
    }

    @Test("the review panel holds the widget's reloads back while it's open, and the app looks once as it closes")
    func theReviewPanelHoldsReloadsBack() {
        var reloading = WidgetReloading()
        let start = time.now

        reloading.panelOpened()
        let whileOpen = [reloading.databaseChanged(at: start), reloading.databaseChanged(at: start + 10)]
        let looksWhileOpen = reloading.looks(at: start + 60)
        let looksAsItCloses = reloading.panelClosed()
        reloading.panelOpened()
        let looksAsItClosesUnchanged = reloading.panelClosed()

        #expect(whileOpen == [nil, nil])
        #expect(!looksWhileOpen)
        #expect(looksAsItCloses)
        #expect(!looksAsItClosesUnchanged)
    }

    /// When `card`'s front-first way is due, on the default ladder.
    private func dueTime(of card: Card) throws -> Date {
        try #require(try engine.standing(of: card.id, with: ReviewSettings.defaults.scheduler).due)
    }
}

/// Tests on Ficha Dev's widget, whose engine runs on the time its debug menu
/// moved forward, while WidgetKit's timeline runs on the system's.
final class FichaDevWidgetTests {
    let calendar: Calendar
    /// The system's time.
    let system: ManualTimeSource
    /// Ficha Dev's time, a day ahead of the system's.
    let fichaDevTime: DebugTimeSource
    let engine: Engine
    /// Ficha Dev's data folder, which keeps how far its time moved.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaDataTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        system = ManualTimeSource(now: try morning(of: 14, in: calendar))
        fichaDevTime = try DebugTimeSource(savedIn: folder, base: system)
        try fichaDevTime.moveForward(by: .seconds(24 * 60 * 60))
        engine = try Engine(location: .inMemory, time: fichaDevTime, calendar: calendar)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("Ficha Dev's widget shows a new card at the system's midnight before Ficha Dev's, and asks nothing more")
    func aNewCardShowsAtTheSystemsMidnight() throws {
        var settings = ReviewSettings.defaults.progress
        settings.newCardsPerDay = 1
        try engine.saveProgressSettings(settings, changedFrom: ReviewSettings.defaults.progress)
        let met = try approveCard("serendipia", in: engine)
        let new = try approveCard("ubuntu", in: engine)
        // The day's new card, met, and out of the way.
        try engine.meet(met)
        try engine.bury([met.id])
        // A day before Ficha Dev's midnight, which is a day ahead.
        let systemsMidnight = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 0)))

        let timeline = try engine.widgetTimeline(.defaults, engineAheadBy: fichaDevTime.shift)

        #expect(
            timeline.entries == [
                WidgetTimeline.Entry(date: system.now, content: .nextCard(at: systemsMidnight)),
                WidgetTimeline.Entry(
                    date: systemsMidnight,
                    content: .card(
                        WidgetCard(
                            way: CardWay(cardID: new.id, way: .frontFirst), isNew: true, side: .front,
                            text: "ubuntu", image: nil, showsSpeaker: false))),
            ])
        #expect(timeline.refreshAt == nil)
    }

    @Test("Ficha Dev's widget asks for its timeline again on the system's time")
    func refreshesOnTheSystemsTime() throws {
        // A due time for each of 250 cards, a minute apart, more than the
        // timeline looks at, so it stops at the 200th.
        let cards = try engine.approve(
            engine.newCapture("muchas").id,
            into: (1...250).map { try card(.word, front: "palabra \($0)", back: "Lo que quiere decir.") })
        for card in cards {
            try engine.meet(card)
            system.advance(by: 1)
        }

        let timeline = try engine.widgetTimeline(.defaults, engineAheadBy: fichaDevTime.shift)

        // Met a second apart, and due an hour after, by the system's time.
        #expect(timeline.refreshAt == system.now - 250 + hours(1) + 199)
    }
}

extension WidgetSettings {
    /// What the app hands over of Ficha's own settings, as Lucas never
    /// changed them.
    fileprivate static let defaults = WidgetSettings(ReviewSettings.defaults)
}

extension WidgetReloading {
    /// Whether the app reloads the widget for `timeline`, as it does once it
    /// looked: then the reload is the last one.
    fileprivate mutating func reloadsAsTheAppDoes(for timeline: WidgetTimeline) -> Bool {
        guard needsReload(for: timeline) else { return false }
        recordReload(of: timeline)
        return true
    }
}

/// The widget's card for `card`'s front-first way, once it had its first
/// view, with no image or sound.
private func widgetCardOfMetCard(_ card: Card) -> WidgetCard {
    WidgetCard(
        way: CardWay(cardID: card.id, way: .frontFirst), isNew: false, side: .front, text: card.front, image: nil,
        showsSpeaker: false)
}

/// Tests on the widget's engine, which reads the database in a data folder
/// beside the app and the CLI, which write it, and never writes it.
final class WidgetDatabaseTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    /// A data folder of the test's own, which the app's engine creates when it
    /// first opens it.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaDataTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("the widget reads the database beside the app and the CLI, and a card the CLI reviews leaves it")
    func aCardReviewedMeanwhileLeavesTheWidget() throws {
        let app = try Engine(location: .folder(folder), time: time)
        let serendipia = try approveCard("serendipia", in: app)
        let ubuntu = try approveCard("ubuntu", in: app)
        try app.meet(serendipia)
        try app.meet(ubuntu)
        time.advance(by: hours(1))
        let widget = try #require(try Engine(readingOnlyIn: folder, time: time))
        let before = try widget.widgetTimeline(.defaults, engineAheadBy: .zero).entries.first?.content

        let cli = try Engine(location: .folder(folder), time: time)
        try cli.review(serendipia, .good)

        #expect(before == .card(widgetCardOfMetCard(serendipia)))
        #expect(
            try widget.widgetTimeline(.defaults, engineAheadBy: .zero).entries.first?.content
                == .card(widgetCardOfMetCard(ubuntu))
        )
    }

    // SQLite's side files, which a process that reads alone needs, stay once
    // the processes that write close the database (persistent WAL), so the
    // widget never makes them: here it couldn't.
    @Test("the widget reads the cards once the app and the CLI closed the database, without writing a file")
    func readsOnceTheWritersClosedTheDatabase() throws {
        let serendipia = try approveCard("serendipia", in: try Engine(location: .folder(folder), time: time))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
        }

        let widget = try #require(try Engine(readingOnlyIn: folder, time: time))

        #expect(
            try widget.widgetTimeline(.defaults, engineAheadBy: .zero).entries.first?.content
                == .card(
                    WidgetCard(
                        way: CardWay(cardID: serendipia.id, way: .frontFirst), isNew: true, side: .front,
                        text: "serendipia", image: nil, showsSpeaker: false)))
    }

    @Test("the widget never creates the database: before the app opens it, there's nothing to read")
    func neverCreatesTheDatabase() throws {
        #expect(try Engine(readingOnlyIn: folder, time: time) == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }
}
