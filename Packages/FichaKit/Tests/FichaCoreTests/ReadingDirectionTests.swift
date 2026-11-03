import FichaCore
import Testing

struct ReadingDirectionTests {
    @Test("a Spanish text reads left to right, and an Arabic or a Hebrew one right to left")
    func eachTextReadsInItsScriptsDirection() {
        #expect(ReadingDirection(of: "¿Qué es la inflación?") == .leftToRight)
        #expect(ReadingDirection(of: "كلب ينبح لا يعض") == .rightToLeft)
        #expect(ReadingDirection(of: "שלום") == .rightToLeft)
    }

    @Test("a text reads as its first letter does, after digits, punctuation or an emoji, whatever comes after")
    func theFirstLetterDecides() {
        #expect(ReadingDirection(of: "١٢ كلبًا") == .rightToLeft)
        #expect(ReadingDirection(of: "42 كلبًا") == .rightToLeft)
        #expect(ReadingDirection(of: "🐶 «Perro», en árabe كلب") == .leftToRight)
        #expect(ReadingDirection(of: "كلب (dog)") == .rightToLeft)
        #expect(ReadingDirection(of: "\n  Собака") == .leftToRight)
        #expect(ReadingDirection(of: "犬") == .leftToRight)
    }

    @Test("a text without a letter, a number or an emoji alone, has no direction of its own")
    func aTextWithoutALetterHasNoDirection() {
        #expect(ReadingDirection(of: "") == nil)
        #expect(ReadingDirection(of: "1914") == nil)
        #expect(ReadingDirection(of: "١٩١٤") == nil)
        #expect(ReadingDirection(of: "🐶 → ★") == nil)
    }
}
