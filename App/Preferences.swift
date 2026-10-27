import FichaCore
import FichaData
import Foundation
import SwiftUI
import os

/// The settings' log, which says when a stored setting can't be read.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "settings")

/// Where the app keeps what Lucas changes in Settings, and how he leaves the
/// Cards window's table: its preferences, which are its own for each app
/// (`AppVariant`), so Ficha Dev's never touch the real Ficha's. Only what
/// differs from a default is stored, so a setting Lucas never changed follows
/// its default. A stored value the app can't read, as when it was edited by
/// hand, goes into `unreadable`, for the app to say so: a setting reads as
/// its default meanwhile, and a capture shortcut as off. The settings that
/// decide a card's progress sync, so the engine keeps them in the database
/// instead (#315): the preferences keep them as they were before, for the
/// engine to move them in.
enum Preferences {
    /// The names of the stored settings that couldn't be read so far.
    private(set) static var unreadable: Set<String> = []

    /// The settings the engine decides with: this device's own, as Lucas
    /// left them, and `progress`, the settings that decide a card's
    /// progress, as the database holds them.
    static func reviewSettings(with progress: ProgressSettings) -> ReviewSettings {
        var settings = ReviewSettings.defaults
        settings.progress = progress
        settings.cardsPerAppearance =
            read(.cardsPerAppearance, as: Int.self) { $0 >= 1 ? $0 : nil } ?? settings.cardsPerAppearance
        settings.lookAhead = read(.lookAhead, as: Int.self, minutesFrom: 0) ?? settings.lookAhead
        settings.activeHours = read(.activeHours, as: [Int].self, activeHours) ?? settings.activeHours
        settings.separation = read(.separation, as: Int.self, minutesFrom: 0) ?? settings.separation
        settings.waitAfterWaking = read(.waitAfterWaking, as: Int.self, minutesFrom: 0) ?? settings.waitAfterWaking
        settings.waitAfterSuppression =
            read(.waitAfterSuppression, as: Int.self, minutesFrom: 0) ?? settings.waitAfterSuppression
        settings.suppressionsThatApply =
            read(.suppressionsThatApply, as: [String].self, suppressions) ?? settings.suppressionsThatApply
        settings.autoClose = read(.autoClose, as: Int.self, minutesFrom: 1) ?? settings.autoClose
        settings.focusMode = read(.focusMode, as: String.self, FocusMode.init(rawValue:)) ?? settings.focusMode
        settings.idleBeforeTakingKeyboard =
            read(.idleBeforeTakingKeyboard, as: Int.self) { (0...longest).contains($0) ? .seconds($0) : nil }
            ?? settings.idleBeforeTakingKeyboard
        return settings
    }

    /// The settings that decide a card's progress as the preferences kept
    /// them before they synced, which no version writes since, for the engine
    /// to move them into the database.
    static func progressSettingsBeforeSync() -> ProgressSettings {
        var settings = ReviewSettings.defaults.progress
        settings.ladder = read(.ladder, as: [Int].self, ladder) ?? settings.ladder
        settings.newCardsPerDay = read(.newCardsPerDay, as: Int.self) { $0 >= 0 ? $0 : nil } ?? settings.newCardsPerDay
        if let offer = read(.forgottenOftenAfter, as: Int.self, StoredOffer.init(stored:)) {
            settings.forgottenOftenAfter = offer.timesForgotten
        }
        return settings
    }

    /// Keeps `settings`, as Lucas changed them in Settings: this device's
    /// own, since the engine keeps the settings that decide a card's
    /// progress.
    static func save(_ settings: ReviewSettings) {
        let defaults = ReviewSettings.defaults
        write(settings.cardsPerAppearance, for: .cardsPerAppearance, unless: defaults.cardsPerAppearance)
        write(wholeMinutes(settings.lookAhead), for: .lookAhead, unless: wholeMinutes(defaults.lookAhead))
        write(
            [settings.activeHours.lowerBound, settings.activeHours.upperBound], for: .activeHours,
            unless: [defaults.activeHours.lowerBound, defaults.activeHours.upperBound])
        write(wholeMinutes(settings.separation), for: .separation, unless: wholeMinutes(defaults.separation))
        write(
            wholeMinutes(settings.waitAfterWaking), for: .waitAfterWaking,
            unless: wholeMinutes(defaults.waitAfterWaking))
        write(
            wholeMinutes(settings.waitAfterSuppression), for: .waitAfterSuppression,
            unless: wholeMinutes(defaults.waitAfterSuppression))
        write(
            Suppression.allCases.filter(settings.suppressionsThatApply.contains).map(\.rawValue),
            for: .suppressionsThatApply, unless: Suppression.allCases.map(\.rawValue))
        write(wholeMinutes(settings.autoClose), for: .autoClose, unless: wholeMinutes(defaults.autoClose))
        write(settings.focusMode.rawValue, for: .focusMode, unless: defaults.focusMode.rawValue)
        write(
            settings.idleBeforeTakingKeyboard.components.seconds, for: .idleBeforeTakingKeyboard,
            unless: defaults.idleBeforeTakingKeyboard.components.seconds)
    }

    /// How often Ficha backs up on its own, and how many backups it keeps, as
    /// Lucas left them in Settings.
    static func backupSettings() -> BackupSettings {
        var settings = BackupSettings.defaults
        settings.frequency =
            read(.backupFrequency, as: String.self, BackupSettings.Frequency.init(rawValue:)) ?? settings.frequency
        return read(.backupsKept, as: Int.self) { BackupSettings(frequency: settings.frequency, kept: $0) } ?? settings
    }

    /// Keeps `settings`, as Lucas changed them in Settings' Backups tab.
    static func save(_ settings: BackupSettings) {
        let defaults = BackupSettings.defaults
        write(settings.frequency.rawValue, for: .backupFrequency, unless: defaults.frequency.rawValue)
        write(settings.keptCount, for: .backupsKept, unless: defaults.keptCount)
    }

    /// Whether the menu-bar icon shows how many cards are due: off by
    /// default, so Ficha doesn't pressure Lucas.
    static var showsDueCount: Bool {
        get { read(.showsDueCount, as: Bool.self) { $0 } ?? false }
        set { write(newValue, for: .showsDueCount, unless: false) }
    }

    /// The shortcut that opens "Capture…" from any app, or nil when it's off:
    /// the app's own (`AppVariant.captureShortcut`) until Lucas picks another
    /// or turns it off, which an empty one stored says. One that can't be
    /// read is off, since it isn't known which one he wanted.
    static var captureShortcut: CaptureShortcut? {
        get {
            guard UserDefaults.standard.object(forKey: Key.captureShortcut.rawValue) != nil else {
                return AppVariant.current.captureShortcut
            }
            let stored = read(.captureShortcut, as: [String: Any].self) { stored -> StoredShortcut? in
                stored.isEmpty ? .off : CaptureShortcut(stored: stored).map(StoredShortcut.on)
            }
            return switch stored {
            case .on(let shortcut): shortcut
            case .off, nil: nil
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

    /// The tab Settings opens on: the one Lucas left it on last, and at
    /// first General. One that can't be read is only logged, with no alert:
    /// Settings opens on General, and the next tab Lucas picks replaces it.
    static var settingsTab: SettingsTab {
        get { read(.settingsTab, as: String.self, SettingsTab.init(rawValue:)) ?? .general }
        set { write(newValue.rawValue, for: .settingsTab, unless: SettingsTab.general.rawValue) }
    }

    /// The order the Cards window's table lists the cards in: the one Lucas
    /// left it in, and at first the newest cards first. One that can't be
    /// read is only logged, as the tab Settings opens on: the window opens
    /// with the newest first, and the next column Lucas sorts by replaces it.
    static var cardsSortOrder: [CardRowOrder] {
        get { read(.cardsSortOrder, decoding: [CardRowOrder].self) ?? CardRowOrder.newestFirst }
        set { write(newValue, encodedFor: .cardsSortOrder, unless: CardRowOrder.newestFirst) }
    }

    /// The Cards window's table columns as Lucas left them: which ones show,
    /// in what order and how wide, as SwiftUI keeps them. At first the
    /// table's own: Front, Media, Step and Due. One that can't be read is
    /// only logged, as the tab Settings opens on: the window opens with its
    /// first columns, and Lucas's next change to them replaces it. Keeping
    /// them here, with the other preferences, rather than through SwiftUI's
    /// `@AppStorage`, is our own.
    static var cardsColumns: TableColumnCustomization<CardRow> {
        get { read(.cardsColumns, decoding: TableColumnCustomization<CardRow>.self) ?? TableColumnCustomization() }
        set { write(newValue, encodedFor: .cardsColumns, unless: TableColumnCustomization()) }
    }

    /// Whether start at login is set up: the user answered whether the real
    /// Ficha opens at login, which it asks at its first launch
    /// (`StartAtLoginQuestion`), or, before it asked, it turned start at login
    /// on at its first launch. From then on, it's as the user leaves it.
    static var startsAtLoginIsSetUp: Bool {
        get { read(.startsAtLoginIsSetUp, as: Bool.self) { $0 } ?? false }
        set { write(newValue, for: .startsAtLoginIsSetUp, unless: false) }
    }

    /// Each setting's name in the preferences. Spans of time are stored in
    /// whole minutes, but the idle time, in whole seconds. The ladder, the
    /// new cards a day and the forgotten-often count are as versions before
    /// #315 left them, only to be moved into the database.
    private enum Key: String {
        case ladder = "LadderMinutes"
        case cardsPerAppearance = "CardsPerAppearance"
        case newCardsPerDay = "NewCardsPerDay"
        case lookAhead = "LookAheadMinutes"
        /// The first hour and the hour after the last one, as two numbers.
        case activeHours = "ActiveHours"
        case separation = "SeparationMinutes"
        case waitAfterWaking = "WaitAfterWakingMinutes"
        case waitAfterSuppression = "WaitAfterSuppressionMinutes"
        /// The raw values of the suppressions that apply.
        case suppressionsThatApply = "SuppressionsThatApply"
        case autoClose = "AutoCloseMinutes"
        case focusMode = "FocusMode"
        case idleBeforeTakingKeyboard = "IdleBeforeTakingKeyboardSeconds"
        /// How many reviews of one of a card's ways rated again make it
        /// forgotten often, or 0 when the review panel never offers to flag
        /// it.
        case forgottenOftenAfter = "ForgottenOftenAfter"
        /// The raw value of how often Ficha backs up on its own.
        case backupFrequency = "BackupFrequency"
        case backupsKept = "BackupsKept"
        case showsDueCount = "ShowsDueCount"
        case captureShortcut = "CaptureShortcut"
        case startsAtLoginIsSetUp = "StartsAtLoginIsSetUp"
        /// The raw value of the tab Settings opens on.
        case settingsTab = "SettingsTab"
        /// The columns the Cards window's table sorts by, in JSON.
        case cardsSortOrder = "CardsSortOrder"
        /// The Cards window's table columns, in JSON, as SwiftUI encodes them.
        case cardsColumns = "CardsColumns"
    }

    /// The setting stored for `key`, as `make` makes it out of the stored
    /// value, or nil when none is stored, or when the stored value can't be
    /// made into one: then it goes into `unreadable`, and the log says so.
    private static func read<Stored, Value>(_ key: Key, as stored: Stored.Type, _ make: (Stored) -> Value?) -> Value? {
        guard let object = UserDefaults.standard.object(forKey: key.rawValue) else {
            return nil
        }
        guard let stored = object as? Stored, let value = make(stored) else {
            logger.error(
                "Couldn't read the setting \(key.rawValue, privacy: .public): \(String(describing: object), privacy: .public)"
            )
            unreadable.insert(key.rawValue)
            return nil
        }
        return value
    }

    /// The span of time stored for `key` in whole minutes, from `least` up
    /// to a year.
    private static func read(_ key: Key, as stored: Int.Type, minutesFrom least: Int) -> Duration? {
        read(key, as: stored) { (least...longest).contains($0) ? .minutes($0) : nil }
    }

    /// The value stored for `key` in JSON, or nil when none is stored, or
    /// when it can't be decoded: then the log says why, and it goes into
    /// `unreadable`.
    private static func read<Value: Decodable>(_ key: Key, decoding type: Value.Type) -> Value? {
        read(key, as: Data.self) { data in
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                logger.error(
                    "Couldn't decode the setting \(key.rawValue, privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }
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

    /// Stores `value` for `key` in JSON, unless it's the default,
    /// `defaultValue`: then it removes what's stored, as `write` does. When
    /// it can't be encoded, what's stored stays, and the log says why.
    private static func write<Value: Encodable & Equatable>(
        _ value: Value, encodedFor key: Key, unless defaultValue: Value
    ) {
        if value == defaultValue {
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        } else {
            do {
                UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: key.rawValue)
            } catch {
                logger.error(
                    "Couldn't encode the setting \(key.rawValue, privacy: .public): \(error, privacy: .public)")
            }
        }
    }
}

extension Duration {
    /// A span of whole minutes.
    nonisolated static func minutes(_ count: Int) -> Duration {
        .seconds(count * 60)
    }
}

/// The most minutes or seconds a stored span of time may hold: a year's
/// minutes, far beyond any setting's, and too few for the span to overflow.
private let longest = 366 * 24 * 60

/// A span of time in whole minutes, leaving out any seconds.
private func wholeMinutes(_ duration: Duration) -> Int64 {
    duration.components.seconds / 60
}

/// The ladder stored as each step's wait in whole minutes, or nil unless they
/// make one, each step up to a year.
private func ladder(_ stored: [Int]) -> Ladder? {
    guard stored.allSatisfy((1...longest).contains) else {
        return nil
    }
    return Ladder(waits: stored.map(Duration.minutes))
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

/// The offer to flag a card forgotten often, as the preferences stored it
/// before it synced: the number of reviews of one of a card's ways rated
/// again that brings it, or 0 when it's off.
private struct StoredOffer {
    /// How many reviews of one of a card's ways rated again bring the offer,
    /// or nil when it's off.
    let timesForgotten: Int?

    /// The offer `stored` says, or nil unless it's 0 or a number from 1 up.
    init?(stored: Int) {
        switch stored {
        case 0: timesForgotten = nil
        case 1...: timesForgotten = stored
        default: return nil
        }
    }
}
