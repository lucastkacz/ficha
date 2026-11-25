import FichaCore
import Testing

/// The review panel's two buttons and its rating keys, once a card's lower
/// side shows (ADR 0033).
struct AnswerButtonTests {
    @Test("Forgot records again, on key 1, and Got it records good, on Space", .bug(id: 489))
    func theTwoButtons() {
        #expect(AnswerButton.allCases == [.forgot, .gotIt])
        #expect(AnswerButton.forgot.rating == .again)
        #expect(AnswerButton.forgot.key == .digit("1"))
        #expect(AnswerButton.gotIt.rating == .good)
        #expect(AnswerButton.gotIt.key == .space)
    }

    @Test("keys 1 to 4 still record again, hard, good and easy, and 2 and 4 have no button", .bug(id: 489))
    func theFourKeys() {
        #expect(Rating.allCases.map(RatingKey.digit(of:)) == ["1", "2", "3", "4"])
        #expect(Rating.allCases == [.again, .hard, .good, .easy])
        let buttonKeys = AnswerButton.allCases.map(\.key)
        #expect(!buttonKeys.contains(.digit("2")))
        #expect(!buttonKeys.contains(.digit("4")))
    }
}
