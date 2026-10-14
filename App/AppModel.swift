import FichaData
import Observation

/// The app's way into Lucas's cards: it goes through the engine and keeps what
/// the menu shows up to date.
@Observable
final class AppModel {
    private let engine: Engine
    /// How many captures wait in the inbox, or nil when they couldn't be
    /// counted (the engine logs why).
    private(set) var capturesInInbox: Int?

    init(engine: Engine) {
        self.engine = engine
        countCapturesInInbox()
    }

    /// Saves a capture in the inbox, as the capture window's fields hold it.
    func capture(text: String, note: String, source: String) throws(EngineError) {
        try engine.capture(text: text, note: note, source: source)
        countCapturesInInbox()
    }

    private func countCapturesInInbox() {
        capturesInInbox = try? engine.inboxCount()
    }
}
