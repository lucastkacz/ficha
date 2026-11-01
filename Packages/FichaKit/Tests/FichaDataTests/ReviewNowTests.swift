import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the cards review now brings to the review panel.
struct ReviewNowTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("a new card comes in review now as a new card, front first, for its first review")
    func newCardComesAsANewCard() throws {
        let serendipia = try approveCard("serendipia", in: engine)

        #expect(try engine.reviewNow(settings) == [.new(serendipia, .frontFirst)])
    }

    @Test("a card comes back in review now as a review once it's due, and not before")
    func aCardComesBackOnceItsDue() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)

        time.advance(by: hours(1) - 1)
        #expect(try engine.reviewNow(settings).isEmpty)
        time.advance(by: 1)
        #expect(try engine.reviewNow(settings) == [.review(serendipia)])
    }

    @Test("review now brings at most 5 due cards, the shortest interval first and then the longest overdue")
    func dueCardsComeShortestIntervalFirstThenLongestOverdue() throws {
        // Six cards come due by the evening, each with an interval, and
        // overdue by then by:
        let ubuntu = try approveCard("ubuntu", in: engine)  // graduated, days, 5 hours
        let petricor = try approveCard("petricor", in: engine)  // second learning step, 4 hours, 3 hours
        let serendipia = try approveCard("serendipia", in: engine)  // second learning step, 4 hours, 1 hour
        let schadenfreude = try approveCard("Schadenfreude", in: engine)  // first learning step, 1 hour, 2 hours
        let ockham = try approveCard("navaja de Ockham", in: engine)  // first learning step, 1 hour, 30 minutes
        let sunkCost = try approveCard("costo hundido", in: engine)  // first learning step, 1 hour, 10 minutes
        try engine.climb(ubuntu, goods: 2, movingForward: time)
        let evening = try #require(try engine.standing(of: ubuntu.id, with: settings.scheduler).due) + hours(5)
        time.move(to: evening - hours(8))
        try engine.meet(petricor)
        time.advance(by: hours(1))
        try engine.review(petricor, .good)
        time.move(to: evening - hours(6))
        try engine.meet(serendipia)
        time.advance(by: hours(1))
        try engine.review(serendipia, .good)
        time.move(to: evening - hours(3))
        try engine.meet(schadenfreude)
        time.move(to: evening - minutes(90))
        try engine.meet(ockham)
        time.move(to: evening - minutes(70))
        try engine.meet(sunkCost)

        time.move(to: evening)

        #expect(
            try engine.reviewNow(settings) == [
                .review(schadenfreude), .review(ockham), .review(sunkCost), .review(petricor), .review(serendipia),
            ]
        )
    }

    @Test("with room left, review now brings one new card after the due ones: the first one Lucas approved")
    func oneNewCardComesAfterTheDueOnes() throws {
        let met = try ["ubuntu", "petricor", "serendipia", "Schadenfreude"].map { try approveCard($0, in: engine) }
        let ockham = try approveCard("navaja de Ockham", in: engine)
        try approveCard("costo hundido", in: engine)
        for card in met {
            try engine.meet(card)
            time.advance(by: minutes(1))
        }

        time.move(to: try morning(of: 15, in: calendar))

        #expect(try engine.reviewNow(settings) == met.map { PanelCard.review($0) } + [.new(ockham)])
    }

    @Test("a new card waits while due cards fill review now")
    func newCardsWaitWhileDueCardsFillReviewNow() throws {
        let met = try ["ubuntu", "petricor", "serendipia", "Schadenfreude", "navaja de Ockham"].map {
            try approveCard($0, in: engine)
        }
        try approveCard("costo hundido", in: engine)
        for card in met {
            try engine.meet(card)
            time.advance(by: minutes(1))
        }

        time.move(to: try morning(of: 15, in: calendar))

        #expect(try engine.reviewNow(settings) == met.map { PanelCard.review($0) })
    }

    @Test("new cards stop at 5 a day, and start again when the day does, by the Mac's calendar")
    func newCardsStopAtFiveADay() throws {
        let cards = try ["ubuntu", "petricor", "serendipia", "Schadenfreude", "navaja de Ockham", "costo hundido"].map {
            try approveCard($0, in: engine)
        }
        // At 23:10 in Buenos Aires, so that none is due again before midnight
        // there, which is 3 in the morning in UTC.
        time.advance(by: hours(14) + minutes(10))
        for card in cards.prefix(4) {
            try engine.meet(card)
        }
        #expect(try engine.reviewNow(settings) == [.new(cards[4])])
        try engine.meet(cards[4])
        #expect(try engine.reviewNow(settings).isEmpty)

        time.move(to: calendar.startOfDay(for: try morning(of: 15, in: calendar)))

        #expect(try engine.reviewNow(settings) == [.new(cards[5])])
    }

    @Test(
        "a card that goes both ways comes back first, new, for that way's first review, once Lucas had its first review front first, and not before"
    )
    func aCardThatGoesBothWaysComesBackFirstOnceMet() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let bothWays = try #require(try engine.setBothWays(true, of: [serendipia.id]).first)

        let beforeMeetingIt = try engine.reviewNow(settings)
        try engine.meet(bothWays)

        #expect(beforeMeetingIt == [.new(bothWays)])
        #expect(try engine.reviewNow(settings) == [.new(bothWays, .backFirst)])
    }

    @Test("new cards and new back-first ways take turns, a new card first each day, back first in the cards' order")
    func newCardsAndBackFirstWaysTakeTurns() throws {
        let met = try ["serendipia", "ubuntu"].map { try approveCard($0, in: engine) }
        let new = try ["petricor", "Schadenfreude"].map { try approveCard($0, in: engine) }
        for card in met {
            try engine.meet(card)
        }
        let bothWays = try engine.setBothWays(true, of: Set(met.map(\.id)))
        time.move(to: try morning(of: 15, in: calendar))

        let first = try newWayNow()
        try engine.meet(new[0])
        let second = try newWayNow()
        try engine.meet(bothWays[0], way: .backFirst)
        let third = try newWayNow()
        try engine.meet(new[1])
        let fourth = try newWayNow()

        #expect(first == .new(new[0]))
        #expect(second == .new(bothWays[0], .backFirst))
        #expect(third == .new(new[1]))
        #expect(fourth == .new(bothWays[1], .backFirst))
    }

    @Test("a new back-first way comes after another when no new card waits")
    func backFirstWaysComeOneAfterAnotherWhenNoNewCardWaits() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id, ubuntu.id])
        try engine.meet(serendipia)
        try engine.meet(ubuntu)

        try engine.meet(bothWays[0], way: .backFirst)

        #expect(try newWayNow() == .new(bothWays[1], .backFirst))
    }

    @Test("due ways with the same interval and due at the same time come by card, each card's front-first way first")
    func tiedDueWaysComeByCardFrontFirstFirst() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let bothWays = try engine.setBothWays(true, of: [serendipia.id, ubuntu.id])
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        try engine.meet(bothWays[1], way: .backFirst)
        try engine.meet(bothWays[0], way: .backFirst)

        time.advance(by: hours(1))

        #expect(
            try engine.reviewNow(settings) == [
                .review(bothWays[0]), .review(bothWays[0], .backFirst), .review(bothWays[1]),
                .review(bothWays[1], .backFirst),
            ])
    }

    /// The new way review now brings, after the due ones, if any.
    private func newWayNow() throws -> PanelCard? {
        try engine.reviewNow(settings).first { panelCard in
            if case .new = panelCard { true } else { false }
        }
    }
}
