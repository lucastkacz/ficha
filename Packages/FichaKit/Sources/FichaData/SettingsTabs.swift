import Foundation

// Settings' five tabs (ADR 0033, ADR 0034, ADR 0041, #492), each row where the
// desktop mock placed it, which Lucas approved on 2026-11-25: General, with
// About at its foot; Pace, How fast? and the queue new cards come from;
// Interruptions, when the review panel shows up, what holds it back and how it
// behaves once it's up; Sync; and Advanced, Anki's settings, there but out of
// sight, the offer to flag a card forgotten often, the backups and
// Diagnostics. Which tab lists which section, and which section which rows,
// is decided here, and the app draws each tab from it, in its order, so no
// row is lost on the way.

/// A tab of the Settings window. Its raw value is how the app's preferences
/// keep the tab Settings was left on, and its tab's identifier, so it never
/// changes.
public enum SettingsTab: String, Sendable, CaseIterable {
    case general
    case pace
    case interruptions
    case sync
    case advanced

    /// The tab that holds the rows of the tab `stored` named, as the app's
    /// preferences kept the tab Settings was left on, one of these or of
    /// the seven tabs before #492, so Settings opens where those rows are:
    /// nil for a name no tab had.
    public init?(stored: String) {
        switch stored {
        case "appearances", "reviewPanel": self = .interruptions
        // Scheduling's was the Ladder tab's, which it replaced (#404).
        case "ladder", "backups": self = .advanced
        case "about": self = .general
        default: self.init(rawValue: stored)
        }
    }

    /// The tabs Settings shows, in their order: Sync only in an app that
    /// syncs.
    public static func shown(syncing: Bool) -> [SettingsTab] {
        allCases.filter { $0 != .sync || syncing }
    }

    /// The tab's sections, in the order it shows them.
    public var sections: [SettingsSection] {
        switch self {
        case .general: [.general, .cardSize, .about]
        case .pace: [.howFast, .upNext]
        case .interruptions: [.whenFichaShowsUp, .holdAppearancesBack, .reviewPanel]
        case .sync: [.sync, .decksToSync]
        case .advanced:
            [.learningSteps, .relearningSteps, .retention, .forgottenOften, .backups, .copies, .diagnostics]
        }
    }
}

/// A section of a tab of Settings: its rows, under its heading, when it has
/// one, and over its footer, which the app writes.
public enum SettingsSection: Sendable, CaseIterable {
    /// General's first: what the app does around the cards.
    case general
    /// Card size, with the keys that change it under it.
    case cardSize
    /// About, at General's foot: which version of the app this is, and its
    /// privacy policy.
    case about
    /// How fast?: the three paces.
    case howFast
    /// Up next: the queue new cards come from.
    case upNext
    /// When the review panel shows up on its own.
    case whenFichaShowsUp
    /// What holds an appearance back.
    case holdAppearancesBack
    /// How the review panel behaves when it shows up on its own.
    case reviewPanel
    /// Sync through iCloud, and which cards sync.
    case sync
    /// The decks to sync, while only the cards in the decks the user chooses
    /// sync.
    case decksToSync
    /// The learning steps.
    case learningSteps
    /// The relearning steps.
    case relearningSteps
    /// The desired retention and the longest interval.
    case retention
    /// The offer to flag a card the user forgets often.
    case forgottenOften
    /// How the app backs up on its own, the last backup, and the folder the
    /// copies are in.
    case backups
    /// The copies of the user's cards, to restore or delete.
    case copies
    /// Diagnostics.
    case diagnostics

    /// The section's rows, in the order it shows them.
    public var rows: [SettingsRow] {
        switch self {
        case .general: [.startAtLogin, .dueCountInMenuBar, .captureShortcut]
        case .cardSize: [.cardSize]
        case .about: [.version, .privacyPolicy]
        case .howFast: [.pace]
        case .upNext: [.queue]
        case .whenFichaShowsUp:
            [.activeHoursStart, .activeHoursEnd, .separation, .cardsPerAppearance, .lookAhead, .waitAfterWaking]
        case .holdAppearancesBack: [.meetings, .videos, .fullScreenApps, .waitAfterSuppression]
        case .reviewPanel: [.takeTheKeyboard, .idleBeforeTakingTheKeyboard, .closeWhenUntouched]
        case .sync: [.syncWithICloud, .cardsToSync]
        case .decksToSync: [.decksToSync]
        case .learningSteps: [.learningSteps]
        case .relearningSteps: [.relearningSteps]
        case .retention: [.desiredRetention, .longestInterval]
        case .forgottenOften: [.offerToFlag, .forgottenOftenAfter]
        case .backups: [.backupFrequency, .backupsKept, .lastBackup, .backupsFolder]
        case .copies: [.copies]
        case .diagnostics: [.diagnostics]
        }
    }
}

/// A row of Settings: a setting the user changes, or what a row says or does.
public enum SettingsRow: Sendable, CaseIterable {
    /// Whether the app starts at login.
    case startAtLogin
    /// Whether the menu bar shows how many cards are due.
    case dueCountInMenuBar
    /// The shortcut that opens Capture… from any app, until #540 takes it
    /// out with Capture.
    case captureShortcut
    /// How large a card's text and images show.
    case cardSize
    /// Which version of the app this is.
    case version
    /// The link to Ficha's privacy policy.
    case privacyPolicy
    /// How fast?: the pace, the new cards a day for every deck together,
    /// which the Appearances tab's New cards per day set before.
    case pace
    /// The queue new cards come from, with Put it first.
    case queue
    /// The hour active hours start at.
    case activeHoursStart
    /// The hour active hours end at.
    case activeHoursEnd
    /// The least time between two appearances.
    case separation
    /// How many cards an appearance brings.
    case cardsPerAppearance
    /// How soon a card due later may come along.
    case lookAhead
    /// How long an appearance waits once the Mac wakes.
    case waitAfterWaking
    /// Whether a meeting holds appearances back.
    case meetings
    /// Whether a video holds appearances back.
    case videos
    /// Whether a full-screen app holds appearances back.
    case fullScreenApps
    /// How long an appearance waits once what held it back ends.
    case waitAfterSuppression
    /// When the review panel takes the keyboard as it shows up on its own.
    case takeTheKeyboard
    /// How long the user is idle before the panel takes the keyboard.
    case idleBeforeTakingTheKeyboard
    /// How long the panel stays open untouched.
    case closeWhenUntouched
    /// Whether cards sync through iCloud.
    case syncWithICloud
    /// Whether every card syncs, or only those in the decks the user chooses.
    case cardsToSync
    /// The decks to choose, while only their cards sync.
    case decksToSync
    /// The learning steps.
    case learningSteps
    /// The relearning steps.
    case relearningSteps
    /// The desired retention.
    case desiredRetention
    /// The longest interval.
    case longestInterval
    /// Whether the panel offers to flag a card the user forgets often.
    case offerToFlag
    /// After how many lapses the panel offers it.
    case forgottenOftenAfter
    /// The folder the copies are in, with Show in Finder.
    case backupsFolder
    /// How often the app backs up on its own.
    case backupFrequency
    /// How many backups it keeps.
    case backupsKept
    /// When the last backup was saved, with Back Up Now.
    case lastBackup
    /// Every copy, with Restore… and Delete….
    case copies
    /// The button that opens the Diagnostics window.
    case diagnostics
}
