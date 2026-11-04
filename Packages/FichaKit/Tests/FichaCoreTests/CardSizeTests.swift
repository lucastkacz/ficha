import FichaCore
import Testing

struct CardSizeTests {
    @Test("100% is the normal size, and each step moves it by 10%, up to 200% and down to 80%")
    func stepsStopAtTheLimits() throws {
        #expect(CardSize.normal.percent == 100)
        #expect(CardSize.normal.larger.percent == 110)
        #expect(CardSize.normal.smaller.percent == 90)

        let largest = try #require(CardSize(percent: 200))
        #expect(largest.larger == largest)
        #expect(largest.smaller.percent == 190)

        let smallest = try #require(CardSize(percent: 80))
        #expect(smallest.smaller == smallest)
        #expect(smallest.larger.percent == 90)
    }

    @Test("only a step builds from a stored percent", arguments: [85, 0, 300, -100, 70, 210, 101])
    func anythingElseDoesNotBuild(percent: Int) {
        #expect(CardSize(percent: percent) == nil)
    }

    @Test("every step from 80% to 200% builds from its percent, in order")
    func theStepsAreEveryTenPercent() {
        #expect(CardSize.steps.map(\.percent) == [80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200])
        #expect(CardSize.steps.allSatisfy { CardSize(percent: $0.percent) == $0 })
    }

    @Test("a length scales with the size, and stays as it is at 100%")
    func aLengthScales() throws {
        #expect(CardSize.normal.scaled(17) == 17)
        #expect(try #require(CardSize(percent: 150)).scaled(17) == 25.5)
        #expect(try #require(CardSize(percent: 80)).scaled(10) == 8)
    }

    @Test(
        "the panel is 400 pt wide up to 100%, and 400 pt times the size above it",
        arguments: [(80, 400.0), (90, 400), (100, 400), (110, 440), (120, 480), (200, 800)])
    func thePanelsWidth(percent: Int, width: Double) throws {
        #expect(try #require(CardSize(percent: percent)).panelWidth == width)
    }

    @Test("an image's height limit is 280 pt at 100%, doubles at 200%, and follows a short screen")
    func anImagesHeightLimit() throws {
        let largest = try #require(CardSize(percent: 200))

        // A third of the panel's tallest is past 280 pt on a large screen.
        #expect(CardSize.normal.imageHeightLimit(panelTallest: 900) == 280)
        #expect(largest.imageHeightLimit(panelTallest: 900) == 560)
        // On a short one, it's less, and scales from there.
        #expect(CardSize.normal.imageHeightLimit(panelTallest: 600) == 200)
        #expect(largest.imageHeightLimit(panelTallest: 600) == 400)
        // A window with no tallest of its own, as `make render`'s.
        #expect(CardSize.normal.imageHeightLimit(panelTallest: .infinity) == 280)
    }

    @Test("an image is never taller than the panel's tallest, at any size or on any screen")
    func anImageIsNeverTallerThanThePanel() {
        for size in CardSize.steps {
            for tallest in [120.0, 300, 600, 840, 1200] {
                #expect(size.imageHeightLimit(panelTallest: tallest) <= tallest)
            }
        }
    }

    @Test(
        "an image takes less of the width it's offered below 100%, and all of it from 100% up",
        arguments: [(80, 288.0), (90, 324), (100, 360), (150, 360), (200, 360)])
    func anImagesWidthLimit(percent: Int, width: Double) throws {
        #expect(try #require(CardSize(percent: percent)).imageWidthLimit(offered: 360) == width)
    }
}

struct CardSizeKeyTests {
    @Test("⌘+ and ⌘= make a card larger, ⌘− smaller, and ⌘0 returns it to normal")
    func eachKeyChangesTheSize() throws {
        let large = try #require(CardSize(percent: 150))

        #expect(CardSizeKey.plus.applied(to: large).percent == 160)
        #expect(CardSizeKey.equals.applied(to: large).percent == 160)
        #expect(CardSizeKey.minus.applied(to: large).percent == 140)
        #expect(CardSizeKey.zero.applied(to: large) == .normal)
    }

    // What a US, a German, an Arabic and a Zhuyin keyboard type with these keys,
    // without ⌘ and with it.
    @Test(
        "a press of ⌘ alone stands for what its layout types with ⌘",
        arguments: [
            ("=", "=", CardSizeKey.equals), ("+", "+", CardSizeKey.plus), ("-", "-", CardSizeKey.minus),
            ("0", "0", CardSizeKey.zero), ("٠", "0", CardSizeKey.zero), ("ㄢ", "0", CardSizeKey.zero),
            ("ㄦ", "-", CardSizeKey.minus),
        ])
    func aPressOfCommandAlone(typed: String, typedWithCommand: String, key: CardSizeKey) {
        #expect(CardSizeKey(typed: typed, typedWithCommand: typedWithCommand, isShiftHeld: false) == key)
    }

    // What a US, a German and a French keyboard type with these keys and Shift,
    // and with ⌘ without Shift.
    @Test(
        "a press of ⌘ and Shift stands for what its layout types with Shift",
        arguments: [("+", "=", CardSizeKey.plus), ("=", "0", CardSizeKey.equals), ("0", "à", CardSizeKey.zero)])
    func aPressOfCommandAndShift(typed: String, typedWithCommand: String, key: CardSizeKey) {
        #expect(CardSizeKey(typed: typed, typedWithCommand: typedWithCommand, isShiftHeld: true) == key)
    }

    // A French key that types à with ⌘ too, a letter, what a dead key types, and
    // more than one character.
    @Test(
        "a press of ⌘ alone that types anything else stands for no key",
        arguments: [("à", "à"), ("a", "a"), ("", ""), ("==", "==")])
    func anyOtherPressOfCommandAlone(typed: String, typedWithCommand: String) {
        #expect(CardSizeKey(typed: typed, typedWithCommand: typedWithCommand, isShiftHeld: false) == nil)
    }

    // A US keyboard's Shift on its - and 0 keys, whose ⌘ alone would act.
    @Test(
        "a press of ⌘ and Shift that types anything else stands for no key",
        arguments: [("_", "-"), (")", "0")])
    func anyOtherPressOfCommandAndShift(typed: String, typedWithCommand: String) {
        #expect(CardSizeKey(typed: typed, typedWithCommand: typedWithCommand, isShiftHeld: true) == nil)
    }
}
