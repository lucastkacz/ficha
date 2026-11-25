import FichaCore
import Testing

/// What the review panel's ⋯ menu offers to do with a card (ADR 0033).
struct CardActionTests {
    @Test("the ⋯ menu offers to ask, flag and bury, on A, M and E as before", .bug(id: 489))
    func askFlagAndBury() {
        #expect(CardAction.allCases == [.ask, .flag, .bury])
        #expect(CardAction.allCases.map(\.key) == ["a", "m", "e"])
    }
}
