import FichaData
import Testing

/// Tests on what each opening of the app shows, spec #447's table, and on the
/// question the real Ficha asks at its first launch, whether it opens when the
/// user logs in, which App Review asks of every app that starts at login
/// (Guideline 2.4.5(iii)).
struct AppOpeningTests {
    @Test(
        "the real Ficha that isn't set up shows the Welcome page with the question, at any launch, then the Cards window",
        arguments: AppOpening.Launch.allCases)
    func aFirstLaunchShowsTheWelcomePageWithTheQuestion(launch: AppOpening.Launch) {
        let opening = AppOpening(appMayStartAtLogin: true, isSetUp: false, startsAtLogin: false, launch: launch)

        #expect(opening.showsWelcomePage)
        #expect(opening.asks)
        #expect(opening.opensCardsWindow)
    }

    // As when the preferences were lost, but not the login item: asking then
    // could only leave it on, whatever the answer.
    @Test(
        """
        when macOS already starts the real Ficha at login, the page doesn't ask, at any launch; its one button sets \
        start at login up and turns nothing on, and the Cards window opens
        """,
        arguments: AppOpening.Launch.allCases)
    func whenItAlreadyStartsAtLoginThePageHasOneButton(launch: AppOpening.Launch) {
        var opening = AppOpening(appMayStartAtLogin: true, isSetUp: false, startsAtLogin: true, launch: launch)

        #expect(opening.showsWelcomePage)
        #expect(!opening.asks)
        #expect(opening.opensCardsWindow)
        #expect(!opening.isSetUp)

        opening.answer(.continued)

        #expect(opening.isSetUp)
        #expect(!opening.turnsOnStartAtLogin)
        #expect(!opening.showsWelcomePage)
    }

    @Test(
        "opening the real Ficha by hand once it's set up opens the Cards window, whether macOS starts it at login or not",
        arguments: [false, true])
    func openingItByHandOpensTheCardsWindow(startsAtLogin: Bool) {
        let opening = AppOpening(appMayStartAtLogin: true, isSetUp: true, startsAtLogin: startsAtLogin, launch: .byHand)

        #expect(!opening.showsWelcomePage)
        #expect(!opening.asks)
        #expect(opening.opensCardsWindow)
    }

    @Test(
        "the real Ficha that starts at login once it's set up shows nothing, whether macOS starts it at login or not",
        arguments: [false, true])
    func startingAtLoginShowsNothing(startsAtLogin: Bool) {
        let opening = AppOpening(
            appMayStartAtLogin: true, isSetUp: true, startsAtLogin: startsAtLogin, launch: .atLogin)

        #expect(!opening.showsWelcomePage)
        #expect(!opening.asks)
        #expect(!opening.opensCardsWindow)
    }

    // A link, and whatever else launches it for something of its own: only
    // that shows, which the app does on its own.
    @Test(
        "the real Ficha launched for something else once it's set up opens no window of its own, whether macOS starts it at login or not",
        arguments: [false, true])
    func aLaunchForSomethingElseOpensNoWindow(startsAtLogin: Bool) {
        let opening = AppOpening(
            appMayStartAtLogin: true, isSetUp: true, startsAtLogin: startsAtLogin, launch: .forSomethingElse)

        #expect(!opening.showsWelcomePage)
        #expect(!opening.asks)
        #expect(!opening.opensCardsWindow)
    }

    // So `make run`, which Lucas runs all day, stays quiet: its debug menu
    // shows the page.
    @Test(
        "Ficha Dev shows nothing as it launches, whatever else is so",
        arguments: AppOpening.Launch.allCases, [false, true])
    func fichaDevShowsNothing(launch: AppOpening.Launch, isSetUp: Bool) {
        for startsAtLogin in [false, true] {
            let opening = AppOpening(
                appMayStartAtLogin: false, isSetUp: isSetUp, startsAtLogin: startsAtLogin, launch: launch)

            #expect(!opening.showsWelcomePage)
            #expect(!opening.asks)
            #expect(!opening.opensCardsWindow)
        }
    }

    // Lucas's own Ficha turned start at login on at its first launch, before
    // it asked, which set it up as an answer does; his preferences go along
    // when his data moves to the sandboxed Ficha.
    @Test("it asks at the real Ficha's first launch, not once start at login is set up, and never in Ficha Dev")
    func asksOnlyAtTheRealFichasFirstLaunch() {
        let firstLaunch = AppOpening(appMayStartAtLogin: true, isSetUp: false, startsAtLogin: false, launch: .byHand)
        let setUp = AppOpening(appMayStartAtLogin: true, isSetUp: true, startsAtLogin: false, launch: .byHand)
        let fichaDev = AppOpening(appMayStartAtLogin: false, isSetUp: false, startsAtLogin: false, launch: .byHand)

        #expect(firstLaunch.asks)
        #expect(!setUp.asks)
        #expect(!fichaDev.asks)
    }

    @Test(
        "Open at Login turns start at login on, Not Now leaves it off, and either sets it up, so the app never asks again"
    )
    func eitherAnswerSetsItUp() {
        var openAtLogin = AppOpening(appMayStartAtLogin: true, isSetUp: false, startsAtLogin: false, launch: .byHand)
        var notNow = openAtLogin

        openAtLogin.answer(.openAtLogin)
        notNow.answer(.notNow)

        #expect(openAtLogin.turnsOnStartAtLogin)
        #expect(!notNow.turnsOnStartAtLogin)
        #expect(openAtLogin.isSetUp && notNow.isSetUp)
        #expect(!openAtLogin.asks && !notNow.asks)
        #expect(!openAtLogin.showsWelcomePage && !notNow.showsWelcomePage)
    }

    // A launch at login shows nothing once it's set up, but the page that
    // just set it up is still the opening that showed it.
    @Test("the Cards window opens once the page closes, even when answering sets start at login up")
    func theCardsWindowOpensAsThePageCloses() {
        var opening = AppOpening(appMayStartAtLogin: true, isSetUp: false, startsAtLogin: false, launch: .atLogin)

        opening.answer(.notNow)

        #expect(opening.opensCardsWindow)
    }
}
