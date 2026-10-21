import Foundation

/// `make render-iphone`, which takes the app's pictures in a simulator of its
/// own (`scripts/render-iphone.sh`), opens Ficha Dev with `launchArgument`.
/// Then the app doesn't ask whether it may send notifications, since iOS's
/// alert would cover its screen in every picture, and once its screen is up it
/// says so on its standard output, which the tool waits for before each
/// picture. Only Ficha Dev takes the argument: the real Ficha always asks.
enum Rendering {
    /// The launch argument the tool opens the app with.
    static let launchArgument = "-FichaRendering"

    /// Whether the tool opened the app.
    static let isOn = AppVariant.current == .dev && ProcessInfo.processInfo.arguments.contains(launchArgument)

    /// Says on the standard output that the app's screen is up, when the tool
    /// opened it, in the line the tool waits for.
    static func sayScreenIsUp() {
        if isOn {
            FileHandle.standardOutput.write(Data("The screen is up\n".utf8))
        }
    }
}
