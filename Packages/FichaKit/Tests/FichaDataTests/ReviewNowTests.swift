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

    @Test("a new card comes in review now as a first view")
    func newCardComesAsAFirstView() throws {
        let serendipia = try approveCard("serendipia", in: engine)

        #expect(try engine.reviewNow(settings) == [.firstView(serendipia)])
    }

    @Test("a card comes back in review now as a review once its wait is over, and not before")
    func aCardComesBackOnceItsWaitIsOver() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.recordFirstView(of: serendipia.id, responseTime: .seconds(8), trigger: .reviewNow)

        time.advance(by: hours(1) - 1)
        #expect(try engine.reviewNow(settings).isEmpty)
        time.advance(by: 1)
        #expect(try engine.reviewNow(settings) == [.review(serendipia)])
    }

    @Test("review now brings at most 5 due cards, lowest step first and then the longest overdue")
    func dueCardsComeLowestStepFirstThenLongestOverdue() throws {
        // Six cards come due by the evening of the 16th, each on a step, and
        // overdue by then by:
        let ubuntu = try approveCard("ubuntu", in: engine)  // third step, 5 hours
        let petricor = try approveCard("petricor", in: engine)  // second step, 3 hours
        let serendipia = try approveCard("serendipia", in: engine)  // second step, 1 hour
        let schadenfreude = try approveCard("Schadenfreude", in: engine)  // first step, 2 hours
        let ockham = try approveCard("navaja de Ockham", in: engine)  // first step, 30 minutes
        let sunkCost = try approveCard("costo hundido", in: engine)  // first step, 10 minutes
        let evening = time.now + days(2) + hours(10)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        try engine.review(ubuntu, .good)
        time.advance(by: hours(4))
        try engine.review(ubuntu, .good)
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

        #expect(try engine.reviewNow(settings) == met.map(PanelCard.review) + [.firstView(ockham)])
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

        #expect(try engine.reviewNow(settings) == met.map(PanelCard.review))
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
        #expect(try engine.reviewNow(settings) == [.firstView(cards[4])])
        try engine.meet(cards[4])
        #expect(try engine.reviewNow(settings).isEmpty)

        time.move(to: calendar.startOfDay(for: try morning(of: 15, in: calendar)))

        #expect(try engine.reviewNow(settings) == [.firstView(cards[5])])
    }
}
