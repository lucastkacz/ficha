import FichaCore
import Testing

/// What each layout's keys type, alone and with ⌘, read from the layout's own
/// data with `UCKeyTranslate`.
struct LetterKeyTests {
    @Test("a key that types a letter of another script stands for the Latin letter its layout types with ⌘")
    func anotherScriptGoesByCommand() {
        // Russian.
        #expect(LetterKey.letter(typed: "к", typedWithCommand: "r") == "r")
        #expect(LetterKey.letter(typed: "ф", typedWithCommand: "a") == "a")
        #expect(LetterKey.letter(typed: "ь", typedWithCommand: "m") == "m")
        #expect(LetterKey.letter(typed: "у", typedWithCommand: "e") == "e")
        // Arabic, and Arabic – PC's M.
        #expect(LetterKey.letter(typed: "ق", typedWithCommand: "r") == "r")
        #expect(LetterKey.letter(typed: "ش", typedWithCommand: "a") == "a")
        #expect(LetterKey.letter(typed: "و", typedWithCommand: "m") == "m")
        #expect(LetterKey.letter(typed: "ة", typedWithCommand: "m") == "m")
        #expect(LetterKey.letter(typed: "ث", typedWithCommand: "e") == "e")
        // 2-Set Korean.
        #expect(LetterKey.letter(typed: "ㄱ", typedWithCommand: "r") == "r")
        #expect(LetterKey.letter(typed: "ㅁ", typedWithCommand: "a") == "a")
        #expect(LetterKey.letter(typed: "ㅡ", typedWithCommand: "m") == "m")
        #expect(LetterKey.letter(typed: "ㄷ", typedWithCommand: "e") == "e")
    }

    @Test("a key that types ASCII stays as it is, whatever its layout types with ⌘")
    func asciiStays() {
        // US.
        #expect(LetterKey.letter(typed: "r", typedWithCommand: "r") == nil)
        // Dvorak – QWERTY ⌘, on QWERTY's R key: its p must not press R.
        #expect(LetterKey.letter(typed: "p", typedWithCommand: "r") == nil)
        // Dvorak – QWERTY ⌘, on QWERTY's E key: its . must not press E.
        #expect(LetterKey.letter(typed: ".", typedWithCommand: "e") == nil)
    }

    @Test("a key whose layout types no ASCII letter with ⌘ stands for no letter")
    func noLetterWithCommand() {
        // German's ö and Turkish F's ı, Latin letters of their own.
        #expect(LetterKey.letter(typed: "ö", typedWithCommand: "ö") == nil)
        #expect(LetterKey.letter(typed: "ı", typedWithCommand: "ı") == nil)
        // Russian's ж, on the key where a US keyboard types a semicolon.
        #expect(LetterKey.letter(typed: "ж", typedWithCommand: ";") == nil)
        // Arabic's ١, a rating key that goes by its place.
        #expect(LetterKey.letter(typed: "١", typedWithCommand: "1") == nil)
    }

    @Test("a dead key, which types nothing alone, stands for no letter")
    func deadKeyStandsForNoLetter() {
        // Vietnamese's A key.
        #expect(LetterKey.letter(typed: "", typedWithCommand: "a") == nil)
    }
}
