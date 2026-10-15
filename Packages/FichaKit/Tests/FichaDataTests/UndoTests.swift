import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on ⌘Z in the review panel, which undoes what Lucas did with its
/// cards, one at a time, while the panel is open.
struct UndoTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test("undoing a rating puts the card back where it stood, and the panel shows it again")
    func undoingARatingPutsTheCardBack() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("petricor", in: engine)
        try engine.meet(ubuntu)
        time.advance(by: hours(1))
        let standing = try engine.standing(of: ubuntu.id, on: settings.ladder)
        let log = try engine.reviewLog()
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)
        try panel.answer(.review(.good), responseTime: .seconds(3))

        try panel.undo()

        #expect(panel.current == .review(ubuntu))
        #expect(try engine.standing(of: ubuntu.id, on: settings.ladder) == standing)
        #expect(try engine.reviewLog() == log)
    }

    @Test("undoing a flag takes the card out of the inbox, back to the reviews, and the panel shows it again")
    func undoingAFlagTakesTheCardOutOfTheInbox() throws {
        let cards = try dueCards("ubuntu", "petricor")
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)
        try panel.flag(note: note("Falta un ejemplo"))

        try panel.undo()

        #expect(panel.current == .review(cards[0]))
        #expect(try engine.inbox().flaggedCards.isEmpty)
        #expect(try engine.reviewNow(settings) == cards.map(PanelCard.review))
    }

    @Test("undoing a bury brings the card back to the reviews, and the panel shows it again")
    func undoingABuryBringsTheCardBack() throws {
        let cards = try dueCards("ubuntu", "petricor")
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)
        try panel.bury()

        try panel.undo()

        #expect(panel.current == .review(cards[0]))
        #expect(try engine.cards().map(\.buriedAt) == [nil, nil])
        #expect(try engine.reviewNow(settings) == cards.map(PanelCard.review))
    }

    @Test("⌘Z goes back one card at a time, and no further than the first one")
    func undoGoesBackOneCardAtATime() throws {
        let cards = try dueCards("ubuntu", "petricor", "serendipia")
        let standing = try engine.standing(of: cards[0].id, on: settings.ladder)
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)
        #expect(!panel.canUndo)
        try panel.answer(.review(.good), responseTime: .seconds(3))
        try panel.bury()
        #expect(panel.canUndo)

        try panel.undo()
        #expect(panel.current == .review(cards[1]))
        try panel.undo()
        #expect(panel.current == .review(cards[0]))
        #expect(!panel.canUndo)
        try panel.undo()

        #expect(panel.current == .review(cards[0]))
        #expect(try engine.standing(of: cards[0].id, on: settings.ladder) == standing)
        #expect(try engine.reviewNow(settings) == cards.map(PanelCard.review))
    }

    // Closing the panel writes it into the appearance log, as finished or
    // snoozed, by the cards Lucas went through.
    @Test("once the panel closed, nothing is left to undo")
    func nothingIsLeftToUndoOnceThePanelClosed() throws {
        let cards = try dueCards("ubuntu", "petricor")
        var panel = engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings)
        try panel.answer(.review(.good), responseTime: .seconds(3))
        panel.close(.byLucas)

        try panel.undo()

        #expect(!panel.canUndo)
        #expect(
            try engine.standing(of: cards[0].id, on: settings.ladder) == .onLadder(step: 1, due: time.now + hours(4)))
    }

    /// Approves a word card for each front, in order, and meets them all now,
    /// so that they come due together an hour later, when this moves the
    /// time. Review now brings them in the order given.
    private func dueCards(_ fronts: String...) throws -> [Card] {
        let cards = try fronts.map { try approveCard($0, in: engine) }
        for card in cards {
            try engine.meet(card)
        }
        time.advance(by: hours(1))
        return cards
    }
}
