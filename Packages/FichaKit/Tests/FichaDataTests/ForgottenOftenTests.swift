import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on cards forgotten often: recording a rating of again says whether
/// the card is now forgotten often, and how many times Lucas forgot it which
/// way, each way counted apart, with the default settings, which say so at 8
/// and again every 4 more.
struct ForgottenOftenTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("the eighth “Don't know” on a card never edited says it's forgotten often, and how many times")
    func theEighthAgainSaysTheCardIsForgottenOften() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)

        let firstSeven = try (1...7).map { _ in try forget(ubuntu) }
        let eighth = try forget(ubuntu)

        #expect(firstSeven.allSatisfy { $0 == nil })
        #expect(eighth?.times == 8)
    }

    // As Anki warns again about a leech at every half of its number.
    @Test("after the eighth, a “Don't know” says so again every four more, and not between")
    func itSaysSoAgainEveryHalfTheNumberMore() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)

        let saidSo = try (1...17).map { _ in try forget(ubuntu)?.times }

        #expect(saidSo == [nil, nil, nil, nil, nil, nil, nil, 8, nil, nil, nil, 12, nil, nil, nil, 16, nil])
    }

    @Test(
        "each way of a card that goes both ways counts its own “Don't know”: seven each way say nothing, and the eighth of either says so, and which way"
    )
    func eachWayCountsItsOwnAgains() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id])
        try engine.meet(ubuntu)
        try engine.meet(ubuntu, way: .backFirst)

        let firstSeven = try (1...7).flatMap { _ in [try forget(ubuntu, way: .backFirst), try forget(ubuntu)] }
        let eighthBackFirst = try forget(ubuntu, way: .backFirst)
        let eighthFrontFirst = try forget(ubuntu)

        #expect(firstSeven.allSatisfy { $0 == nil })
        #expect(eighthBackFirst?.times == 8)
        #expect(eighthBackFirst?.way == .backFirst)
        #expect(eighthFrontFirst?.times == 8)
        #expect(eighthFrontFirst?.way == .frontFirst)
    }

    @Test("“Sort of” and “Know it” never say it, and neither they nor a first view count")
    func otherRatingsAndFirstViewsDoNotCount() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        var saidSo: [Int?] = []

        for _ in 1...7 {
            saidSo.append(try forget(ubuntu)?.times)
            saidSo.append(try remember(ubuntu, .hard)?.times)
            saidSo.append(try remember(ubuntu, .good)?.times)
        }
        let eighth = try forget(ubuntu)
        let afterIt = [try remember(ubuntu, .hard), try remember(ubuntu, .good)]

        #expect(saidSo.allSatisfy { $0 == nil })
        #expect(eighth?.times == 8)
        #expect(afterIt == [nil, nil])
    }

    @Test("a “Don't know” in a review ahead counts")
    func anAgainInAReviewAheadCounts() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        for _ in 1...4 {
            try forget(ubuntu)
        }

        let ahead = try (1...4).map { _ in
            try engine.record(
                .review(.again), of: ubuntu.id, responseTime: .seconds(3), trigger: .reviewNow, settings: .defaults,
                reviewingAhead: true)
        }

        #expect(try engine.reviewLog().suffix(4).allSatisfy(\.isAhead))
        #expect(ahead.map { $0?.times } == [nil, nil, nil, 8])
    }

    @Test(
        "a new front or back starts the count over, from the edit, while new tags don't; a card never edited counts every “Don't know”"
    )
    func anEditToTheSidesStartsTheCountOver() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        try engine.meet(petricor)
        for _ in 1...7 {
            try forget(ubuntu)
            try forget(petricor)
        }
        time.advance(by: minutes(1))

        try engine.edit(ubuntu.id, with: card(.word, front: "ubuntu", back: "Soy porque somos."))
        try engine.edit(petricor.id, with: card(.word, front: petricor.front, back: petricor.back, tags: ["olores"]))
        let rewritten = try (1...8).map { _ in try forget(ubuntu)?.times }
        let retagged = try forget(petricor)

        #expect(rewritten == [nil, nil, nil, nil, nil, nil, nil, 8])
        #expect(retagged?.times == 8)
    }

    @Test("a new front or back starts both ways' counts over, while switching Both ways off and on starts neither")
    func anEditStartsBothWaysOverWhileSwitchingDoesNot() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id, petricor.id])
        for card in [ubuntu, petricor] {
            try engine.meet(card)
            try engine.meet(card, way: .backFirst)
        }
        for _ in 1...7 {
            for card in [ubuntu, petricor] {
                try forget(card, way: .backFirst)
                try forget(card)
            }
        }
        time.advance(by: minutes(1))

        try engine.edit(ubuntu.id, with: card(.word, front: "ubuntu", back: "Soy porque somos."))
        try engine.setBothWays(false, of: [petricor.id])
        try engine.setBothWays(true, of: [petricor.id])
        let switched = [try forget(petricor, way: .backFirst)?.times, try forget(petricor)?.times]
        let rewritten = try (1...8).flatMap { _ in
            [try forget(ubuntu, way: .backFirst)?.times, try forget(ubuntu)?.times]
        }

        #expect(switched == [8, 8])
        #expect(rewritten == Array(repeating: nil, count: 14) + [8, 8])
    }

    // Only a test's time stands still; the app's time moves on between an
    // edit and an answer, unless both fall in the same millisecond.
    @Test("a “Don't know” in the very instant the card's front or back changed counts, as after the edit")
    func anAgainInTheInstantOfAnEditCounts() throws {
        var settings = ReviewSettings.defaults
        settings.forgottenOftenAfter = 1
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))

        try engine.edit(ubuntu.id, with: card(.word, front: "ubuntu", back: "Soy porque somos."))
        let forgotten = try engine.record(
            .review(.again), of: ubuntu.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)

        #expect(forgotten?.times == 1)
    }

    /// Moves the time forward until one of `card`'s ways, front first unless
    /// the test says otherwise, is due, and rates it again, as the review
    /// panel does, and returns whether it's now forgotten often.
    @discardableResult
    private func forget(_ card: Card, way: Way = .frontFirst) throws -> ForgottenOften? {
        try rateWhenDue(card, .again, way: way)
    }

    /// Moves the time forward until `card` is due, and rates it `rating`,
    /// hard or good, and returns whether it's now forgotten often.
    private func remember(_ card: Card, _ rating: Rating) throws -> ForgottenOften? {
        try rateWhenDue(card, rating)
    }

    /// Moves the time forward until one of `card`'s ways, front first unless
    /// the test says otherwise, is due, and rates it `rating`, and returns
    /// whether it's now forgotten often.
    private func rateWhenDue(_ card: Card, _ rating: Rating, way: Way = .frontFirst) throws -> ForgottenOften? {
        time.move(to: try #require(try engine.standing(of: card.id, way: way, on: ReviewSettings.defaults.ladder).due))
        return try engine.record(
            .review(rating), of: card.id, way: way, responseTime: .seconds(3), trigger: .reviewNow,
            settings: .defaults)
    }
}
