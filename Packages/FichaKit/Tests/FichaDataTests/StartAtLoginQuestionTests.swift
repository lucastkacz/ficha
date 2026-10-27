import FichaData
import Testing

/// Tests on the question the real Ficha asks at its first launch, whether it
/// opens when the user logs in, which App Review asks of every app that starts
/// at login (Guideline 2.4.5(iii)).
struct StartAtLoginQuestionTests {
    // Lucas's own Ficha turned start at login on at its first launch, before
    // it asked, which set it up as an answer does; his preferences go along
    // when his data moves to the sandboxed Ficha.
    @Test("it asks at the real Ficha's first launch, not once start at login is set up, and never in Ficha Dev")
    func asksOnlyAtTheRealFichasFirstLaunch() {
        let firstLaunch = StartAtLoginQuestion(appMayStartAtLogin: true, isSetUp: false, startsAtLogin: false)
        let setUp = StartAtLoginQuestion(appMayStartAtLogin: true, isSetUp: true, startsAtLogin: false)
        let fichaDev = StartAtLoginQuestion(appMayStartAtLogin: false, isSetUp: false, startsAtLogin: false)

        #expect(firstLaunch.asks)
        #expect(!setUp.asks)
        #expect(!fichaDev.asks)
    }

    // As when the preferences were lost, but not the login item: asking then
    // could only leave it on, whatever the answer.
    @Test("when macOS already starts the real Ficha at login, it doesn't ask, and start at login is set up")
    func doesNotAskWhenItAlreadyStartsAtLogin() {
        let question = StartAtLoginQuestion(appMayStartAtLogin: true, isSetUp: false, startsAtLogin: true)

        #expect(!question.asks)
        #expect(question.isSetUp)
        #expect(!question.turnsOnStartAtLogin)
    }

    @Test(
        "Open at Login turns start at login on, Not Now leaves it off, and either sets it up, so the app never asks again"
    )
    func eitherAnswerSetsItUp() {
        var openAtLogin = StartAtLoginQuestion(appMayStartAtLogin: true, isSetUp: false, startsAtLogin: false)
        var notNow = openAtLogin

        openAtLogin.answer(.openAtLogin)
        notNow.answer(.notNow)

        #expect(openAtLogin.turnsOnStartAtLogin)
        #expect(!notNow.turnsOnStartAtLogin)
        #expect(openAtLogin.isSetUp && notNow.isSetUp)
        #expect(!openAtLogin.asks && !notNow.asks)
    }
}
