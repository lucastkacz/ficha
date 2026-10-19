import FichaCore
import Foundation
import os

/// The settings' log, which says when a stored setting can't be read.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "settings")

/// Where the app keeps what Lucas changes in Settings: its preferences, which
/// are its own for each app (`AppVariant`), so Ficha Dev's never touch the
/// real Ficha's. Only what differs from a default is stored, so a setting
/// Lucas never changed follows its default. A stored value the app can't
/// read, as when it was edited by hand, reads as its default, and the log
/// says why.
enum Preferences {
    /// The settings the engine decides with, as Lucas left them.
    static func reviewSettings() -> ReviewSettings {
        var settings = ReviewSettings.defaults
        settings.ladder = read(.ladder, as: [Int].self) { Ladder(waits: $0.map(minutes)) } ?? settings.ladder
        settings.cardsPerAppearance =
            read(.cardsPerAppearance, as: Int.self) { $0 >= 1 ? $0 : nil } ?? settings.cardsPerAppearance
        settings.newCardsPerDay = read(.newCardsPerDay, as: Int.self) { $0 >= 0 ? $0 : nil } ?? settings.newCardsPerDay
        settings.lookAhead = read(.lookAhead, as: Int.self, minutesFrom: 0) ?? settings.lookAhead
        settings.activeHours = read(.activeHours, as: [Int].self, activeHours) ?? settings.activeHours
        settings.separation = read(.separation, as: Int.self, minutesFrom: 0) ?? settings.separation
        settings.waitAfterSuppression =
            read(.waitAfterSuppression, as: Int.self, minutesFrom: 0) ?? settings.waitAfterSuppression
        settings.suppressionsThatApply =
            read(.suppressionsThatApply, as: [String].self, suppressions) ?? settings.suppressionsThatApply
        settings.autoClose = read(.autoClose, as: Int.self, minutesFrom: 1) ?? settings.autoClose
        settings.focusMode = read(.focusMode, as: String.self, FocusMode.init(rawValue:)) ?? settings.focusMode
        return settings
    }

    /// Keeps `settings`, as Lucas changed them in Settings.
    static func save(_ settings: ReviewSettings) {
        let defaults = ReviewSettings.defaults
        write(settings.ladder.waits.map(wholeMinutes), for: .ladder, unless: defaults.ladder.waits.map(wholeMinutes))
        write(settings.cardsPerAppearance, for: .cardsPerAppearance, unless: defaults.cardsPerAppearance)
        write(settings.newCardsPerDay, for: .newCardsPerDay, unless: defaults.newCardsPerDay)
        write(wholeMinutes(settings.lookAhead), for: .lookAhead, unless: wholeMinutes(defaults.lookAhead))
        write(
            [settings.activeHours.lowerBound, settings.activeHours.upperBound], for: .activeHours,
            unless: [defaults.activeHours.lowerBound, defaults.activeHours.upperBound])
        write(wholeMinutes(settings.separation), for: .separation, unless: wholeMinutes(defaults.separation))
        write(
            wholeMinutes(settings.waitAfterSuppression), for: .waitAfterSuppression,
            unless: wholeMinutes(defaults.waitAfterSuppression))
        write(
            Suppression.allCases.filter(settings.suppressionsThatApply.contains).map(\.rawValue),
            for: .suppressionsThatApply, unless: Suppression.allCases.map(\.rawValue))
        write(wholeMinutes(settings.autoClose), for: .autoClose, unless: wholeMinutes(defaults.autoClose))
        write(settings.focusMode.rawValue, for: .focusMode, unless: defaults.focusMode.rawValue)
    }

    /// Whether the menu-bar icon shows how many cards are due: off by
    /// default, so Ficha doesn't pressure Lucas.
    static var showsDueCount: Bool {
        get { read(.showsDueCount, as: Bool.self) { $0 } ?? false }
        set { write(newValue, for: .showsDueCount, unless: false) }
    }

    /// The shortcut that opens "Capture…" from any app, or nil when Lucas
    /// turned it off: the app's own (`AppVariant.captureShortcut`) until he
    /// picks another. An empty one stored says he turned it off.
    static var captureShortcut: CaptureShortcut? {
        get {
            let stored = read(.captureShortcut, as: [String: Any].self) { stored -> StoredShortcut? in
                stored.isEmpty ? .off : CaptureShortcut(stored: stored).map(StoredShortcut.on)
            }
            return switch stored {
            case .on(let shortcut): shortcut
            case .off: nil
            case nil: AppVariant.current.captureShortcut
            }
        }
        set {
            if newValue == AppVariant.current.captureShortcut {
                UserDefaults.standard.removeObject(forKey: Key.captureShortcut.rawValue)
            } else {
                UserDefaults.standard.set(newValue?.stored ?? [:], forKey: Key.captureShortcut.rawValue)
            }
        }
    }

    /// Whether the real Ficha already turned on starting at login, its
    /// default, the first time it launched: from then on, it's as Lucas
    /// leaves it.
    static var startsAtLoginIsSetUp: Bool {
        get { read(.startsAtLoginIsSetUp, as: Bool.self) { $0 } ?? false }
        set { write(newValue, for: .startsAtLoginIsSetUp, unless: false) }
    }

    /// Each setting's name in the preferences. Spans of time are stored in
    /// whole minutes.
    private enum Key: String {
        case ladder = "LadderMinutes"
        case cardsPerAppearance = "CardsPerAppearance"
        case newCardsPerDay = "NewCardsPerDay"
        case lookAhead = "LookAheadMinutes"
        /// The first hour and the hour after the last one, as two numbers.
        case activeHours = "ActiveHours"
        case separation = "SeparationMinutes"
        case waitAfterSuppression = "WaitAfterSuppressionMinutes"
        /// The raw values of the suppressions that apply.
        case suppressionsThatApply = "SuppressionsThatApply"
        case autoClose = "AutoCloseMinutes"
        case focusMode = "FocusMode"
        case showsDueCount = "ShowsDueCount"
        case captureShortcut = "CaptureShortcut"
        case startsAtLoginIsSetUp = "StartsAtLoginIsSetUp"
    }

    /// The setting stored for `key`, as `read` makes it out of the stored
    /// value, or nil when none is stored, or when the stored value can't be
    /// made into one: then the log says so.
    private static func read<Stored, Value>(_ key: Key, as stored: Stored.Type, _ make: (Stored) -> Value?) -> Value? {
        guard let object = UserDefaults.standard.object(forKey: key.rawValue) else {
            return nil
        }
        guard let stored = object as? Stored, let value = make(stored) else {
            logger.error(
                "Couldn't read the setting \(key.rawValue, privacy: .public), so it's at its default: \(String(describing: object), privacy: .public)"
            )
            return nil
        }
        return value
    }

    /// The span of time stored for `key` in whole minutes, `least` at least.
    private static func read(_ key: Key, as stored: Int.Type, minutesFrom least: Int) -> Duration? {
        read(key, as: stored) { $0 >= least ? minutes($0) : nil }
    }

    /// Stores `value` for `key`, unless it's the default, `defaultValue`:
    /// then it removes what's stored, so the setting follows its default.
    private static func write<Value: Equatable>(_ value: Value, for key: Key, unless defaultValue: Value) {
        if value == defaultValue {
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        } else {
            UserDefaults.standard.set(value, forKey: key.rawValue)
        }
    }
}

/// A span of whole minutes.
private func minutes(_ count: Int) -> Duration {
    .seconds(count * 60)
}

/// A span of time in whole minutes, leaving out any seconds.
private func wholeMinutes(_ duration: Duration) -> Int {
    Int(duration.components.seconds / 60)
}

/// The active hours stored as two numbers, the first hour and the hour after
/// the last one, or nil unless they make a part of the day.
private func activeHours(_ stored: [Int]) -> Range<Int>? {
    guard stored.count == 2, 0 <= stored[0], stored[0] < stored[1], stored[1] <= 24 else {
        return nil
    }
    return stored[0]..<stored[1]
}

/// The suppressions stored by their raw values, or nil when one isn't known.
private func suppressions(_ stored: [String]) -> Set<Suppression>? {
    let known = stored.compactMap(Suppression.init(rawValue:))
    return known.count == stored.count ? Set(known) : nil
}

/// A capture shortcut Lucas picked, or turned off, as the preferences store
/// it.
private enum StoredShortcut {
    case on(CaptureShortcut)
    case off
}
