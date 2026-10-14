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
    /// How many captures wait in the inbox, or nil when they couldn't be
    /// counted (the engine logs why).
    private(set) var capturesInInbox: Int?

    init(engine: Engine, debugTools: DebugTools?) {
        self.engine = engine
        self.debugTools = debugTools
        // Listening before counting, so no change falls in between.
        let changes = engine.changes()
        countCapturesInInbox()
        Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                countCapturesInInbox()
            }
        }
    }

    /// Saves a capture in the inbox, as the capture window's fields hold it.
    /// The menu counts it when the engine says the database changed.
    func capture(text: String, note: String, source: String) throws(EngineError) {
        try engine.capture(text: text, note: note, source: source)
    }

    private func countCapturesInInbox() {
        capturesInInbox = try? engine.inboxCount()
    }
}
