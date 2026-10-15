import FichaCore
import FichaData
import Observation

/// The app's way into Lucas's cards: it goes through the engine and keeps what
/// the menu shows up to date, whether the app or the `ficha` CLI changed it.
@Observable
final class AppModel {
    private let engine: Engine
    /// What Ficha Dev's debug menu does, or nil in the real Ficha, which has no
    /// debug menu.
    let debugTools: DebugTools?
    /// The settings the engine decides with: the defaults, until Lucas can
    /// change them.
    let settings = ReviewSettings.defaults
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

    /// Saves a capture in the inbox, as the capture window's fields hold it.
    /// The menu counts it when the engine says the database changed.
    func capture(text: String, note: String, source: String) throws(EngineError) {
        try engine.capture(text: text, note: note, source: source)
    }

    /// Starts a review now: the cards it brings, for the review panel to go
    /// through, or why they couldn't be brought.
    func startReviewNow() -> Result<ReviewPanelModel, EngineError> {
        Result { () throws(EngineError) in
            try ReviewPanelModel(engine: engine, settings: settings)
        }
    }

    /// Counts again what the menu shows of Lucas's progress. Changes to the
    /// database and the passing of time count it on their own; Ficha Dev's
    /// debug menu asks for it when it moves the time.
    func countProgress() {
        progress = try? engine.progress(settings)
    }
}
