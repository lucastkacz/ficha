import FichaCore
import Testing

/// What the review panel's ⋯ menu offers to do with a card (ADR 0033).
struct CardActionTests {
    @Test("the ⋯ menu offers to flag and set aside, on M and E as before", .bug(id: 489), .bug(id: 539), .bug(id: 540))
    func flagAndSetAside() {
        #expect(CardAction.allCases == [.flag, .setAside])
        #expect(CardAction.allCases.map(\.key) == ["m", "e"])
    }
}
