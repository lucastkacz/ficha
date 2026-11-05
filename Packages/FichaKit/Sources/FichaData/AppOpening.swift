/// What an opening of the app shows as it launches, and the question the real
/// Ficha asks on the Welcome page at its first launch on a Mac, whether it
/// opens when the user logs in, since App Review turns down an app that starts
/// at login without the user's consent (Guideline 2.4.5(iii)).
///
/// The page shows until start at login is set up, which any answer does, and
/// the real Ficha's first launches did before it asked, by turning it on. When
/// macOS already starts the app at login, as when its preferences were lost but
/// not its login item, the page doesn't ask, since Not Now would leave it on,
/// and has one button. Either way the Cards window opens as the page closes.
/// Once start at login is set up, the Cards window opens only for a launch by
/// hand. Ficha Dev shows nothing as it launches, since it never starts at
/// login and `make run` stays quiet: its debug menu shows the page.
///
/// The app keeps whether it's set up in its preferences, shows what this says,
/// and turns start at login on when the answer says so; Settings changes it
/// later.
public struct AppOpening: Sendable {
    /// How this launch came.
    public enum Launch: Sendable, CaseIterable {
        /// The user opened the app, from a double click, Spotlight or `open`.
        case byHand
        /// macOS started the app as the user logged in.
        case atLogin
        /// Something launched the app for something else, as a link does:
        /// only that shows, which the app does apart from this. So does a
        /// launch that doesn't say it's by hand or at login, since silence
        /// wins when the app can't tell.
        case forSomethingElse
    }

    /// How the user answers.
    public enum Answer: Sendable {
        /// Open at Login: the app starts when the user logs in.
        case openAtLogin
        /// Not Now: the app doesn't.
        case notNow
        /// Continue, the page's one button when it doesn't ask, which leaves
        /// start at login as macOS has it.
        case continued
    }

    /// Whether the app may start at login at all: the real Ficha, and never
    /// Ficha Dev.
    private let appMayStartAtLogin: Bool
    /// Whether macOS starts the app at login now.
    private let startsAtLogin: Bool
    /// Whether start at login is set up, which the app keeps in its
    /// preferences: once it is, the Welcome page never shows again.
    public private(set) var isSetUp: Bool
    /// Whether the app turns start at login on: once the user answered Open
    /// at Login.
    public private(set) var turnsOnStartAtLogin = false
    /// Whether the Cards window opens: after the Welcome page when it shows,
    /// and as the app launches otherwise.
    public let opensCardsWindow: Bool

    /// The opening as the app launches: `appMayStartAtLogin` for the real
    /// Ficha, `isSetUp` as the app's preferences keep it, `startsAtLogin` when
    /// macOS starts the app at login now, and `launch`, how this launch came.
    public init(appMayStartAtLogin: Bool, isSetUp: Bool, startsAtLogin: Bool, launch: Launch) {
        self.appMayStartAtLogin = appMayStartAtLogin
        self.startsAtLogin = startsAtLogin
        self.isSetUp = isSetUp
        opensCardsWindow = appMayStartAtLogin && (!isSetUp || launch == .byHand)
    }

    /// Whether the Welcome page shows now: in the real Ficha, until start at
    /// login is set up.
    public var showsWelcomePage: Bool {
        appMayStartAtLogin && !isSetUp
    }

    /// Whether the page asks whether the app opens at login, with its two
    /// buttons, or has only Continue, when macOS already starts it at login.
    public var asks: Bool {
        showsWelcomePage && !startsAtLogin
    }

    /// Takes the button the user pressed, which sets start at login up, so
    /// the page never shows again, and turns it on for Open at Login.
    public mutating func answer(_ answer: Answer) {
        isSetUp = true
        turnsOnStartAtLogin = answer == .openAtLogin
    }
}
