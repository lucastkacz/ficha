/// The question the real Ficha asks at its first launch, whether it opens
/// when the user logs in, since App Review turns down an app that starts at
/// login without the user's consent (Guideline 2.4.5(iii)). It asks until
/// start at login is set up, which either answer does, and the real Ficha's
/// first launches did before it asked, by turning it on. Ficha Dev never asks,
/// since it never starts at login. The app keeps whether it's set up in its
/// preferences, shows the alert while the question `asks`, and turns start at
/// login on when the answer says so; Settings changes it later.
public struct StartAtLoginQuestion: Sendable, Equatable {
    /// How the user answers.
    public enum Answer: Sendable {
        /// Open at Login: the app starts when the user logs in.
        case openAtLogin
        /// Not Now: the app doesn't.
        case notNow
    }

    /// Whether the app may start at login at all: the real Ficha, and never
    /// Ficha Dev.
    private let appMayStartAtLogin: Bool
    /// Whether start at login is set up, which the app keeps in its
    /// preferences: once it is, the app never asks again.
    public private(set) var isSetUp: Bool

    /// The question as the app launches: `appMayStartAtLogin` for the real
    /// Ficha, and `isSetUp` as the app's preferences keep it.
    public init(appMayStartAtLogin: Bool, isSetUp: Bool) {
        self.appMayStartAtLogin = appMayStartAtLogin
        self.isSetUp = isSetUp
    }

    /// Whether the app asks now: in the real Ficha, until start at login is
    /// set up.
    public var asks: Bool {
        appMayStartAtLogin && !isSetUp
    }

    /// Takes the user's answer, which sets start at login up, so the app
    /// never asks again: whether the app turns start at login on, which only
    /// Open at Login does.
    public mutating func answer(_ answer: Answer) -> Bool {
        isSetUp = true
        return answer == .openAtLogin
    }
}
