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
    /// What the menu shows of Lucas's progress, or nil when it couldn't be
    /// counted (the engine logs why).
    private(set) var progress: ProgressCounts?

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
        // Listening before counting, so no change falls in between.
        let changes = engine.changes()
        countProgress()
        Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                countProgress()
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
            ReviewPanelModel(engine.openPanel(.reviewNow, with: try engine.reviewNow(settings), settings: settings))
        }
    }

    /// Whether the review panel shows up on its own now, by what `mac` says,
    /// and with which cards, or why not. The engine decides, and notes an
    /// appearance a suppression holds back in the appearance log.
    func checkAppearance(mac: some MacSignals) throws(EngineError) -> AppearanceDecision {
        try engine.checkAppearance(settings, mac: mac)
    }

    /// The latest entries of the appearance log, the latest first, up to
    /// `count`, for Diagnostics.
    func latestAppearances(_ count: Int) throws(EngineError) -> [AppearanceLogEntry] {
        Array(try engine.appearanceLog().suffix(count).reversed())
    }

    /// Starts an appearance with the cards the engine picked, for the review
    /// panel to go through.
    func startAppearance(with cards: [PanelCard]) -> ReviewPanelModel {
        ReviewPanelModel(engine.openPanel(.appearance, with: cards, settings: settings))
    }

    /// The engine's time: the system's, or, in Ficha Dev, the time its debug
    /// menu moves forward.
    var now: Date {
        engine.now
    }

    /// Counts again what the menu shows of Lucas's progress. Changes to the
    /// database and the passing of time count it on their own; Ficha Dev's
    /// debug menu asks for it when it moves the time.
    func countProgress() {
        progress = try? engine.progress(settings)
    }
}
