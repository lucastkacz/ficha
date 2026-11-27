import FichaCore
import Testing

/// The review panel's three buttons and its rating keys, once a card's lower
/// side shows (ADR 0039).
struct AnswerButtonTests {
    @Test("the buttons are Forgot, Kind of and Got it, in that order, and Kind of's key is 2", .bug(id: 517))
    func theThreeButtons() {
        #expect(AnswerButton.allCases == [.forgot, .kindOf, .gotIt])
        #expect(AnswerButton.kindOf.key == .digit("2"))
    }

    @Test(
        "Forgot and key 1 record again, Kind of and key 2 hard, Got it, Space and key 3 good, and key 4 nothing",
        .bug(id: 517))
    func theKeysRecordTheButtonsRatings() {
        let keys: [Character] = ["1", "2", "3", "4"]

        #expect(AnswerButton.allCases.map(\.rating) == [.again, .hard, .good])
        #expect(AnswerButton.forgot.key == .digit("1"))
        #expect(AnswerButton.gotIt.key == .space)
        #expect(keys.map(AnswerButton.init(ratingKey:)) == [.forgot, .kindOf, .gotIt, nil])
    }
}
