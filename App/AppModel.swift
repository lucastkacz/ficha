import FichaCore
import FichaData
import Foundation
import Observation

/// The app's way into Lucas's cards: it goes through the engine and keeps what
/// the menu shows up to date, whether the app or the `ficha` CLI changed it.
@Observable
final class AppModel {
    private let engine: Engine
    /// What Ficha Dev's debug menu does, or nil in the real Ficha, which has no
    /// debug menu.
    let debugTools: DebugTools?
    /// The settings the engine decides with, as Lucas left them in Settings,
    /// which keeps them in the app's preferences. A change applies from the
    /// next decision on, and the menu counts again at once; an open review
    /// panel keeps the settings it opened with.
    var settings = Preferences.reviewSettings() {
        didSet {
            Preferences.save(settings)
            countProgress()
        }
    }
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
    /// What the menu shows of Lucas's progress, or nil when it couldn't be
    /// counted (the engine logs why).
    private(set) var progress: ProgressCounts?
    /// What the menu's Prioritize submenu offers, as the engine reads it, or
    /// nil when it couldn't be read (the engine logs why).
    private(set) var prioritizeMenu: PrioritizeMenu?

    /// The real Ficha's way into Lucas's cards, through `engine`.
    convenience init(engine: Engine) {
        self.init(engine: engine, debugTools: nil)
    }

    /// Ficha Dev's, through the engine its debug tools run on their time.
    convenience init(debugTools: DebugTools) {
        self.init(engine: debugTools.engine, debugTools: debugTools)
    }

    private init(engine: Engine, debugTools: DebugTools?) {
        self.engine = engine
        self.debugTools = debugTools
        backups = engine.openBackups()
        // Listening before counting, so no change falls in between.
        let changes = engine.changes()
        countProgress()
        readPrioritizeMenu()
        Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                countProgress()
                readPrioritizeMenu()
            }
        }
        // Cards come due as time passes, without the database changing.
        Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self else { return }
                countProgress()
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
                forgottenOftenNote: { ReviewPanelView.forgottenOftenNote(times: $0) }))
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
}
