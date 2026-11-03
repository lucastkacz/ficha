import FichaCore
import Testing

/// The Mac's virtual key codes, from Carbon's `Events.h`: `kVK_ANSI_1` to
/// `kVK_ANSI_5`, `kVK_ANSI_Keypad1` to `kVK_ANSI_Keypad4`, and the US
/// keyboard's R and Q.
struct RatingKeyTests {
    @Test("the number row's 1 to 4 keys are the rating keys 1 to 4, whatever the layout types with them")
    func theNumberRowRatesByPlace() {
        #expect(RatingKey.digit(forKeyCode: 0x12) == "1")
        #expect(RatingKey.digit(forKeyCode: 0x13) == "2")
        #expect(RatingKey.digit(forKeyCode: 0x14) == "3")
        #expect(RatingKey.digit(forKeyCode: 0x15) == "4")
    }

    @Test("the numeric keypad's 1 to 4 keys are the rating keys 1 to 4 too")
    func theKeypadRatesByPlace() {
        #expect(RatingKey.digit(forKeyCode: 0x53) == "1")
        #expect(RatingKey.digit(forKeyCode: 0x54) == "2")
        #expect(RatingKey.digit(forKeyCode: 0x55) == "3")
        #expect(RatingKey.digit(forKeyCode: 0x56) == "4")
    }

    @Test("any other key, as the number row's 5 or a letter, is no rating key")
    func otherKeysAreNoRatingKey() {
        #expect(RatingKey.digit(forKeyCode: 0x17) == nil)
        #expect(RatingKey.digit(forKeyCode: 0x0F) == nil)
        #expect(RatingKey.digit(forKeyCode: 0x0C) == nil)
    }
}
