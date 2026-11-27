import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on how a card's detail in the Cards window says where the card is
/// in words (#537): that a new card is new, how many times the user has seen
/// a card, and when it's back, as the desktop mock's card pane says it, on
/// the default scheduler. They start at 9 in the morning of Wednesday the
/// 14th of October in Buenos Aires.
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

        #expect(said[serendipia.id] == .new)
        #expect(said[ojala.id] == .seen(times: 1, back: .now))
        #expect(said[ubuntu.id] == .seen(times: 1, back: .today(at: time.now + hours(1))))
        #expect(!calendar.isDate(petricorIsBack, inSameDayAs: time.now))
        #expect(said[petricor.id] == .seen(times: 3, back: .on(calendar.startOfDay(for: petricorIsBack))))
    }

    // Ficha's day starts at 4 in the morning (ADR 0045). At 9 at night,
    // lechuza is met, due at 10, and rated Good then, which puts it on its
    // second learning step, 4 hours, due at 2 in the morning. At 11, búho is
    // met, due at midnight. Read at 11, lechuza is back later today, though
    // after midnight. At midnight búho is rated Good, due at 4 in the
    // morning: read then, it's back on the 15th, Ficha's next day, though
    // that's the date it is.
    @Test(
        "a card's detail counts its days from 4 in the morning, so a card back at 2 is back later today, and one back at 4 on that day",
        .bug(id: 537))
    func aCardsDetailCountsItsDaysFromFourInTheMorning() throws {
        let lechuza = try engine.create(card(nil, front: "lechuza", back: "Un ave de la noche."))
        let buho = try engine.create(card(nil, front: "búho", back: "Otra ave de la noche."))
        time.move(to: time.now + hours(12))
        try engine.meet(lechuza)
        try engine.reviewWhenDue(lechuza, .good, movingForward: time)
        time.move(to: time.now + hours(1))
        try engine.meet(buho)
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        window.select([lechuza.id])
        let lechuzaAtEleven = window.wording(of: try #require(window.shownCardRow))
        let lechuzaIsBack = time.now + hours(3)

        try engine.reviewWhenDue(buho, .good, movingForward: time)
        window.read(with: scheduler)
        window.select([buho.id])
        let buhoAtMidnight = window.wording(of: try #require(window.shownCardRow))
        let buhoIsBack = time.now + hours(4)

        #expect(!calendar.isDate(lechuzaIsBack, inSameDayAs: time.now - hours(1)))
        #expect(lechuzaAtEleven == .seen(times: 2, back: .today(at: lechuzaIsBack)))
        #expect(calendar.isDate(buhoIsBack, inSameDayAs: time.now))
        #expect(buhoAtMidnight == .seen(times: 2, back: .on(calendar.startOfDay(for: buhoIsBack))))
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
