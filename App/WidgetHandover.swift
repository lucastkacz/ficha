import FichaData
import Foundation
import os

/// The widget's log, in the app and in the widget's extension, which both
/// compile this file: so a run with the widget reads from the log alone. Card
/// ids and ways only, never a card's content.
let widgetLogger = Logger(subsystem: "com.lucastkacz.ficha", category: "widget")

/// What the app hands its widget (#171), which runs in a sandbox of its own,
/// in a process of its own: the app and the widget's extension both compile
/// this file.
enum WidgetHandover {
    /// The scheme of the links a click on the widget opens the app with, which
    /// the app claims: `FICHA_URL_SCHEME` in `project.yml`, which the build
    /// writes in the app's Info.plist and in the extension's, one for each
    /// app, so a link opens the app whose widget made it. Nil when the
    /// Info.plist doesn't say, as a build outside Xcode's doesn't.
    static var linkScheme: String? {
        Bundle.main.object(forInfoDictionaryKey: "FichaURLScheme") as? String
    }

    /// Hands the widget `settings`, what it needs of this Mac's settings, which
    /// the app keeps in its own preferences, where the widget can't read
    /// them: in the defaults of the app's App Group, Apple's documented way
    /// to share data with an extension, where the app and its widget share
    /// the group (`AppVariant.groupDefaults`).
    static func handOver(_ settings: WidgetSettings) {
        AppVariant.current.groupDefaults?.set(settings.cardsPerAppearance, forKey: cardsPerAppearanceKey)
    }

    /// What the app handed the widget, or nil before it did, where the two
    /// don't share a group, or when what's there isn't what the app writes,
    /// which the log says.
    static func handedOver() -> WidgetSettings? {
        guard let stored = AppVariant.current.groupDefaults?.object(forKey: cardsPerAppearanceKey) else {
            return nil
        }
        guard let count = stored as? Int, let settings = WidgetSettings(cardsPerAppearance: count) else {
            widgetLogger.error(
                "Ignored the cards per appearance the app handed over, which aren't a count of 1 or more")
            return nil
        }
        return settings
    }

    /// The key of the cards per appearance in the group's defaults.
    private static let cardsPerAppearanceKey = "cardsPerAppearance"
}
