import FichaData
import Testing

/// Tests on the question the real Ficha asks at its first launch, whether it
/// opens when the user logs in, which App Review asks of every app that starts
/// at login (Guideline 2.4.5(iii)).
struct StartAtLoginQuestionTests {
    @Test("at the real Ficha's first launch, it asks whether to open at login")
    func asksAtFirstLaunch() {
        let question = StartAtLoginQuestion(appMayStartAtLogin: true, isSetUp: false)

        #expect(question.asks)
    }

    // Lucas's own Ficha turned start at login on at its first launch, before
    // it asked, which set it up as an answer does; his preferences go along
    // when his data moves to the sandboxed Ficha.
    @Test("once start at login is set up, the real Ficha doesn't ask")
    func doesNotAskOnceSetUp() {
        let question = StartAtLoginQuestion(appMayStartAtLogin: true, isSetUp: true)

        #expect(!question.asks)
    }

    @Test("Ficha Dev never asks, since it never starts at login")
    func fichaDevNeverAsks() {
        let question = StartAtLoginQuestion(appMayStartAtLogin: false, isSetUp: false)

        #expect(!question.asks)
    }

    @Test("Open at Login turns start at login on, and sets it up, so the app never asks again")
    func openAtLoginTurnsItOn() {
        var question = StartAtLoginQuestion(appMayStartAtLogin: true, isSetUp: false)

        let turnsOn = question.answer(.openAtLogin)

        #expect(turnsOn)
        #expect(question.isSetUp)
        #expect(!question.asks)
    }

    @Test("Not Now leaves start at login off, and sets it up, so the app never asks again")
    func notNowLeavesItOff() {
        var question = StartAtLoginQuestion(appMayStartAtLogin: true, isSetUp: false)

        let turnsOn = question.answer(.notNow)

        #expect(!turnsOn)
        #expect(question.isSetUp)
        #expect(!question.asks)
    }
}
