import FichaData
import Testing

/// Tests on Settings' five tabs (#492): which tab lists which section, and
/// which section which rows, as the app draws them, against the seven tabs
/// Settings had before, each row as the app titled it there.
struct SettingsTabsTests {
    /// Each row of the seven tabs Settings had before #492, by its tab and
    /// its title there, with the row of the five it became: New cards per
    /// day became How fast?'s pace. The Language row went before, with
    /// #488 (ADR 0036).
    static let rowsBefore: [(tab: String, title: String, row: SettingsRow)] = [
        ("General", "Start at login", .startAtLogin),
        ("General", "Show how many cards are due in the menu bar", .dueCountInMenuBar),
        ("General", "Capture shortcut", .captureShortcut),
        ("General", "Card size", .cardSize),
        ("Appearances", "Start at", .activeHoursStart),
        ("Appearances", "End at", .activeHoursEnd),
        ("Appearances", "At least this long apart", .separation),
        ("Appearances", "Cards per appearance", .cardsPerAppearance),
        ("Appearances", "New cards per day", .pace),
        ("Appearances", "Bring along cards due within", .lookAhead),
        ("Appearances", "After the Mac wakes, wait", .waitAfterWaking),
        ("Appearances", "Meetings", .meetings),
        ("Appearances", "Videos", .videos),
        ("Appearances", "Full-screen apps", .fullScreenApps),
        ("Appearances", "Then wait", .waitAfterSuppression),
        ("Review panel", "Take the keyboard", .takeTheKeyboard),
        ("Review panel", "Idle for", .idleBeforeTakingTheKeyboard),
        ("Review panel", "Close it when untouched for", .closeWhenUntouched),
        ("Review panel", "Offer to flag a card you forget often", .offerToFlag),
        ("Review panel", "After forgetting it 8 times", .forgottenOftenAfter),
        ("Scheduling", "Learning steps", .learningSteps),
        ("Scheduling", "Relearning steps", .relearningSteps),
        ("Scheduling", "Desired retention", .desiredRetention),
        ("Scheduling", "Longest interval", .longestInterval),
        ("Backups", "Folder", .backupsFolder),
        ("Backups", "Back up", .backupFrequency),
        ("Backups", "Backups to keep", .backupsKept),
        ("Backups", "Last backup", .lastBackup),
        ("Backups", "The copies, with Restore… and Delete…", .copies),
        ("Sync", "Sync with iCloud", .syncWithICloud),
        ("Sync", "Cards to sync", .cardsToSync),
        ("Sync", "Decks to sync", .decksToSync),
        ("About", "Version", .version),
        ("About", "Privacy Policy", .privacyPolicy),
    ]

    @Test(
        "every row of Settings' seven tabs before is in one of the five, once, and so is every row of the five",
        .bug(id: 492))
    func everyRowIsInOneTab() {
        let rows = SettingsTab.allCases.flatMap { $0.sections.flatMap(\.rows) }

        for before in Self.rowsBefore {
            #expect(rows.count { $0 == before.row } == 1, "\(before.tab)'s \(before.title)")
        }
        for row in SettingsRow.allCases {
            #expect(rows.count { $0 == row } == 1, "\(row)")
        }
        #expect(SettingsTab.allCases.flatMap(\.sections).count == SettingsSection.allCases.count)
    }

    @Test(
        "Settings has five tabs, General, Pace, Interruptions, Sync and Advanced: General ends with About, Pace shows How fast? and the queue of decks, and Advanced the learning and relearning steps, the desired retention, the longest interval and Diagnostics",
        .bug(id: 492))
    func eachTabShowsWhatTheIssueAsks() {
        let advanced = SettingsTab.advanced.sections.flatMap(\.rows)

        #expect(SettingsTab.allCases == [.general, .pace, .interruptions, .sync, .advanced])
        #expect(SettingsTab.general.sections.last == .about)
        #expect(SettingsTab.pace.sections.flatMap(\.rows) == [.pace, .queue])
        for row in [SettingsRow.learningSteps, .relearningSteps, .desiredRetention, .longestInterval, .diagnostics] {
            #expect(advanced.contains(row), "\(row)")
        }
    }

    @Test("Settings shows its Sync tab only in an app that syncs", .bug(id: 492))
    func itShowsSyncOnlyWhileSyncing() {
        #expect(SettingsTab.shown(syncing: true) == [.general, .pace, .interruptions, .sync, .advanced])
        #expect(SettingsTab.shown(syncing: false) == [.general, .pace, .interruptions, .advanced])
    }

    // The raw values the app's preferences kept for the seven tabs before:
    // Scheduling's was the Ladder tab's it replaced (#404).
    @Test("Settings opens on the tab that took the rows of the tab it was left on", .bug(id: 492))
    func itOpensWhereTheRowsWent() {
        let stored: [String: SettingsTab] = [
            "general": .general, "appearances": .interruptions, "reviewPanel": .interruptions,
            "ladder": .advanced, "backups": .advanced, "sync": .sync, "about": .general, "pace": .pace,
            "interruptions": .interruptions, "advanced": .advanced,
        ]

        for (name, tab) in stored {
            #expect(SettingsTab(stored: name) == tab, "\(name)")
        }
        #expect(SettingsTab(stored: "language") == nil)
    }
}
