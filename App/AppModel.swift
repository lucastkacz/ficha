import FichaCore
import FichaData
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "menu")

/// The app's way into Lucas's cards: it goes through the engine and keeps what
/// the menu shows up to date, whether the app or the `ficha` CLI changed it.
@Observable
final class AppModel {
    /// The engine on Lucas's cards, which sync through iCloud works on too.
    let engine: Engine
    /// What Ficha Dev's debug menu does, or nil in the real Ficha, which has no
    /// debug menu.
    let debugTools: DebugTools?
    /// The settings the engine decides with, as Lucas left them in Settings:
    /// this device's own, which the app keeps in its preferences, and the
    /// settings that decide a card's progress, which the engine keeps in the
    /// database, since they sync, and which another device may change. A
    /// change applies from the next decision on, and the menu counts again at
    /// once; an open review panel keeps the settings it opened with.
    var settings: ReviewSettings {
        didSet {
            Preferences.save(settings)
            if settings.progress != oldValue.progress {
                keepProgressSettings(changedFrom: oldValue.progress)
            }
            countProgress()
        }
    }
    /// Why the engine couldn't keep the last change to the settings that
    /// decide a card's progress, for Settings to say, until Lucas closes its
    /// alert. Settings shows the change meanwhile, until the database changes
    /// again or the app quits.
    var progressSettingsFailure: EngineError?
    /// Whether the menu-bar icon shows how many cards are due: off by
    /// default, so Ficha doesn't pressure Lucas.
    var showsDueCount = Preferences.showsDueCount {
        didSet {
            Preferences.showsDueCount = showsDueCount
        }
    }
    /// How often Ficha backs up on its own, and how many backups it keeps, as
    /// Lucas left them in Settings, which keeps them in the app's
    /// preferences. A change applies from the next backup on.
    var backupSettings = Preferences.backupSettings() {
        didSet {
            Preferences.save(backupSettings)
        }
    }
    /// The backups the app saves on its own, once they started, and Settings'
    /// Backups tab, which lists the copies and acts on them: the menu says
    /// when the last backup failed.
    var backups: BackupsState
    /// Settings' Sync tab, and the menu's line while iCloud is full, which
    /// the app's delegate opens as it starts syncing, or nil while the app
    /// doesn't sync, which shows neither: the real Ficha, until #318, and a
    /// Ficha Dev on a scratch folder or not signed for iCloud.
    var sync: SyncTabState?
    /// What the menu shows of Lucas's progress, or nil when it couldn't be
    /// counted (the engine logs why).
    private(set) var progress: ProgressCounts?
    /// What the menu's Prioritize submenu offers, as the engine reads it, or
    /// nil when it couldn't be read (the engine logs why).
    private(set) var prioritizeMenu: PrioritizeMenu?

    /// The real Ficha's way into Lucas's cards, through `engine`, or why the
    /// settings that decide a card's progress couldn't be read.
    convenience init(engine: Engine) throws(EngineError) {
        try self.init(engine: engine, debugTools: nil)
    }

    /// Ficha Dev's, through the engine its debug tools run on their time.
    convenience init(debugTools: DebugTools) throws(EngineError) {
        try self.init(engine: debugTools.engine, debugTools: debugTools)
    }

    private init(engine: Engine, debugTools: DebugTools?) throws(EngineError) {
        self.engine = engine
        self.debugTools = debugTools
        settings = Preferences.reviewSettings(with: try Self.movedInProgressSettings(of: engine))
        backups = engine.openBackups()
        // Listening before counting, so no change falls in between.
        let changes = engine.changes()
        countProgress()
        readPrioritizeMenu()
        Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                readProgressSettings()
                countProgress()
                readPrioritizeMenu()
                sync?.read()
                // So a check can tell, from the log, how soon the menu shows
                // what the CLI changed.
                if let progress {
                    logger.debug("Counted again after a change: \(progress.inInbox) in the inbox")
                }
            }
        }
        // Cards come due as time passes, without the database changing, and
        // when the device last synced, which the Sync tab says, changes
        // without the database telling.
        Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self else { return }
                countProgress()
                sync?.read()
            }
        }
    }

    /// Saves a capture in the inbox, as the capture window's fields hold it,
    /// unless it repeats a card or a capture: then the result says what it
    /// repeats, for Lucas to expand or ignore it. The menu counts it when the
    /// engine says the database changed.
    func capture(text: String, note: String, source: String) throws(EngineError) -> CaptureResult {
        try engine.capture(text: text, note: note, source: source)
    }

    /// Saves a capture that repeats a card or a capture, which Lucas chose to
    /// expand: attached to the card, or next to the capture.
    func expand(text: String, note: String, source: String) throws(EngineError) {
        try engine.expand(text: text, note: note, source: source)
    }

    /// Starts a review now: the cards it brings, for the review panel to go
    /// through, or why they couldn't be brought.
    func startReviewNow() -> Result<ReviewPanelModel, EngineError> {
        Result { () throws(EngineError) in
            try openPanel(.reviewNow, with: engine.reviewNow(settings))
        }
    }

    /// Whether the review panel shows up on its own now, by what `mac` says,
    /// and with which cards, or why not. The engine decides, and notes an
    /// appearance a suppression holds back in the appearance log.
    func checkAppearance(mac: some DeviceSignals) throws(EngineError) -> AppearanceDecision {
        try engine.checkAppearance(settings, mac: mac)
    }

    /// The latest entries of the appearance log, the latest first, up to
    /// `count`, for Diagnostics.
    func latestAppearances(_ count: Int) throws(EngineError) -> [AppearanceLogEntry] {
        Array(try engine.appearanceLog().suffix(count).reversed())
    }

    /// Starts an appearance with the cards the engine picked, for the review
    /// panel to go through, or why the panel couldn't open them.
    func startAppearance(with cards: [PanelCard]) -> Result<ReviewPanelModel, EngineError> {
        Result { () throws(EngineError) in
            try openPanel(.appearance, with: cards)
        }
    }

    /// Opens the review panel with `cards`, which `trigger` brought: it times
    /// Lucas on the system's continuous clock, and writes the note it offers
    /// to flag a card forgotten often with in the Mac's language.
    private func openPanel(_ trigger: Trigger, with cards: [PanelCard]) throws(EngineError) -> ReviewPanelModel {
        ReviewPanelModel(
            try engine.openPanel(
                trigger, with: cards, settings: settings, clock: ContinuousClock(),
                forgottenOftenNote: { ReviewPanelView.forgottenOftenNote(for: $0) }))
    }

    /// Opens the Cards window on Lucas's cards as they are now, on the ladder
    /// he set in Settings: what he does in it goes through the state.
    func openCardsWindow() -> CardsWindowState {
        engine.openCardsWindow(on: settings.ladder)
    }

    /// Every change to Lucas's cards from now on, by the app or by the
    /// `ficha` CLI, for a window that shows them to read them again.
    func changes() -> AsyncStream<Void> {
        engine.changes()
    }

    /// The engine's time: the system's, or, in Ficha Dev, the time its debug
    /// menu moves forward.
    var now: Date {
        engine.now
    }

    /// Starts the backups the app saves on its own: one now, when it's due,
    /// and then a check every minute, which saves one as the hour, day or week
    /// changes, also when Ficha Dev's debug menu moves the time.
    func startBackups() {
        backups.backUpIfDue(backupSettings)
        Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self else { return }
                backups.backUpIfDue(backupSettings)
            }
        }
    }

    /// Counts again what the menu shows of Lucas's progress. Changes to the
    /// database and the passing of time count it on their own; Ficha Dev's
    /// debug menu asks for it when it moves the time.
    func countProgress() {
        progress = try? engine.progress(settings)
    }

    /// Toggles `tag`'s priority, as the Prioritize submenu does: its cards
    /// come first, or no longer do, from the next appearance, review now or
    /// "See more" on. An open review panel keeps its cards. The submenu reads
    /// the tags again when the engine says the database changed.
    func togglePriority(of tag: String) throws(EngineError) {
        try engine.togglePriority(of: tag)
    }

    /// Makes no tag a priority tag, as the Prioritize submenu's "None" does.
    func clearPriorityTags() throws(EngineError) {
        try engine.clearPriorityTags()
    }

    /// Reads again what the Prioritize submenu offers, whenever the database
    /// changes.
    private func readPrioritizeMenu() {
        prioritizeMenu = try? engine.prioritizeMenu()
    }

    /// Reads again the settings that decide a card's progress, whenever the
    /// database changes, as when another device changed them, or a restore
    /// brought back a copy's. When they can't be read, they stay as they were
    /// (the engine logs why).
    private func readProgressSettings() {
        guard let progress = try? Self.movedInProgressSettings(of: engine), progress != settings.progress else {
            return
        }
        settings.progress = progress
    }

    /// Has the engine keep those of the settings that decide a card's
    /// progress that Lucas changed in Settings from `old`, or keeps why it
    /// couldn't, for Settings to say.
    private func keepProgressSettings(changedFrom old: ProgressSettings) {
        do {
            try engine.saveProgressSettings(settings.progress, changedFrom: old)
        } catch {
            progressSettingsFailure = error
        }
    }

    /// The settings that decide a card's progress, as `engine`'s database
    /// holds them, once the engine moved in those the preferences kept before
    /// they synced, when it held none: at the update, whether the CLI opened
    /// the database first, and after a restore of a copy from before it.
    private static func movedInProgressSettings(of engine: Engine) throws(EngineError) -> ProgressSettings {
        try engine.moveInProgressSettings { Preferences.progressSettingsBeforeSync() }
        return try engine.progressSettings()
    }
}
