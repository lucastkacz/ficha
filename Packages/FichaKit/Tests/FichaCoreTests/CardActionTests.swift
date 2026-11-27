import FichaCore
import Testing

/// What the review panel's ⋯ menu offers to do with a card (ADR 0033).
struct CardActionTests {
    @Test("the ⋯ menu offers to ask, flag and set aside, on A, M and E as before", .bug(id: 489), .bug(id: 539))
    func askFlagAndSetAside() {
        #expect(CardAction.allCases == [.ask, .flag, .setAside])
        #expect(CardAction.allCases.map(\.key) == ["a", "m", "e"])
    }
}
