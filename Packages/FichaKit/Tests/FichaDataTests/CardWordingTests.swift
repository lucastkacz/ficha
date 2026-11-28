import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on how a card's detail in the Cards window says where the card is
/// in words (#537): that a new card is new, how many times the user has seen
/// a card, and when it's back, by Ficha's days (ADR 0045), as the desktop
/// mock's card pane says it, on the default scheduler. They start at 9 in the
/// morning of Wednesday the 14th of October 2026 in Buenos Aires.
struct CardWordingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // At 9, ojalá is met, due an hour later. petricor climbs its two learning
    // steps, an hour and 4 hours, and graduates at 2 in the afternoon, after
    // three reviews, to wait a day or more. Then ubuntu is met, due at 3.
    // serendipia is new. Their detail reads at 2.
    @Test(
        "a card's detail says a new card is new, and of a card seen N times that it's seen N times and back now, at a time later today, or on a later day",
        .bug(id: 537))
    func aCardsDetailSaysInWordsWhenItsBack() throws {
        let serendipia = try engine.create(card(nil, front: "serendipia", back: "Un hallazgo por accidente."))
        let ojala = try engine.create(card(nil, front: "ojalá", back: "Ojalá que llueva café."))
        let petricor = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        let ubuntu = try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."))
        try engine.meet(ojala)
        try engine.climb(petricor, goods: 2, movingForward: time)
        try engine.meet(ubuntu)
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        var rows: [Int64: CardRow] = [:]
        var said: [Int64: CardRow.Wording] = [:]
        for shown in [serendipia, ojala, petricor, ubuntu] {
            window.select([shown.id])
            let row = try #require(window.shownCardRow)
            rows[shown.id] = row
            said[shown.id] = window.wording(of: row)
        }
        let petricorIsBack = try #require(rows[petricor.id]?.frontFirst.due)
        let petricorsDay = calendar.startOfDay(for: petricorIsBack)

        #expect(said[serendipia.id] == .new)
        #expect(said[ojala.id] == .seen(times: 1, back: .now))
        #expect(said[ubuntu.id] == .seen(times: 1, back: .today(at: time.now + hours(1))))
        #expect(!calendar.isDate(petricorIsBack, inSameDayAs: time.now))
        #expect(said[petricor.id] == .seen(times: 3, back: .on(petricorsDay, inThisYear: true)))
    }

    // Out of the reviews, a card isn't back until it's back in them, and the
    // detail says why above the card: flagged, set aside on its own, or in a
    // set-aside deck. A new card there waits no turn in the queue either:
    // ojalá, petricor and eudaimonía were met, and serendipia, ubuntu and
    // ataraxia are new.
    @Test(
        "a card out of the user's reviews, flagged, set aside on its own or in a set-aside deck, says so in place of when it's back, and a new one doesn't say it waits its turn",
        .bug(id: 537))
    func aCardOutOfTheReviewsSaysSo() throws {
        let ojala = try engine.create(card(nil, front: "ojalá", back: "Ojalá que llueva café."))
        let petricor = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        let serendipia = try engine.create(card(nil, front: "serendipia", back: "Un hallazgo por accidente."))
        let ubuntu = try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."))
        let eudaimonia = try engine.create(card(nil, front: "eudaimonía", back: "La vida buena."), deck: "Filosofía")
        let ataraxia = try engine.create(card(nil, front: "ataraxia", back: "La calma del alma."), deck: "Filosofía")
        for met in [ojala, petricor, eudaimonia] {
            try engine.meet(met)
        }
        try engine.flag(ojala.id, note: note("Falta de quién es la canción"))
        try engine.flag(serendipia.id, note: note("Falta de dónde viene"))
        try engine.bury([petricor.id, ubuntu.id])
        try engine.setAside(deck: "Filosofía")
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        window.choose(.cards(.deck(Deck.defaultName)))
        let inDefault = try [ojala, petricor, serendipia, ubuntu].map { try wording(of: $0, in: &window) }
        window.choose(.cards(.deck("Filosofía")))
        let inFilosofia = try [eudaimonia, ataraxia].map { try wording(of: $0, in: &window) }

        let seenOnce = CardRow.Wording.seen(times: 1, back: .outOfReviews)
        let neverSeen = CardRow.Wording.seen(times: 0, back: .outOfReviews)
        #expect(inDefault == [seenOnce, seenOnce, neverSeen, neverSeen])
        #expect(inFilosofia == [seenOnce, neverSeen])
    }

    // Ficha's day starts at 4:00, so a night that crosses midnight is one
    // day. jacarandá is met at 21:00 and climbs to its second step at 22:00,
    // due 4 hours later, at 2:00; ombú is met at 23:00 and climbs at
    // midnight, due at 4:00 on Thursday the 15th, which starts the next
    // Ficha's day. With the day starting at 6:00, 4:00 is still today.
    @Test(
        "a card's detail counts Ficha's days: due at 2:00, read at 23:00 the day before, a card is back today, and due at 4:00, read at midnight, back on the next day, or today once the day starts at 6:00",
        .bug(id: 537), .bug(id: 562))
    func aCardsDetailCountsFichasDays() throws {
        let jacaranda = try engine.create(card(nil, front: "jacarandá", back: "Un árbol de flores violetas."))
        let ombu = try engine.create(card(nil, front: "ombú", back: "Un árbol de la pampa."))
        let twoAM = try at(2, day: 15)
        let fourAM = try at(4, day: 15)
        let thursday = try at(0, day: 15)
        time.move(to: try at(21, day: 14))
        try engine.climb(jacaranda, goods: 1, movingForward: time)
        time.move(to: try at(23, day: 14))
        try engine.meet(ombu)
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        let jacarandaAtEleven = try wording(of: jacaranda, in: &window)
        try engine.reviewWhenDue(ombu, .good, movingForward: time)
        window.read(with: scheduler)
        let jacarandaAtMidnight = try wording(of: jacaranda, in: &window)
        let ombuAtMidnight = try wording(of: ombu, in: &window)
        let stored = try engine.progressSettings()
        var atSix = stored
        atSix.dayStartsAtHour = 6
        try engine.saveProgressSettings(atSix, changedFrom: stored)
        window.read(with: scheduler)
        let ombuWithTheDayAtSix = try wording(of: ombu, in: &window)

        #expect(time.now == thursday)
        #expect(jacarandaAtEleven == .seen(times: 2, back: .today(at: twoAM)))
        #expect(jacarandaAtMidnight == .seen(times: 2, back: .today(at: twoAM)))
        #expect(ombuAtMidnight == .seen(times: 2, back: .on(thursday, inThisYear: true)))
        #expect(ombuWithTheDayAtSix == .seen(times: 2, back: .today(at: fourAM)))
    }

    // On the last day of 2026, petricor graduates at 2 in the afternoon, to
    // wait a day or more, into 2027.
    @Test("a card back on a day of another year than today's says the year", .bug(id: 537))
    func aCardBackInAnotherYearSaysTheYear() throws {
        time.move(to: try at(9, day: 31, month: 12))
        let petricor = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        try engine.climb(petricor, goods: 2, movingForward: time)
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        window.select([petricor.id])
        let row = try #require(window.shownCardRow)
        let isBack = try #require(row.frontFirst.due)
        let day = calendar.startOfDay(for: isBack)

        #expect(calendar.component(.year, from: isBack) == 2027)
        #expect(window.wording(of: row) == .seen(times: 3, back: .on(day, inThisYear: false)))
    }

    /// What the detail says of `card` in words once the user selects it in
    /// the grid, which lists the cards of the deck the sidebar chose.
    private func wording(of card: Card, in window: inout CardsWindowState) throws -> CardRow.Wording {
        window.select([card.id])
        return window.wording(of: try #require(window.shownCardRow))
    }

    /// `hour` o'clock on the `day`th of `month` 2026, October unless the test
    /// says otherwise, in Buenos Aires.
    private func at(_ hour: Int, day: Int, month: Int = 10) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }
}

extension CardsWindowState {
    /// The card the detail shows whole, or nil when it shows something else.
    fileprivate var shownCardRow: CardRow? {
        guard case .card(let row, _) = detail else {
            return nil
        }
        return row
    }
}
